import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels
@testable import OpenRouterLanguageModels

@Suite("Executor: tagged reasoning")
struct ExecutorTaggedReasoningTests {
    /// An answer that opens with a block, for splitting at each of its characters.
    static let answer = " <thinking>Plan.</thinking>\n Hello"

    @Test(arguments: ["think", "thinking"])
    func `a block that opens the answer becomes reasoning`(tag: String) async throws {
        let stub = HTTPStub(events(text("<\(tag)>The user wants a greeting.</\(tag)>\nHello!"), done()))

        let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

        #expect(response.content == "Hello!")
        #expect(reasoningTexts(response.transcriptEntries) == ["The user wants a greeting."])
    }

    @Test func `whitespace before the block and after it leaves the answer`() async throws {
        let stub = HTTPStub(events(text("\n  <think> Plan. </think>\n\n"), text("  Hello!"), done()))

        let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

        #expect(response.content == "Hello!")
        #expect(reasoningTexts(response.transcriptEntries) == [" Plan. "])
    }

    @Test(arguments: 1..<ExecutorTaggedReasoningTests.answer.count)
    func `tags split at any character still leave the answer, and no snapshot shows them`(splitPoint: Int) async throws {
        let split = Self.answer.index(Self.answer.startIndex, offsetBy: splitPoint)
        let stub = HTTPStub(events(text(String(Self.answer[..<split])), text(String(Self.answer[split...])), done()))
        let session = LanguageModelSession(model: model(stub))

        var snapshots: [String] = []
        for try await snapshot in session.streamResponse(to: "Say hello.") {
            snapshots.append(snapshot.content)
        }

        #expect(snapshots.last == "Hello")
        #expect(snapshots.allSatisfy { !$0.contains("<") })
        #expect(reasoningTexts(session.transcript) == ["Plan."])
    }

    @Test func `an answer without a block is unchanged`() async throws {
        let stub = HTTPStub(events(text("  Hello"), text(", <b>world</b>"), done()))

        let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

        #expect(response.content == "  Hello, <b>world</b>")
        #expect(reasoningTexts(response.transcriptEntries).isEmpty)
    }

    @Test(arguments: [
        ("Hello <think>A</think>", [String](), "Hello <think>A</think>"),
        ("<think>A</think>Hello <think>B</think>", ["A"], "Hello <think>B</think>"),
    ])
    func `only a block that opens the answer is reasoning`(answer: String, reasoning: [String], content: String) async throws {
        let stub = HTTPStub(events(text(answer), done()))

        let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

        #expect(response.content == content)
        #expect(reasoningTexts(response.transcriptEntries) == reasoning)
    }

    @Test func `a block the answer never closes is all reasoning`() async throws {
        let stub = HTTPStub(events(text("<think>Weighing the"), text(" options</thi"), done("length")))

        let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

        #expect(response.content.isEmpty)
        #expect(reasoningTexts(response.transcriptEntries) == ["Weighing the options</thi"])
    }

