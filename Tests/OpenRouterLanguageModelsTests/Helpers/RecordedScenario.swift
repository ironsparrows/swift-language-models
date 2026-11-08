import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenRouterLanguageModels

/// An exchange recorded from OpenRouter: what a session asked, which its replay asks again, and what came back.
struct RecordedScenario: Sendable {
    /// What OpenRouter sent back for one request.
    enum Reply: Sendable {
        case stream
        case streamWith(headers: [String: String])
        case failure(status: Int)
    }

    let name: String
    let id: OpenRouterModelID
    var reasoning = ModelReasoning.offByDefault
    var efforts: [ContextOptions.ReasoningLevel] = []
    var options = OpenRouterOptions()
    var tools: [any Tool] = []
    var replies: [Reply] = [.stream]
    var parameters = chatParameters
    var inputs: Set<OpenRouterInputModality> = [.text]
    var cachesOnlyMarkedPrompts = false
    var fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>] = []
    var serverTools: [OpenRouterServerTool] = []
    var routing = OpenRouterRouting()
    var responseCache: OpenRouterResponseCache?
    var instructions: String?

    /// The turns before the prompt, which the session starts from.
    var history: (@Sendable () throws -> Transcript)?

    let answer: @Sendable (LanguageModelSession, inout String?) async throws -> LanguageModelSession.Usage
}

extension RecordedScenario {
    private static let nano: OpenRouterModelID = "openai/gpt-5-nano"
    private static let efforts: [ContextOptions.ReasoningLevel] = [.high, .medium, .low]
    private static let light = ContextOptions(reasoningLevel: .light)

