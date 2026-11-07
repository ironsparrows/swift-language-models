import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Tagged reasoning")
    struct TaggedReasoning {
        @Test(arguments: ["think", "thinking"])
        func `a block that opens the answer becomes reasoning`(tag: String) async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("<\(tag)>The user wants a greeting.</\(tag)>\nHello!"), finishChunk()))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Say hello.")

            #expect(response.content == "Hello!")
            #expect(reasoningTexts(response.transcriptEntries) == ["The user wants a greeting."])
        }

        @Test func `an answer without a block has no reasoning`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("  Hello"), textChunk(", <b>world</b>"), finishChunk()))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Say hello.")

            #expect(response.content == "  Hello, <b>world</b>")
            #expect(reasoningTexts(response.transcriptEntries).isEmpty)
        }

        @Test func `a block the answer never closes is all reasoning, with the text held back at its end`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("<think>Weighing the"), textChunk(" options</thi"), finishChunk("length")))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Say hello.")

            #expect(response.content.isEmpty)
            #expect(reasoningTexts(response.transcriptEntries) == ["Weighing the options</thi"])
        }

        @Test func `a guided answer after a block decodes`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(textChunk("<think>A fair score.</think>\n"), textChunk(#"{"stars":"#), textChunk("4}"), finishChunk())
            )

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)

            #expect(response.content.stars == 4)
            #expect(reasoningTexts(response.transcriptEntries) == ["A fair score."])
        }

        @Test func `the provider's reasoning and a block make one reasoning, in the order they arrive`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    reasoningChunk("One. "), textChunk("<think>Two. "), reasoningChunk("Three. "), textChunk("Four.</think>Hello"),
                    finishChunk()))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

            #expect(response.content == "Hello")
            #expect(reasoningTexts(response.transcriptEntries) == ["One. Two. Three. Four."])
        }

        @Test func `a block goes back as written at the start of the answer's text`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(textChunk("<thinking> A greeting. </thinking>\n"), textChunk("Hello!"), finishChunk()),
                chatCompletionsEvents(textChunk("Bye."), finishChunk()))
            let session = LanguageModelSession(model: plainModel(stub))

            _ = try await session.respond(to: "Say hello.")
            _ = try await session.respond(to: "Say bye.")

            let assistant = try #require(try assistantMessages(stub, request: 1).first)
            #expect(assistant == ["content": "<thinking> A greeting. </thinking>\nHello!", "role": "assistant"])
        }

        @Test func `a block before a tool call goes back with the call`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    textChunk("<thinking>Look it up.</thinking>"),
                    toolCallChunk(id: "call_1", name: "lookUp", arguments: #"{"word":"egg"}"#),
                    finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("An egg is food."), finishChunk()))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])

            let response = try await session.respond(to: "Define egg.")

            #expect(response.content == "An egg is food.")
            #expect(reasoningTexts(response.transcriptEntries) == ["Look it up."])
            let assistant = try #require(try assistantMessages(stub, request: 1).first)
            #expect(assistant["content"] == "<thinking>Look it up.</thinking>")
            #expect(assistant["tool_calls"]?[0]?["id"] == "call_1")
        }

        @Test(arguments: [
            (String?.some("test"), "<think>Count.</think>\nSeven."),
            (nil, "Seven."),
            ("other", "Seven."),
        ])
        func `a block goes back at the start of the answer's text only from the provider's own reasoning`(origin: String?, content: String)
            throws
        {
            // The keys saved transcripts hold the block and its origin under.
            var metadata = ["taggedReasoning": "<think>Count.</think>\n"]
            metadata["reasoningOrigin"] = origin
            let entries: [Transcript.Entry] = [
                prompt(text("Hi")), .reasoning(Transcript.Reasoning(metadata: metadata, segments: [text("Count.")])),
                .response(Transcript.Response(assetIDs: [], segments: [text("Seven.")])),
            ]

            let assistant = messages(try ChatCompletionsSentRequest(generationRequest(entries)).body).last

            #expect(assistant?["content"] == .string(content))
        }
    }
}
