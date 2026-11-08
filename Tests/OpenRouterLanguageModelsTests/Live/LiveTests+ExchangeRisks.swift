import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    /// Probes of the ways a request may break on some models. A probe that fails today runs in a known issue, so it
    /// reports once the problem is fixed, and one that passes stays as a regression test. Calls that share an index are
    /// probed by the parallel calls in Tools.
    @Suite("Exchange risks")
    struct ExchangeRisks {
        /// Models whose hosts need the tool definitions whenever the history has tool calls: Anthropic, and Bedrock,
        /// the only host of Nova.
        static let toolHistoryModels = [LiveModel(.anthropicClaudeHaiku5_5), LiveModel(.amazonNovaMicroV1)]

        /// Models that reason in plain text, which some hosts stream as `reasoning` next to empty `reasoning_details`.
        static let plainTextReasoningModels = [
            LiveModel(.deepseekDeepseekV4Flash, reasoningLevel: .deep),
            LiveModel(.zAiGlm5_3Flash),
            LiveModel(.xiaomiMimoV2_6Flash),
            LiveModel(.qwenQwen3_7Flash),
        ]

        /// Models a transcript moves to with encrypted reasoning that another model wrote.
        static let handoffModels = [LiveModel(.deepseekDeepseekV4Flash), LiveModel(.googleGemini3_1FlashLite)]

        /// With tool calls disallowed, Foundation Models sends no tools, so a history with tool calls goes out without
        /// their definitions, and Anthropic and Bedrock still accept it.
        @Test(arguments: toolHistoryModels)
        func `a turn with tools disallowed after a tool call keeps the history valid`(model: LiveModel) async throws {
            let session = LanguageModelSession(model: model.languageModel, tools: [WeatherTool()])
            defer { record(session.transcript, named: "transcript.txt") }
            _ = try await session.respond(to: "How warm is it in Lisbon right now? Use the tool.")
            try #require(!session.transcript.toolCalls.isEmpty)

            let response = try await session.respond(
                to: "Which city did you just check? Reply with its name only.",
                options: GenerationOptions(toolCallingMode: .disallowed)
            )

            #expect(response.content.localizedCaseInsensitiveContains("Lisbon"))
        }

        /// Some hosts stream reasoning as `reasoning` text next to an empty `reasoning_details`, and the text still
        /// arrives.
        @Test(arguments: plainTextReasoningModels)
        func `reasoning in plain text reaches the transcript`(model: LiveModel) async throws {
            let session = LanguageModelSession(model: model.languageModel)

            let response = try await session.respond(
                to: "What is 17 × 23? Reply with the number only.",
                contextOptions: ContextOptions(reasoningLevel: model.reasoningLevel)
            )

            record(response.transcriptEntries, named: "entries.txt")
            #expect(response.content.contains("391"))
            try #require(response.usage.output.reasoningTokenCount > 0, "The model didn't reason.")
            #expect(reasoningEntries(in: response.transcriptEntries).contains { !plainText($0.segments).isEmpty })
        }

        /// A host that repeats a call's arguments gives `{…}{…}`, which isn't one JSON object. Kimi K2.6 is known to
        /// repeat a call.
        @Test func `a Kimi tool call arrives once with arguments that parse`() async throws {
            let session = LanguageModelSession(model: LiveModel(.moonshotaiKimiK2_6).languageModel, tools: [WeatherTool()])

            let response = try await session.respond(
                to: "How warm is it in Lisbon right now? Use the tool.",
                contextOptions: ContextOptions(reasoningLevel: .off)
            )

            record(session.transcript, named: "transcript.txt")
            #expect(try session.transcript.weatherCities().count == 1)
            #expect(response.content.contains("17"))
        }

        /// MiniMax M2.5 writes `<think>` inside the content on its own host, and it stays out of the answer. The host
        /// takes no schema, so the probe reads plain text.
        @Test func `MiniMax's own host keeps its thinking out of the answer`() async throws {
            let routing = OpenRouterRouting(order: ["minimax"])
            let session = LanguageModelSession(model: LiveModel(.minimaxMinimaxM2_5).languageModel(routing: routing))

            let response = try await session.respond(to: "What is 17 × 23? Reply with the number only.")

            record(answerMetadata(response), named: "metadata.txt")
            record(response.transcriptEntries, named: "entries.txt")
            #expect(response.content.contains("391"))
            expectThinkingMovedToReasoning(in: response.transcriptEntries)
        }

        /// Nova writes `<thinking>` before it calls a tool. The block goes back at the start of the answer's text, and
        /// Bedrock takes it, so the tool loop ends with the tool's answer.
        @Test func `Nova keeps its thinking out of the answer through a tool loop`() async throws {
            let session = LanguageModelSession(model: LiveModel(.amazonNovaMicroV1).languageModel, tools: [WeatherTool()])

            let response = try await session.respond(to: "How warm is it in Lisbon right now? Use the tool.")

            record(session.transcript, named: "transcript.txt")
            #expect(response.content.contains("17"))
            expectThinkingMovedToReasoning(in: response.transcriptEntries)
        }

        /// Expects no answer among the entries to hold a `<think>` or `<thinking>` tag, and a reasoning entry to hold
        /// the text between them.
        private func expectThinkingMovedToReasoning(in entries: some Sequence<Transcript.Entry>) {
            let answers = entries.compactMap { entry in if case .response(let answer) = entry { plainText(answer.segments) } else { nil } }
            #expect(!answers.contains { $0.contains("<think") })
            #expect(reasoningEntries(in: entries).contains { !plainText($0.segments).isEmpty })
        }

        /// Tool-call ids from another host go back as they are, though Mistral takes only 9 letters and digits.
        /// Mistral's own host accepts them through OpenRouter all the same.
        @Test func `another host's tool-call ids work on Mistral's own host`() async throws {
            let first = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel, tools: [WeatherTool()])
            _ = try await first.respond(to: "How warm is it in Lisbon right now? Use the tool.")
            try #require(!first.transcript.toolCalls.isEmpty)
            let model = LiveModel(.mistralaiMistralNemo).languageModel(routing: LiveTests.mistralHost)
            let second = LanguageModelSession(model: model, tools: [WeatherTool()], transcript: first.transcript)

            defer { record(second.transcript, named: "transcript.txt") }

            let response = try await second.respond(to: "And in Porto? Use the tool.")

            #expect(response.content.contains("17"))
        }

        /// An id is made up as `call_<UUID>` when the model sends none, which Mistral would reject on the next request,
        /// so Mistral's own ids must arrive.
        @Test func `a tool round trip on Mistral's own host keeps its 9-character ids`() async throws {
            let model = LiveModel(.mistralaiMistralNemo).languageModel(routing: LiveTests.mistralHost)
            let session = LanguageModelSession(model: model, tools: [WeatherTool()])

            let response = try await session.respond(to: "How warm is it in Lisbon right now? Use the tool.")

            record(session.transcript, named: "transcript.txt")
            let ids = session.transcript.toolCalls.map(\.id)
            #expect(!ids.isEmpty)
            #expect(ids.allSatisfy { $0.wholeMatch(of: /[A-Za-z0-9]{9}/) != nil })
            #expect(response.content.contains("17"))
        }

        /// An empty tool output goes out as `content: ""`, and Bedrock, which rejects blank text, still accepts it.
        @Test func `an empty tool output is accepted on Bedrock`() async throws {
            let session = LanguageModelSession(model: LiveModel(.amazonNovaMicroV1).languageModel, tools: [SilentTool()])
            defer { record(session.transcript, named: "transcript.txt") }

            let response = try await session.respond(to: "Log a visit to Lisbon with the tool, then reply with OK.")

            #expect(session.transcript.toolCalls.contains { $0.toolName == "logVisit" }, "The model never called the tool.")
            #expect(!response.content.isEmpty)
        }

        /// `.required` is refused before any request on a model without `tool_choice`, such as Nova, which would
        /// otherwise answer without a tool call.
        @Test func `a required tool call is refused on a model without tool_choice`() async throws {
            let session = LanguageModelSession(model: LiveModel(.amazonNovaMicroV1).languageModel, tools: [WeatherTool()])

            let error = try await #require(throws: LanguageModelError.self) {
                try await session.respond(to: "Say hello.", options: GenerationOptions(toolCallingMode: .required))
            }

            record(error, named: "error.txt")
            guard case .unsupportedCapability(let unsupported) = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(unsupported.capability == .toolCalling)
        }

        /// A request with a schema asks for hosts that honor every parameter, and Kimi K2.6 still has one for a strict
        /// schema.
        @Test func `a strict schema finds a Kimi host`() async throws {
            let session = LanguageModelSession(model: LiveModel(.moonshotaiKimiK2_6).languageModel)

            let trip = try await session.respond(
                to: "Plan a short trip to Lisbon.",
                generating: Trip.self,
                contextOptions: ContextOptions(includeSchemaInPrompt: true, reasoningLevel: .off)
            ).content

            record(trip, named: "trip.txt")
            #expect(trip.activities.count == 3)
        }

        /// Reasoning that neither the model nor a fallback wrote still goes back, so a transcript moved to another model
        /// resends the first model's encrypted reasoning, which DeepSeek and Gemini accept.
        @Test(arguments: handoffModels)
        func `a transcript with another model's encrypted reasoning moves to a new model`(model: LiveModel) async throws {
            let first = LanguageModelSession(model: LiveModel(.openaiGpt5Nano).languageModel, tools: [WeatherTool()])
            _ = try await first.respond(
                to: "How warm is it in Lisbon right now? Use the tool.",
                contextOptions: ContextOptions(reasoningLevel: .light)
            )
            let details = try reasoningEntries(in: first.transcript).flatMap(reasoningDetails(of:))
            try #require(details.contains { $0["type"] == "reasoning.encrypted" }, "gpt-5-nano sent no encrypted reasoning.")
            let second = LanguageModelSession(model: model.languageModel, tools: [WeatherTool()], transcript: first.transcript)
            defer { record(second.transcript, named: "transcript.txt") }

            let response = try await second.respond(to: "And in Porto? Use the tool.")

            #expect(response.content.contains("17"))
        }

        /// Unsigned reasoning text without a format counts as Anthropic's and is dropped when it's replayed, so GLM's
        /// reasoning goes back only while GLM names a format of its own. The next request goes to a stub, which shows
        /// what would go back.
        @Test func `GLM's unsigned reasoning goes back on the next request`() async throws {
            let glm = LiveModel(.zAiGlm5_3Flash)
            let session = LanguageModelSession(model: glm.languageModel, tools: [WeatherTool()])
            _ = try await session.respond(
                to: "How warm is it in Lisbon right now? Use the tool.",
                contextOptions: ContextOptions(reasoningLevel: glm.reasoningLevel)
            )
            let reasoning = reasoningEntries(in: session.transcript)
            record(try reasoning.map(reasoningDetails(of:)), named: "reasoning-details.txt")
            guard reasoning.contains(where: { !plainText($0.segments).isEmpty }) else {
                try Test.cancel("GLM sent no reasoning text, so there's nothing to replay.")
            }

            let stub = HTTPStub(events(text("OK"), done()))
            let replay = OpenRouterLanguageModel(
                glm.details, session: stub.session,
                auth: .proxied(baseURL: stub.baseURL, headers: { ["Authorization": "Bearer sk-or-replay"] }))
            _ = try await LanguageModelSession(model: replay, tools: [WeatherTool()], transcript: session.transcript).respond(to: "Thanks.")

            let assistant = try assistantMessages(stub)
            record(assistant, named: "replayed-assistant-messages.txt")
            #expect(assistant.contains { $0["reasoning"]?.stringValue?.isEmpty == false })
            #expect(assistant.contains { elements($0["reasoning_details"]).contains { $0["type"] == "reasoning.text" } })
        }

        /// Perplexity's Sonar bills a search on every request, on top of its tokens, so only the cost that the
        /// answer reports says what it cost.
        @Test func `a Perplexity answer reports what it cost`() async throws {
            let session = LanguageModelSession(model: LiveModel(.perplexitySonar).languageModel)

            let response = try await session.respond(to: "Reply with the single word: hello", options: LiveTests.short)

            record(answerMetadata(response), named: "metadata.txt")
            let cost = try #require(response.usage.openRouter.cost)
            #expect(cost > 0)
        }
    }
}

/// A tool whose output is empty.
private struct SilentTool: Tool {
    let name = "logVisit"
    let description = "Logs a visit to a city. It returns nothing."

    @Generable
    struct Arguments {
        @Guide(description: "The city's name.")
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        ""
    }
}