    @Test func `a guided answer after a block decodes`() async throws {
        let stub = HTTPStub(
            events(text("<think>A warm dish.</think>\n"), text(#"{"name":"Soup","#), text(#""servings":2}"#), done())
        )
        let session = LanguageModelSession(model: model(stub, parameters: [.structuredOutputs]))

        let response = try await session.respond(to: "A dinner idea.", generating: Dish.self)

        #expect(response.content.name == "Soup")
        #expect(response.content.servings == 2)
        #expect(reasoningTexts(response.transcriptEntries) == ["A warm dish."])
    }

    @Test func `reasoning deltas and a block make one reasoning, in the order they arrive`() async throws {
        let stub = HTTPStub(
            events(
                chunk(["reasoning": "One. "]),
                text("<think>Two. "),
                chunk(["reasoning": "Three. "]),
                text("Four.</think>Hello"),
                done()
            )
        )

        let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

        #expect(response.content == "Hello")
        #expect(reasoningTexts(response.transcriptEntries) == ["One. Two. Three. Four."])
    }

    @Test func `a block goes back as written at the start of the answer's text`() async throws {
        let stub = HTTPStub(
            events(text("<thinking> A greeting. </thinking>\n"), text("Hello!"), done()),
            events(text("Bye."), done())
        )
        let session = LanguageModelSession(model: model(stub))

        _ = try await session.respond(to: "Say hello.")
        _ = try await session.respond(to: "Say bye.")

        let assistant = try #require(try assistantMessages(stub, 1).first)
        #expect(assistant == ["content": "<thinking> A greeting. </thinking>\nHello!", "role": "assistant"])
    }

    @Test func `a block before a tool call goes back with the call`() async throws {
        let stub = HTTPStub(
            events(
                text("<thinking>Look it up.</thinking>"),
                toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                done("tool_calls")
            ),
            events(text("An egg has 100 kcal."), done())
        )
        let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

        let response = try await session.respond(to: "Calories in an egg?")

        #expect(response.content == "An egg has 100 kcal.")
        #expect(reasoningTexts(response.transcriptEntries) == ["Look it up."])
        let assistant = try #require(try assistantMessages(stub, 1).first)
        #expect(assistant["content"] == "<thinking>Look it up.</thinking>")
        #expect(assistant["tool_calls"]?[0]?["id"] == "call_1")
    }

    @Test func `a block that a fallback wrote isn't sent back`() async throws {
        let stub = HTTPStub(
            events(from: "vendor/fallback", text("<think>Plan.</think>Hello!"), done()),
            events(text("Bye."), done())
        )
        let session = LanguageModelSession(model: model(stub, fallbacks: [fallback()]))

        _ = try await session.respond(to: "Say hello.")
        _ = try await session.respond(to: "Say bye.")

        let assistant = try #require(try assistantMessages(stub, 1).first)
        #expect(assistant == ["content": "Hello!", "role": "assistant"])
    }

    @Test func `a block goes back only in the answer's text when details go back beside it`() async throws {
        let detail: JSONValue = ["type": "reasoning.text", "text": "One.", "format": "openai-responses-v1"]
        let stub = HTTPStub(
            events(reasoning(detail), text("<think>Two.</think>Hello!"), done()),
            events(text("Bye."), done())
        )
        let session = LanguageModelSession(model: model(stub))

        let first = try await session.respond(to: "Say hello.")
        _ = try await session.respond(to: "Say bye.")

        #expect(reasoningTexts(first.transcriptEntries) == ["One.Two."])
        let assistant = try #require(try assistantMessages(stub, 1).first)
        #expect(assistant["content"] == "<think>Two.</think>Hello!")
        #expect(assistant["reasoning_details"] == [detail])
        #expect(assistant["reasoning"] == nil)
    }

    @Test func `a block goes back from a saved transcript whose entry names OpenRouter`() async throws {
        let stub = HTTPStub(events(text("Bye."), done()))
        let metadata = ["reasoningOrigin": "openrouter", "taggedReasoning": "<think>Plan.</think>"]
        let session = LanguageModelSession(model: model(stub), transcript: answeredTranscript(reasoningMetadata: metadata))

        _ = try await session.respond(to: "Say bye.")

        let assistant = try #require(try assistantMessages(stub).first)
        #expect(assistant == ["content": "<think>Plan.</think>Hello!", "role": "assistant"])
    }

    @Test(arguments: [ReasoningOrigin?.none, ReasoningOrigin(rawValue: "vendor")])
    func `a block in reasoning that another provider wrote isn't sent back`(origin: ReasoningOrigin?) async throws {
        let stub = HTTPStub(events(text("Bye."), done()))
        // The key saved transcripts hold the block under.
        var metadata = ["taggedReasoning": "<think>Plan.</think>"]
        metadata[ReasoningOrigin.metadataKey] = origin?.rawValue
        let session = LanguageModelSession(model: model(stub), transcript: answeredTranscript(reasoningMetadata: metadata))

        _ = try await session.respond(to: "Say bye.")

        let assistant = try #require(try assistantMessages(stub).first)
        #expect(assistant == ["content": "Hello!", "role": "assistant"])
    }

    @Test func `streamed reasoning names OpenRouter as its origin`() async throws {
        let stub = HTTPStub(events(text("<think>Plan.</think>Hello!"), done()))

        let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

        let reasoning = try #require(reasoningEntries(in: response.transcriptEntries).first)
        #expect(metadataString(reasoning.metadata, "reasoningOrigin") == "openrouter")
    }

    /// A transcript of one answered prompt, whose reasoning entry has the given metadata.
    private func answeredTranscript(reasoningMetadata: [String: String]) -> Transcript {
        Transcript(entries: [
            .prompt(Transcript.Prompt(segments: [.text(.init(content: "Say hello."))])),
            .reasoning(Transcript.Reasoning(metadata: reasoningMetadata, segments: [.text(.init(content: "Plan."))])),
            .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Hello!"))])),
        ])
    }

    /// The text of each reasoning entry.
    private func reasoningTexts(_ entries: some Sequence<Transcript.Entry>) -> [String] {
        reasoningEntries(in: entries).map { plainText($0.segments) }
    }
}

@Generable
private struct Dish {
    var name: String
    var servings: Int
}
