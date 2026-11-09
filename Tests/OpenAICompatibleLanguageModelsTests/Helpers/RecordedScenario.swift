import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

/// An exchange recorded from a preset's provider: what a session asked, which its replay asks again, and what came back.
struct RecordedScenario: Sendable {
    /// The key a scenario's requests carry.
    enum Key: Sendable {
        /// The provider's own key, or none for a server that takes none.
        case provider

        /// A key the provider refuses.
        case refused(String)
    }

    /// The scenario's name, which its fixtures are named after, starting with its provider's.
    let name: String

    /// The preset the scenario was recorded on.
    let provider: OpenAICompatibleProvider

    /// The model on the preset, or on the preset at a stub's address.
    let details: @Sendable (OpenAICompatibleProvider) -> OpenAICompatibleModel

    var tools: [any Tool] = []

    /// How many requests the scenario sends, each answered with what the provider sent back for it.
    var requests = 1

    /// Whether the provider refused the scenario's request, so it ends in a failure rather than an answer.
    var fails = false

    var key = Key.provider

    /// The session's instructions, or `nil` for none.
    var instructions: String?

    let answer: @Sendable (LanguageModelSession, inout String?) async throws -> LanguageModelSession.Usage
}

extension RecordedScenario {
    /// Every recorded scenario, by provider.
    static let all: [RecordedScenario] = gemini + groq + ollama

    static let gemini: [RecordedScenario] = [
        .geminiText, .geminiTools, .geminiGuided, .geminiReasoning, .geminiRefusedKey, .geminiCached,
    ]
    static let groq: [RecordedScenario] = [
        .groqText, .groqTools, .groqGuided, .groqReasoning, .groqRefusedKey, .groqTooLarge, .groqCached,
    ]
    static let ollama: [RecordedScenario] = [
        .ollamaText, .ollamaTools, .ollamaGuided, .ollamaReasoning, .ollamaUnknownModel, .ollamaCached,
    ]

    /// The scenarios whose second turn repeats a long prefix, which the provider caches.
    static let cached: [RecordedScenario] = [.geminiCached, .groqCached, .ollamaCached]

    /// The scenarios that end with an answer, whose transcripts apps save.
    static let answered = all.filter { !$0.fails }
}

// MARK: - Gemini

extension RecordedScenario {
    /// Gemini's Flash-Lite, which reasons unless a request turns reasoning off.
    fileprivate static let flashLite: @Sendable (OpenAICompatibleProvider) -> OpenAICompatibleModel = {
        OpenAICompatibleModel("gemini-3.1-flash-lite", on: $0)
    }

    /// A streamed answer at the model's own reasoning.
    static let geminiText = RecordedScenario(name: "gemini-text", provider: .gemini, details: flashLite) { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(to: "Name one color of the sea.", options: GenerationOptions(maximumResponseTokens: 300)),
            into: &lastSnapshot)
    }

    /// Two calls made at once, then the answer to their outputs.
    static let geminiTools = RecordedScenario(
        name: "gemini-tools", provider: .gemini, details: flashLite, tools: [WeatherTool()], requests: 2
    ) { session, _ in
        try await session.respond(
            to: "What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence.",
            options: GenerationOptions(maximumResponseTokens: 800)
        )
        .usage
    }

    /// A guided answer with the schema features providers differ on.
    static let geminiGuided = RecordedScenario(name: "gemini-guided", provider: .gemini, details: flashLite) { session, _ in
        try await session.respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_000)
        )
        .usage
    }

    /// A streamed answer that reasons hard, which Gemini signs.
    static let geminiReasoning = RecordedScenario(name: "gemini-reasoning", provider: .gemini, details: flashLite) {
        session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "What is 17 times 23? Think it through.", options: GenerationOptions(maximumResponseTokens: 1_200),
                contextOptions: ContextOptions(reasoningLevel: .deep)),
            into: &lastSnapshot)
    }

    /// A key Gemini refuses.
    static let geminiRefusedKey = RecordedScenario(
        name: "gemini-refused-key", provider: .gemini, details: flashLite, fails: true,
        key: .refused("AIza-not-a-key")
    ) { session, _ in
        try await session.respond(to: "Hi").usage
    }
}

// MARK: - Groq

extension RecordedScenario {
    /// GPT-OSS 20B on Groq, which always reasons, at the efforts it takes.
    fileprivate static let gptOSS: @Sendable (OpenAICompatibleProvider) -> OpenAICompatibleModel = {
        OpenAICompatibleModel("openai/gpt-oss-20b", on: $0, reasoning: .mandatory, efforts: [.high, .medium, .low])
    }

