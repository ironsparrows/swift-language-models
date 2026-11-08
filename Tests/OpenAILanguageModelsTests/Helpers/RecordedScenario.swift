import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenAILanguageModels

/// An exchange recorded from OpenAI: what a session asked, which its replay asks again, and what came back.
struct RecordedScenario: Sendable {
    /// What OpenAI sent back for one request.
    enum Reply: Sendable {
        case stream
        case failure(status: Int, contentType: String = "application/json")
    }

    let name: String
    let details: OpenAIModel<ContextOptions.ReasoningLevel>
    var serverTools: [OpenAIServerTool] = []
    var options = OpenAIOptions()
    var tools: [any Tool] = []
    var replies: [Reply] = [.stream]
    var instructions: String?

    /// The turns before the prompt, which the session starts from.
    var history: (@Sendable () throws -> Transcript)?

    let answer: @Sendable (LanguageModelSession, inout String?) async throws -> LanguageModelSession.Usage
}

extension RecordedScenario {
    private static let nano: OpenAIModel<ContextOptions.ReasoningLevel> = OpenAILanguageModelsTests.details(
        id: "gpt-5-nano", efforts: [.high, .medium, .low, .minimal])
    private static let mini: OpenAIModel<ContextOptions.ReasoningLevel> = OpenAILanguageModelsTests.details(
        id: "gpt-4o-mini", parameters: plainParameters, reasoning: .unsupported, efforts: [])
    private static let quick = ContextOptions(reasoningLevel: .minimal)
    private static let luna: OpenAIModel<ContextOptions.ReasoningLevel> = OpenAILanguageModelsTests.details(
        id: "gpt-6-luna", parameters: [.maxOutputTokens, .parallelToolCalls, .reasoning, .structuredOutputs, .toolChoice, .tools],
        efforts: [.max, .xhigh, .high, .medium, .low, .off])
    /// The least reasoning a web search takes.
    private static let light = ContextOptions(reasoningLevel: .light)