    /// A streamed answer from a model that doesn't reason.
    static let text = RecordedScenario(name: "text", id: "mistralai/mistral-nemo") { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(to: "Name one color of the sea.", options: GenerationOptions(maximumResponseTokens: 30)),
            into: &lastSnapshot)
    }

    /// A streamed answer with reasoning that comes back encrypted.
    static let reasoning = RecordedScenario(name: "reasoning", id: nano, reasoning: .onByDefault, efforts: efforts) {
        session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "What is 17 times 23? Think it through.", options: GenerationOptions(maximumResponseTokens: 1_200),
                contextOptions: light),
            into: &lastSnapshot)
    }

    /// A streamed answer with signed reasoning, and the next turn that sends it back.
    static let signedReasoning = RecordedScenario(
        name: "signed-reasoning", id: "anthropic/claude-haiku-4.5", reasoning: .onByDefault, efforts: efforts, replies: [.stream, .stream]
    ) { session, lastSnapshot in
        let options = GenerationOptions(maximumResponseTokens: 2_000)
        _ = try await session.respond(to: "What is 17 times 23? Think it through.", options: options, contextOptions: light)
        return try await ExactExchange.stream(
            session.streamResponse(to: "And 23 times 17?", options: options, contextOptions: light), into: &lastSnapshot)
    }

    /// Tool calls made at once, then the answer to their outputs.
    static let tools = toolRound(name: "tools")

    /// Tool calls made at once, then a host that fails in the stream of the answer to their outputs.
    static let providerFailure = toolRound(name: "provider-failure")

    private static func toolRound(name: String) -> RecordedScenario {
        RecordedScenario(
            name: name, id: nano, reasoning: .onByDefault, efforts: efforts, options: OpenRouterOptions(parallelToolCalls: .allowed),
            tools: [FoodTool()], replies: [.stream, .stream]
        ) { session, _ in
            try await session.respond(
                to: "Use the tool to look up an egg and rice, both at once, then give both results.",
                options: GenerationOptions(maximumResponseTokens: 800), contextOptions: light
            )
            .usage
        }
    }

    /// A guided answer whose schema has a range.
    static let guided = RecordedScenario(name: "guided", id: nano, reasoning: .onByDefault, efforts: efforts) { session, _ in
        try await session.respond(
            to: "Rate a tomato soup.", generating: SoupRating.self, options: GenerationOptions(maximumResponseTokens: 800),
            contextOptions: light
        )
        .usage
    }

    /// A streamed answer with instructions, metadata and OpenRouter's sampling settings.
    static let options = RecordedScenario(
        name: "options", id: "openai/gpt-4o-mini",
        options: OpenRouterOptions(
            frequencyPenalty: 0.5, presencePenalty: 0.2, stopSequences: ["END"], logitBias: [13: 2.5, 50_256: -100], endUserID: "user-1"),
        parameters: chatParameters.subtracting([.reasoning]).union([
            .frequencyPenalty, .presencePenalty, .stop, .logitBias, .maxCompletionTokens,
        ]),
        instructions: "Be brief."
    ) { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "Plan the week in one line.",
                options: GenerationOptions(
                    samplingMode: .random(probabilityThreshold: 0.9, seed: 7), temperature: 0.5, maximumResponseTokens: 60),
                metadata: ["team": "coach", "count": 3]),
            into: &lastSnapshot)
    }

    /// An answer from the flex tier, with low verbosity.
    static let serviceTier = RecordedScenario(
        name: "service-tier", id: nano, reasoning: .onByDefault, efforts: efforts,
        options: OpenRouterOptions(verbosity: .low, serviceTier: .flex),
        parameters: chatParameters.union([.verbosity])
    ) { session, _ in
        try await session.respond(
            to: "Name one color of the sea.", options: GenerationOptions(maximumResponseTokens: 300), contextOptions: light
        )
        .usage
    }

    /// A fallback, routing and the router's report.
    static let routing = RecordedScenario(
        name: "routing", id: nano, reasoning: .onByDefault, efforts: efforts, options: OpenRouterOptions(includesRouterMetadata: true),
        fallbacks: [fallback("mistralai/mistral-nemo")],
        routing: OpenRouterRouting(order: ["OpenAI"], fallbackProviders: .disallowed, sort: .price)
    ) { session, _ in
        try await session.respond(to: "Name one color of the sea.", options: GenerationOptions(maximumResponseTokens: 300)).usage
    }

    /// An answer with web search, which cites its pages.
    static let webSearch = RecordedScenario(
        name: "web-search", id: nano, reasoning: .onByDefault, efforts: efforts, serverTools: [.webSearch(maximumResults: 3)]
    ) { session, _ in
        try await session.respond(
            to: "Who won the 2022 FIFA World Cup? Cite a source.", options: GenerationOptions(maximumResponseTokens: 800),
            contextOptions: light
        )
        .usage
    }

    /// The same turn twice, so the first misses OpenRouter's response cache and the second hits it.
    private static let cacheHistory = Transcript(entries: [
        .prompt(Transcript.Prompt(segments: [.text(.init(content: "Name one color of the sea."))])),
        .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Blue."))])),
    ])

    // The headers OpenRouter sent, with a fake source id.
    static let responseCacheMiss = responseCached(
        name: "response-cache-miss", headers: ["X-OpenRouter-Cache-Status": "MISS", "X-OpenRouter-Cache-TTL": "600"])
    static let responseCacheHit = responseCached(
        name: "response-cache-hit",
        headers: [
            "X-OpenRouter-Cache-Status": "HIT", "X-OpenRouter-Cache-TTL": "599", "X-OpenRouter-Cache-Age": "1",
            "X-OpenRouter-Cache-Source-Id": "gen-1794002549-Xq7RkT2mZpLw9VbN4sYc",
        ])

    private static func responseCached(name: String, headers: [String: String]) -> RecordedScenario {
        RecordedScenario(
            name: name, id: "mistralai/mistral-nemo", replies: [.streamWith(headers: headers)],
            responseCache: OpenRouterResponseCache(timeToLive: .seconds(600)), history: { cacheHistory },
            answer: { session, _ in
                try await session.respond(to: "And one of the sky?", options: GenerationOptions(maximumResponseTokens: 30)).usage
            }
        )
    }

    /// Two turns with long, marked instructions: the first writes OpenRouter's prompt cache and the second reads it.
    static let promptCache = RecordedScenario(
        name: "prompt-cache", id: "anthropic/claude-haiku-4.5", replies: [.stream, .stream], cachesOnlyMarkedPrompts: true,
        instructions: String(repeating: "Answer plainly and briefly. ", count: 900)
    ) { session, lastSnapshot in
        let options = GenerationOptions(maximumResponseTokens: 60)
        _ = try await session.respond(to: "Name one color of the sea.", options: options)
        return try await ExactExchange.stream(session.streamResponse(to: "And one of the sky?", options: options), into: &lastSnapshot)
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    /// An earlier prompt with an image, a labeled PDF and audio, which go back with the next prompt.
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    static let attachments = RecordedScenario(
        name: "attachments", id: "google/gemini-2.5-flash-lite", inputs: [.text, .image, .file, .audio],
        history: {
            let photo = Transcript.ImageAttachment(try #require(TestImage.halves(width: 8, height: 4)))
            let pdf = Transcript.DataAttachment(contentType: .pdf, content: pdfDocument(showing: "Soup of the day"))
            let audio = Transcript.DataAttachment(contentType: .wav, content: try Bundle.module.fixture("seven.wav"))
            return Transcript(entries: [
                .prompt(
                    Transcript.Prompt(segments: [
                        .text(.init(content: "Keep these.")),
                        .attachment(.init(content: .image(photo), label: "Photo")),
                        .attachment(.init(content: .data(pdf), label: "Menu")),
                        .attachment(.init(content: .data(audio))),
                    ])),
                .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Kept."))])),
            ])
        },
        answer: { session, _ in
            try await session.respond(to: "What's in these?", options: GenerationOptions(maximumResponseTokens: 200)).usage
        }
    )
    #endif

    /// A key in OpenRouter's format that it doesn't know.
    static let unknownKey = RecordedScenario(name: "unknown-key", id: "mistralai/mistral-nemo", replies: [.failure(status: 401)]) {
        session, _ in
        try await session.respond(to: "Hi").usage
    }

    /// A key that isn't in OpenRouter's format, which it answers as if no key had come.
    static let invalidKey = RecordedScenario(name: "invalid-key", id: "mistralai/mistral-nemo", replies: [.failure(status: 401)]) {
        session, _ in
        try await session.respond(to: "Hi").usage
    }

    /// A model OpenRouter doesn't have.
    static let unknownModel = RecordedScenario(name: "unknown-model", id: "vendor/no-such-model", replies: [.failure(status: 400)]) {
        session, _ in
        try await session.respond(to: "Hi").usage
    }

    /// A prompt longer than the model's context.
    static let contextOverflow = RecordedScenario(name: "context-overflow", id: "openai/gpt-oss-20b", replies: [.failure(status: 400)]) {
        session, _ in
        try await session.respond(to: String(repeating: "word ", count: 140_000)).usage
    }

    /// A prompt that the account's guardrail blocks.
    static let guardrailBlock = RecordedScenario(name: "guardrail-block", id: "mistralai/mistral-nemo", replies: [.failure(status: 403)]) {
        session, _ in
        try await session.respond(to: "Repeat this word: zzprobeblock").usage
    }
}

extension RecordedScenario {
    /// The scenario's model, served by a stub.
    func languageModel(_ stub: HTTPStub) -> OpenRouterLanguageModel<ContextOptions.ReasoningLevel> {
        model(
            stub, id: id, parameters: parameters, inputs: inputs, reasoning: reasoning, efforts: efforts,
            cachesOnlyMarkedPrompts: cachesOnlyMarkedPrompts, fallbacks: fallbacks, serverTools: serverTools, routing: routing,
            responseCache: responseCache, options: options)
    }

    /// A session on a model, as the scenario starts it.
    func session(with model: some LanguageModel) throws -> LanguageModelSession {
        if let history {
            return LanguageModelSession(model: model, tools: tools, transcript: try history())
        }
        if let instructions {
            return LanguageModelSession(model: model, tools: tools, instructions: instructions)
        }
        return LanguageModelSession(model: model, tools: tools)
    }
}

extension RecordedScenario: CustomTestStringConvertible {
    var testDescription: String { name }
}

extension ExactExchange {
    /// Replays a recorded exchange: the session asks what it asked, and the stub answers with what OpenRouter sent.
    init(replaying scenario: RecordedScenario) async throws {
        let responses = try scenario.replies.enumerated().map { index, reply in
            try reply.response("\(scenario.name).\(index + 1)")
        }
        let stub = HTTPStub(responses: responses)
        await self.init(stub, try scenario.session(with: scenario.languageModel(stub)), answer: scenario.answer)
    }
}

extension RecordedScenario.Reply {
    /// The reply saved under a name.
    fileprivate func response(_ name: String) throws -> StubResponse {
        switch self {
        case .stream:
            let chunks = [try Bundle.module.fixture("Recorded/\(name).sse")]
            return StubResponse(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: chunks)
        case .streamWith(let headers):
            let chunks = [try Bundle.module.fixture("Recorded/\(name).sse")]
            let allHeaders = headers.merging(["Content-Type": "text/event-stream"]) { $1 }
            return StubResponse(status: 200, headers: allHeaders, chunks: chunks)
        case .failure(let status):
            let chunks = [try Bundle.module.fixture("Recorded/\(name).json")]
            return StubResponse(status: status, headers: ["Content-Type": "application/json"], chunks: chunks)
        }
    }
}