    /// The least reasoning, which sends `low`.
    fileprivate static let light = ContextOptions(reasoningLevel: .light)

    /// A streamed answer with the least reasoning.
    static let groqText = RecordedScenario(
        name: "groq-text", provider: .groq, details: gptOSS
    ) { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "Name one color of the sea.", options: GenerationOptions(maximumResponseTokens: 300), contextOptions: light),
            into: &lastSnapshot)
    }

    /// A call of a tool in each of two rounds, then the answer to their outputs, with the model's reasoning going back
    /// with the first.
    static let groqTools = RecordedScenario(
        name: "groq-tools", provider: .groq, details: gptOSS, tools: [WeatherTool()], requests: 3
    ) { session, _ in
        try await session.respond(
            to: "What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence.",
            options: GenerationOptions(maximumResponseTokens: 800), contextOptions: light
        )
        .usage
    }

    /// A guided answer with the schema features providers differ on.
    static let groqGuided = RecordedScenario(
        name: "groq-guided", provider: .groq, details: gptOSS
    ) { session, _ in
        try await session.respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_500),
            contextOptions: light
        )
        .usage
    }

    /// A streamed answer that reasons at a moderate effort.
    static let groqReasoning = RecordedScenario(
        name: "groq-reasoning", provider: .groq, details: gptOSS
    ) { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "What is 17 times 23? Think it through.", options: GenerationOptions(maximumResponseTokens: 2_000),
                contextOptions: ContextOptions(reasoningLevel: .moderate)),
            into: &lastSnapshot)
    }

    /// A key Groq refuses.
    static let groqRefusedKey = RecordedScenario(
        name: "groq-refused-key", provider: .groq, details: gptOSS, fails: true, key: .refused("gsk-not-a-key")
    ) { session, _ in
        try await session.respond(to: "Hi", contextOptions: light).usage
    }

    /// A prompt larger than the free plan's tokens a minute, which no wait lets through.
    static let groqTooLarge = RecordedScenario(
        name: "groq-too-large", provider: .groq, details: gptOSS, fails: true
    ) { session, _ in
        try await session.respond(
            to: String(repeating: "word ", count: 12_000), options: GenerationOptions(maximumResponseTokens: 16), contextOptions: light
        )
        .usage
    }
}

// MARK: - Ollama

extension RecordedScenario {
    /// Qwen3 0.6B, which reasons unless a request turns reasoning off.
    fileprivate static let qwen: @Sendable (OpenAICompatibleProvider) -> OpenAICompatibleModel = {
        OpenAICompatibleModel("qwen3:0.6b", on: $0, reasoning: .onByDefault)
    }

    /// Qwen3.5 4B, which keeps to a schema where the smaller model doesn't.
    private static let largerQwen: @Sendable (OpenAICompatibleProvider) -> OpenAICompatibleModel = {
        OpenAICompatibleModel("qwen3.5:4b", on: $0, reasoning: .onByDefault)
    }

    /// No reasoning, which sends `none`.
    fileprivate static let unreasoned = ContextOptions(reasoningLevel: .off)

    /// A streamed answer without reasoning.
    static let ollamaText = RecordedScenario(name: "ollama-text", provider: .ollama, details: qwen) { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "Name one color of the sea.", options: GenerationOptions(maximumResponseTokens: 300), contextOptions: unreasoned),
            into: &lastSnapshot)
    }

    /// A call of a tool after reasoning, then the answer to its output, with the reasoning going back with the call.
    static let ollamaTools = RecordedScenario(
        name: "ollama-tools", provider: .ollama, details: qwen, tools: [WeatherTool()], requests: 2
    ) { session, _ in
        try await session.respond(
            to: "What's the temperature in Lisbon? Use the tool.", options: GenerationOptions(maximumResponseTokens: 1_500)
        )
        .usage
    }

    /// A guided answer with the schema features providers differ on.
    static let ollamaGuided = RecordedScenario(name: "ollama-guided", provider: .ollama, details: largerQwen) { session, _ in
        try await session.respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_500),
            contextOptions: unreasoned
        )
        .usage
    }

    /// A streamed answer that reasons.
    static let ollamaReasoning = RecordedScenario(name: "ollama-reasoning", provider: .ollama, details: qwen) {
        session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "What is 12 plus 30? Reply with the number only.", options: GenerationOptions(maximumResponseTokens: 1_500)),
            into: &lastSnapshot)
    }

    /// A model the server doesn't have.
    private static let missingModel: @Sendable (OpenAICompatibleProvider) -> OpenAICompatibleModel = {
        OpenAICompatibleModel("no-such-model:1b", on: $0)
    }

    /// A request for a model the server doesn't have.
    static let ollamaUnknownModel = RecordedScenario(
        name: "ollama-unknown-model", provider: .ollama, details: missingModel, fails: true
    ) { session, _ in
        try await session.respond(to: "Hi").usage
    }
}