    /// A streamed answer with the least reasoning.
    static let text = RecordedScenario(name: "text", details: nano) { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "Name one color of the sea.", options: GenerationOptions(maximumResponseTokens: 300), contextOptions: quick),
            into: &lastSnapshot)
    }

    /// A streamed answer with a reasoning summary.
    static let reasoning = RecordedScenario(name: "reasoning", details: nano, options: OpenAIOptions(reasoningSummary: .auto)) {
        session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "What is 17 times 23? Think it through.", options: GenerationOptions(maximumResponseTokens: 1_200),
                contextOptions: ContextOptions(reasoningLevel: .light)),
            into: &lastSnapshot)
    }

    /// Tool calls made at once, then the answer to their outputs.
    static let tools = RecordedScenario(
        name: "tools", details: nano, options: OpenAIOptions(parallelToolCalls: .allowed), tools: [FoodTool()], replies: [.stream, .stream]
    ) { session, _ in
        try await session.respond(
            to: "Use the tool to look up an egg and rice, both at once, then give both results.",
            options: GenerationOptions(maximumResponseTokens: 800), contextOptions: quick
        )
        .usage
    }

    /// A guided answer.
    static let guided = RecordedScenario(name: "guided", details: nano) { session, _ in
        try await session.respond(
            to: "Name a food.", generating: FoodTool.Arguments.self, options: GenerationOptions(maximumResponseTokens: 300),
            contextOptions: quick
        )
        .usage
    }

    /// A streamed answer from a model that doesn't reason.
    static let plain = RecordedScenario(name: "plain", details: mini) { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(to: "Name one color of the sea.", options: GenerationOptions(maximumResponseTokens: 30)),
            into: &lastSnapshot)
    }

    /// A streamed answer with instructions, metadata and OpenAI's options.
    static let options = RecordedScenario(
        name: "options", details: nano,
        options: OpenAIOptions(
            serviceTier: .flex, verbosity: .low, reasoningSummary: .auto, cacheKey: .session, endUserID: "user-1", storage: .notStored),
        instructions: "Be brief."
    ) { session, lastSnapshot in
        try await ExactExchange.stream(
            session.streamResponse(
                to: "Plan the week in one line.", options: GenerationOptions(maximumResponseTokens: 600),
                contextOptions: ContextOptions(reasoningLevel: .light), metadata: ["team": "coach"]),
            into: &lastSnapshot)
    }

    /// Two turns with long instructions, the second of which reads them from OpenAI's cache.
    static let cached = RecordedScenario(
        name: "cached", details: nano, options: OpenAIOptions(cacheKey: .session), replies: [.stream, .stream],
        instructions: String(repeating: "Answer plainly and briefly. ", count: 300)
    ) { session, lastSnapshot in
        let options = GenerationOptions(maximumResponseTokens: 300)
        _ = try await session.respond(to: "Name one color of the sea.", options: options, contextOptions: quick)
        return try await ExactExchange.stream(
            session.streamResponse(to: "And one of the sky?", options: options, contextOptions: quick), into: &lastSnapshot)
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    /// An earlier prompt with an image and a labeled PDF, which go back with the next prompt.
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    static let attachments = RecordedScenario(
        name: "attachments", details: nano,
        history: {
            let photo = Transcript.ImageAttachment(try #require(TestImage.halves(width: 8, height: 4)))
            let pdf = Transcript.DataAttachment(contentType: .pdf, content: pdfDocument(showing: "Soup of the day"))
            return Transcript(entries: [
                .prompt(
                    Transcript.Prompt(segments: [
                        .text(.init(content: "Keep these.")),
                        .attachment(.init(content: .image(photo), label: "Photo")),
                        .attachment(.init(content: .data(pdf), label: "Menu")),
                    ])),
                .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Kept."))])),
            ])
        },
        answer: { session, _ in
            try await session.respond(
                to: "What's in these?", options: GenerationOptions(maximumResponseTokens: 500), contextOptions: quick
            )
            .usage
        }
    )
    #endif

    /// Two turns of web searches that list their sources, at the model's own effort with a reasoning summary, so
    /// reasoning comes between the calls, the second turn sending the first's calls back with it.
    static let webSearch = RecordedScenario(
        name: "web-search", details: luna, serverTools: [.webSearch(listsSources: true)],
        options: OpenAIOptions(reasoningSummary: .auto, maximumServerToolCalls: 2), replies: [.stream, .stream]
    ) { session, _ in
        let options = GenerationOptions(maximumResponseTokens: 4_000)
        _ = try await session.respond(to: "Search the web: what is the latest stable release of Swift? One sentence.", options: options)
        return try await session.respond(to: "When was it released? One sentence.", options: options).usage
    }

    /// Two turns of web searches OpenAI doesn't keep, at the model's own effort, the second sending the first's call back
    /// whole and ending with reasoning before its call.
    static let webSearchNotStored = RecordedScenario(
        name: "web-search-not-stored", details: luna, serverTools: [.webSearch()],
        options: OpenAIOptions(reasoningSummary: .auto, maximumServerToolCalls: 2, storage: .notStored), replies: [.stream, .stream]
    ) { session, _ in
        let options = GenerationOptions(maximumResponseTokens: 4_000)
        _ = try await session.respond(to: "Search the web: what is the tallest building in Lisbon? One sentence.", options: options)
        return try await session.respond(to: "How tall is it? One sentence.", options: options).usage
    }

    /// Two turns of web searches by a model that doesn't reason, whose calls go back before its messages.
    static let webSearchPlain = RecordedScenario(
        name: "web-search-plain", details: mini, serverTools: [.webSearch()], options: OpenAIOptions(maximumServerToolCalls: 1),
        replies: [.stream, .stream]
    ) { session, _ in
        let options = GenerationOptions(maximumResponseTokens: 300)
        _ = try await session.respond(to: "Search the web: who designed the Eiffel Tower? One sentence.", options: options)
        return try await session.respond(to: "In which year was it finished? One sentence.", options: options).usage
    }

    /// A web search and a call of the session's tool in one answer, a second round of calls, then the answer.
    static let webSearchWithSessionTool = RecordedScenario(
        name: "web-search-with-session-tool", details: luna, serverTools: [.webSearch()],
        options: OpenAIOptions(maximumServerToolCalls: 1), tools: [FoodTool()], replies: [.stream, .stream, .stream]
    ) { session, _ in
        try await session.respond(
            to: "Search the web for the calories in a boiled egg, and look up rice with the tool. Give both in one sentence.",
            options: GenerationOptions(maximumResponseTokens: 3_000), contextOptions: light
        )
        .usage
    }

    /// Two turns with an image at the model's own effort, the second asking for a change, which sends the first image's
    /// call back by its id. An image tool's complexity follows a `low` effort, which the image models refuse.
    static let imageGeneration = RecordedScenario(
        name: "image-generation", details: luna, serverTools: [.imageGeneration(quality: .low, size: .square1024)],
        replies: [.stream, .stream]
    ) { session, _ in
        let options = GenerationOptions(maximumResponseTokens: 2_000)
        _ = try await session.respond(to: "Draw a small red circle on a white background.", options: options)
        return try await session.respond(to: "Now make the circle blue.", options: options).usage
    }

    /// Two turns of file searches in a vector store the recording made, with the files the answers cite.
    static let fileSearch = fileSearch(in: "vs_recordedvectorstore0000000000")

    /// Two turns of file searches in a vector store.
    static func fileSearch(in vectorStoreID: String) -> RecordedScenario {
        RecordedScenario(
            name: "file-search", details: luna, serverTools: [.fileSearch(vectorStoreIDs: [vectorStoreID], maximumResults: 3)],
            replies: [.stream, .stream]
        ) { session, _ in
            let options = GenerationOptions(maximumResponseTokens: 2_000)
            _ = try await session.respond(
                to: "Search the files: what does Harbor Kitchen serve on Tuesday? One sentence.", options: options, contextOptions: light)
            return try await session.respond(to: "And when does the kitchen close? One sentence.", options: options, contextOptions: light)
                .usage
        }
    }

    /// A key OpenAI doesn't know.
    static let invalidKey = RecordedScenario(
        name: "invalid-key", details: mini, replies: [.failure(status: 401, contentType: "text/plain")]
    ) {
        session, _ in
        try await session.respond(to: "Hi").usage
    }

    /// A model OpenAI doesn't have.
    static let unknownModel = RecordedScenario(
        name: "unknown-model",
        details: OpenAILanguageModelsTests.details(
            id: "gpt-no-such-model", parameters: plainParameters, reasoning: .unsupported, efforts: []),
        replies: [.failure(status: 404)]
    ) { session, _ in
        try await session.respond(to: "Hi").usage
    }

    /// A prompt longer than the model's context, which OpenAI refuses in the stream, after a status of 200.
    static let contextOverflow = RecordedScenario(name: "context-overflow", details: mini) { session, _ in
        try await session.respond(to: String(repeating: "word ", count: 140_000)).usage
    }
}

extension RecordedScenario {
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
    /// Replays a recorded exchange: the session asks what it asked, and the stub answers with what OpenAI sent.
    init(replaying scenario: RecordedScenario) async throws {
        let responses = try scenario.replies.enumerated().map { index, reply in
            try reply.response("\(scenario.name).\(index + 1)")
        }
        let stub = HTTPStub(responses: responses)
        let languageModel = model(stub, scenario.details, serverTools: scenario.serverTools, options: scenario.options)
        await self.init(stub, try scenario.session(with: languageModel), answer: scenario.answer)
    }
}

extension RecordedScenario.Reply {
    /// The reply saved under a name, with a fixed request id in place of the real one.
    fileprivate func response(_ name: String) throws -> StubResponse {
        switch self {
        case .stream:
            let chunks = [try Bundle.module.fixture("Recorded/\(name).sse")]
            return StubResponse(status: 200, headers: ["Content-Type": "text/event-stream", "x-request-id": "req_1"], chunks: chunks)
        case .failure(let status, let contentType):
            let chunks = [try Bundle.module.fixture("Recorded/\(name).json")]
            return StubResponse(status: status, headers: ["Content-Type": contentType, "x-request-id": "req_1"], chunks: chunks)
        }
    }
}
