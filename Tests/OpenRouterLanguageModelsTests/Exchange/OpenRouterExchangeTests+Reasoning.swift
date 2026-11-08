import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Reasoning")
    struct Reasoning {
        @Test func `a typed effort becomes the effort OpenRouter sends`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<HighMediumLow> = model(stub, efforts: [.high, .medium, .low])
            let profile = LanguageModelSession.Profile { Instructions("Think.") }.model(model, effort: .high)

            _ = try await LanguageModelSession(profile: profile).respond(to: "Hi")

            #expect(try body(stub)["reasoning"] == ["effort": "high"])
        }

        @Test(arguments: [
            (ContextOptions.ReasoningLevel.deep, "high"),
            (.custom("max"), "high"),
            (.light, "low"),
        ])
        func `a level moves to the nearest effort the model accepts`(level: ContextOptions.ReasoningLevel, effort: String) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<HighMediumLow> = model(stub, efforts: [.high, .medium, .low])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: level))

            #expect(try body(stub)["reasoning"] == ["effort": .string(effort)])
        }

        @Test(arguments: [(ContextOptions.ReasoningLevel.deep, true), (.off, false)])
        func `a model whose effort can't be chosen is told whether to reason`(level: ContextOptions.ReasoningLevel, enabled: Bool)
            async throws
        {
            let stub = HTTPStub(events(text("Hi"), done()))

            _ = try await LanguageModelSession(model: model(stub)).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: level))

            #expect(try body(stub)["reasoning"] == ["enabled": .bool(enabled)])
        }

        @Test(arguments: [
            (ContextOptions.ReasoningLevel.deep, JSONValue?.some(["enabled": true])),
            (.off, nil),
        ])
        func `a model that always reasons can't be told to stop`(level: ContextOptions.ReasoningLevel, reasoning: JSONValue?) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, reasoning: .mandatory)

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: level))

            #expect(try body(stub)["reasoning"] == reasoning)
        }

        @Test(arguments: [(ContextOptions.ReasoningLevel.deep, "high"), (.off, "low")])
        func `a model that always reasons, with efforts, gets the nearest effort, even for off`(
            level: ContextOptions.ReasoningLevel,
            effort: String
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<HighMediumLow> = model(stub, reasoning: .mandatory, efforts: [.high, .medium, .low])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: level))

            #expect(try body(stub)["reasoning"] == ["effort": .string(effort)])
        }

        @Test func `a model with off among its efforts is sent none`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<HighLowOff> = model(stub, efforts: [.high, .low, .off])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: .off))

            #expect(try body(stub)["reasoning"] == ["effort": "none"])
        }

        @Test(arguments: [ModelReasoning.offByDefault, .onByDefault])
        func `off turns reasoning off for a model that can stop, without none among its efforts`(reasoning: ModelReasoning) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<HighMediumLow> = model(stub, reasoning: reasoning, efforts: [.high, .medium, .low])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: .off))

            #expect(try body(stub)["reasoning"] == ["enabled": false])
        }

        @Test(arguments: [ContextOptions.ReasoningLevel.deep, .light, .off, .custom("max")])
        func `a model that doesn't reason is refused a reasoning level before any request`(level: ContextOptions.ReasoningLevel)
            async throws
        {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, reasoning: .unsupported)

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: level))
            }

            guard case .unsupportedCapability = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(stub.requests.isEmpty)
        }

        @Test(arguments: [ModelReasoning.unsupported, .offByDefault])
        func `no reasoning level sends no reasoning setting`(reasoning: ModelReasoning) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, reasoning: reasoning)

            _ = try await LanguageModelSession(model: model).respond(to: "Hi")

            #expect(try body(stub)["reasoning"] == nil)
        }

        @Test func `streamed reasoning becomes a reasoning entry and goes back on the next turn`() async throws {
            let stub = HTTPStub(
                events(
                    reasoning(["type": "reasoning.text", "text": "Eggs are ", "format": "anthropic-claude-v1", "index": 0]),
                    reasoning(["type": "reasoning.text", "text": "light.", "index": 0]),
                    reasoning(["type": "reasoning.text", "signature": "sig-1", "index": 0]),
                    reasoning(["type": "reasoning.encrypted", "data": "blob", "index": 1]),
                    text("About 70 kcal."),
                    done(reasoning: 12)
                ),
                events(text("Yes."), done())
            )
            let session = LanguageModelSession(model: model(stub))

            let first = try await session.respond(to: "Calories in an egg?")
            _ = try await session.respond(to: "Sure?")

            #expect(reasoningTexts(first.transcriptEntries) == ["Eggs are light."])
            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["content"] == "About 70 kcal.")
            #expect(assistant["reasoning"] == "Eggs are light.")
            #expect(
                assistant["reasoning_details"] == [
                    [
                        "format": "anthropic-claude-v1", "index": 0, "signature": "sig-1", "text": "Eggs are light.",
                        "type": "reasoning.text",
                    ],
                    ["data": "blob", "index": 1, "type": "reasoning.encrypted"],
                ]
            )
        }

        @Test func `plain reasoning text is shown, and goes back as the message's reasoning since it has no details`() async throws {
            let stub = HTTPStub(
                events(chunk(["reasoning": "Eggs are light."]), text("About 70 kcal."), done()), events(text("Yes."), done()))
            let session = LanguageModelSession(model: model(stub))

            let first = try await session.respond(to: "Calories in an egg?")
            _ = try await session.respond(to: "Sure?")

            #expect(reasoningTexts(first.transcriptEntries) == ["Eggs are light."])
            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant == ["content": "About 70 kcal.", "reasoning": "Eggs are light.", "role": "assistant"])
        }

        @Test func `reasoning details win over plain reasoning text in the same delta`() async throws {
            let detail: JSONValue = ["type": "reasoning.text", "text": "Detailed.", "signature": "sig-1"]
            let stub = HTTPStub(events(chunk(["reasoning": "Plain.", "reasoning_details": [detail]]), text("Hi"), done()))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            #expect(reasoningTexts(response.transcriptEntries) == ["Detailed."])
        }

        @Test func `plain reasoning text shows when the same delta's details list is empty`() async throws {
            let stub = HTTPStub(
                events(chunk(["reasoning": "Eggs are light.", "reasoning_details": []]), text("About 70 kcal."), done()),
                events(text("Yes."), done())
            )
            let session = LanguageModelSession(model: model(stub))

            let first = try await session.respond(to: "Calories in an egg?")
            _ = try await session.respond(to: "Sure?")

            #expect(reasoningTexts(first.transcriptEntries) == ["Eggs are light."])
            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["reasoning_details"] == [])
            #expect(assistant["reasoning"] == "Eggs are light.")
        }

        @Test func `reasoning after the answer started still goes back in its details`() async throws {
            let stub = HTTPStub(
                events(
                    reasoning(["type": "reasoning.text", "text": "Eggs are light.", "format": "anthropic-claude-v1"]),
                    text("About 70 kcal."),
                    reasoning(["type": "reasoning.text", "text": " Late.", "signature": "sig-1"]),
                    done()
                ),
                events(text("Yes."), done())
            )
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Calories in an egg?")
            _ = try await session.respond(to: "Sure?")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(
                assistant["reasoning_details"] == [
                    ["format": "anthropic-claude-v1", "signature": "sig-1", "text": "Eggs are light. Late.", "type": "reasoning.text"]
                ]
            )
        }

        @Test func `summaries stream into one summary`() async throws {
            let stub = HTTPStub(
                events(
                    reasoning(["type": "reasoning.summary", "summary": "Weighed ", "format": "openai-responses-v1"]),
                    reasoning(["type": "reasoning.summary", "summary": "the options."]),
                    text("Soup."),
                    done()
                ),
                events(text("Yes."), done())
            )
            let session = LanguageModelSession(model: model(stub))

            let first = try await session.respond(to: "Dinner?")
            _ = try await session.respond(to: "Sure?")

            #expect(reasoningTexts(first.transcriptEntries) == ["Weighed the options."])
            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(
                assistant["reasoning_details"] == [
                    ["format": "openai-responses-v1", "summary": "Weighed the options.", "type": "reasoning.summary"]
                ]
            )
            #expect(assistant["reasoning"] == "Weighed the options.")
        }

        @Test(arguments: [
            (JSONValue?.some("anthropic-claude-v1"), false),
            ("google-gemini-v1", false),
            (nil, false),
            ("openai-responses-v1", true),
        ])
        func `unsigned reasoning text goes back only in formats that take it`(format: JSONValue?, isSent: Bool) async throws {
            let detail: JSONValue = ["type": "reasoning.text", "text": "Unsigned.", "format": format]
            let stub = HTTPStub(events(reasoning(detail), text("Hi"), done()), events(text("Again."), done()))
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Hi")
            _ = try await session.respond(to: "Again?")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["reasoning_details"] == .array(isSent ? [detail] : []))
            #expect(assistant["reasoning"] == (isSent ? "Unsigned." : nil))
        }

        @Test func `summaries of different blocks stay apart`() async throws {
            let stub = HTTPStub(
                events(
                    reasoning(["type": "reasoning.summary", "summary": "First.", "index": 0]),
                    reasoning(["type": "reasoning.summary", "summary": "Second.", "index": 1]),
                    text("Soup."),
                    done()
                ),
                events(text("Yes."), done())
            )
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Dinner?")
            _ = try await session.respond(to: "Sure?")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(
                assistant["reasoning_details"] == [
                    ["index": 0, "summary": "First.", "type": "reasoning.summary"],
                    ["index": 1, "summary": "Second.", "type": "reasoning.summary"],
                ]
            )
        }

        /// The text of each reasoning entry.
        private func reasoningTexts(_ entries: some Sequence<Transcript.Entry>) -> [String] {
            entries.compactMap { entry in
                if case .reasoning(let reasoning) = entry { plainText(reasoning.segments) } else { nil }
            }
        }
    }
}