// MARK: - Caching

extension RecordedScenario {
    /// Instructions of about ten tokens a copy, which no earlier request sent, so the first turn finds nothing cached.
    static func longInstructions(copies: Int) -> String {
        "Run 1. " + String(repeating: "Answer in one short sentence, and stay polite. ", count: copies)
    }

    /// Two turns after the same long instructions, the second of which repeats the first's whole request as its prefix.
    private static func twoTurns(
        reasoning contextOptions: ContextOptions
    ) -> @Sendable (LanguageModelSession, inout String?) async throws -> LanguageModelSession.Usage {
        { session, _ in
            let options = GenerationOptions(maximumResponseTokens: 300)
            _ = try await session.respond(to: "Name one color of the sea.", options: options, contextOptions: contextOptions)
            return try await session.respond(to: "And one of the sky?", options: options, contextOptions: contextOptions).usage
        }
    }

    /// Instructions of about 6,000 tokens, then a second turn.
    static let geminiCached = RecordedScenario(
        name: "gemini-cached", provider: .gemini, details: flashLite, requests: 2,
        instructions: longInstructions(copies: 600), answer: twoTurns(reasoning: ContextOptions()))

    /// Instructions of about 3,000 tokens, then a second turn.
    static let groqCached = RecordedScenario(
        name: "groq-cached", provider: .groq, details: gptOSS, requests: 2,
        instructions: longInstructions(copies: 300), answer: twoTurns(reasoning: light))

    /// Instructions of about 2,000 tokens, then a second turn.
    static let ollamaCached = RecordedScenario(
        name: "ollama-cached", provider: .ollama, details: qwen, requests: 2,
        instructions: longInstructions(copies: 200), answer: twoTurns(reasoning: unreasoned))
}

// MARK: - Replaying

extension RecordedScenario {
    /// A session on a model, as the scenario starts it.
    func session(with model: some LanguageModel) -> LanguageModelSession {
        if let instructions {
            return LanguageModelSession(model: model, tools: tools, instructions: instructions)
        }
        return LanguageModelSession(model: model, tools: tools)
    }

    /// The scenario's model on the preset at a stub's address, with the key it was recorded with.
    func model(_ stub: HTTPStub) -> OpenAICompatibleLanguageModel {
        let auth: OpenAICompatibleAuthentication =
            switch key {
            case .provider: provider.name == "Ollama" ? .unauthenticated : .apiKey { "sk-test" }
            case .refused(let refused): .apiKey { refused }
            }
        return OpenAICompatibleLanguageModel(
            details(provider.at(stub.baseURL)), session: stub.session, configuration: .stubbed, auth: auth)
    }
}

extension RecordedScenario: CustomTestStringConvertible {
    var testDescription: String { name }
}

extension RecordedScenario {
    /// A stub that answers each request with what the provider sent back for it: its status, the headers the package
    /// reads, with the request id swapped as the body's is, and its body.
    func stub() throws -> HTTPStub {
        let replies = try JSONDecoder().decode([String: Reply].self, from: Bundle.module.fixture("Recorded/replies.json"))
        return HTTPStub(
            responses: try (1...requests).map { index in
                let name = "\(name).\(index)"
                let reply = try #require(replies[name], "Recorded/replies.json has no reply \(name).")
                let kind = reply.headers["content-type"]?.contains("event-stream") == true ? "sse" : "json"
                let body = try Bundle.module.fixture("Recorded/\(name).\(kind)")
                return StubResponse(status: reply.status, headers: reply.headers, chunks: [body])
            })
    }

    /// What the provider sent back for one request, beside its body.
    private struct Reply: Decodable {
        let status: Int
        let headers: [String: String]
    }
}

extension ExactExchange {
    /// Replays a recorded exchange: the session asks what it asked, and the stub answers with what the provider sent.
    init(replaying scenario: RecordedScenario) async throws {
        let stub = try scenario.stub()
        await self.init(stub, scenario.session(with: scenario.model(stub)), recordingHeaders: /^X-/, answer: scenario.answer)
    }
}
