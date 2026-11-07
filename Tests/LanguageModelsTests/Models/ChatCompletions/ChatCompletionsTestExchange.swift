import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

/// An exchange that adds only what a test gives it, so the format's own behavior shows.
///
/// Its errors are the format's failures themselves, so a test can read what failed.
struct ChatCompletionsTestExchange: ChatCompletions.Exchange {
    /// What the exchange adds to a request's members and choices.
    var prepares: @Sendable (inout ChatCompletions.Request) throws -> Void = { _ in }

    /// The key under which an assistant message carries the text of the reasoning it sends back, or `nil` to send none.
    var reasoningMember: String?

    /// The host the chunks named.
    private var host: String?

    func prepare(_ request: inout ChatCompletions.Request) throws {
        request.headers = ["X-Test": "yes"]
        try prepares(&request)
    }

    func replayMembers(for reasoning: [(entry: Transcript.Reasoning, text: String)]) -> JSONObject {
        guard let reasoningMember else { return JSONObject() }
        return [reasoningMember: .string(reasoning.map(\.text).joined())]
    }

    mutating func read(_ extras: TestExtras) -> ChatCompletions.ChunkAdditions {
        host = extras.host ?? host
        return ChatCompletions.ChunkAdditions(reasoning: extras.choices?.first?.delta?.reasoning)
    }

    func additions(header: (String) -> String?) -> AnswerAdditions {
        var metadata: [String: any ConvertibleToGeneratedContent] = [:]
        metadata[LanguageModelMetadataKey.provider] = host
        return AnswerAdditions(host: host, metadata: metadata)
    }

    func error(for failure: RequestFailure<APIErrorBody>) -> any Error {
        failure
    }
}

/// The members of a chunk only the test exchange reads: the host, and plain reasoning text in the delta.
struct TestExtras: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let reasoning: String?
        }

        let delta: Delta?
    }

    let host: String?
    let choices: [Choice]?
}

extension ChatCompletions.Model<ChatCompletionsTestExchange> {
    /// A model of a provider named `Test`, sending to a URL with no retries.
    static func test(url: URL = URL(fileURLWithPath: "/"), session: URLSession = .shared) -> Self {
        var model = Self(
            name: "vendor/model", url: url,
            connection: Connection(
                session: session, authentication: Connection.Authentication(baseURL: nil) { [:] }, idleTimeout: nil, retries: .disabled,
                retrying: { _ in false }),
            providerName: "Test", capabilities: LanguageModelCapabilities([.guidedGeneration, .toolCalling, .reasoning]), reaching: [],
            exchange: ChatCompletionsTestExchange())
        // The fallbacks a test adds go after the model, as a provider may order its members.
        model.memberOrder = [.model, "models", .messages]
        return model
    }
}

/// What a model sends for a request, after its exchange prepared it.
struct ChatCompletionsSentRequest {
    let body: JSONValue
    let portableSchemaBody: JSONValue?
    let adjustments: [RequestAdjustment]

    init(
        _ generation: LanguageModelExecutorGenerationRequest,
        model: ChatCompletions.Model<ChatCompletionsTestExchange> = .test()
    ) throws {
        let exchange = model.exchange
        var request = try ChatCompletions.Request(generation, model: model, exchange: exchange)
        try exchange.prepare(&request)
        let sent = try request.body()
        body = sent.json
        portableSchemaBody = sent.portableJSON
        adjustments = sent.adjustments
    }
}

/// The messages of a request body.
func messages(_ body: JSONValue) -> [JSONValue] {
    if case .array(let messages)? = body["messages"] { messages } else { [] }
}

/// A streamed answer made of the given chunks, then `[DONE]`.
func chatCompletionsEvents(_ chunks: JSONValue...) -> StubResponse {
    let lines = chunks.map { "data: \($0.text)\n\n" } + ["data: [DONE]\n\n"]
    return .eventStream(Data(lines.joined().utf8))
}

extension ChatCompletionsModelTests {
    /// A chunk of answer text, which ends the answer when it has a finish reason.
    static func textChunk(_ text: String, finishReason: String? = nil) -> JSONValue {
        ["choices": [["delta": ["content": .string(text)], "finish_reason": finishReason.map(JSONValue.string)]]]
    }

    /// A chunk with one tool-call fragment. A fragment without an index leaves the field out.
    static func toolCallChunk(_ index: Int? = 0, id: String? = nil, name: String? = nil, arguments: String? = nil) -> JSONValue {
        let function: JSONValue = ["name": name.map(JSONValue.string), "arguments": arguments.map(JSONValue.string)]
        let fragment: JSONValue = ["index": index.map(JSONValue.integer), "id": id.map(JSONValue.string), "function": function]
        return ["choices": [["delta": ["tool_calls": [fragment]]]]]
    }

    /// The chunk that ends an answer, with its usage when there is one.
    static func finishChunk(_ reason: String = "stop", usage: JSONValue? = nil) -> JSONValue {
        ["choices": [["delta": [:], "finish_reason": .string(reason)]], "usage": usage]
    }

    /// A chunk of the plain reasoning text the test exchange reads.
    static func reasoningChunk(_ reasoning: String) -> JSONValue {
        ["choices": [["delta": ["reasoning": .string(reasoning)]]]]
    }

    /// The start of an answer: the given chunks, with the connection left open after them.
    static func openAnswer(_ chunks: JSONValue...) -> StubResponse {
        StubResponse.eventStream(Data(chunks.map { "data: \($0.text)\n\n" }.joined().utf8)).keepingConnectionOpen()
    }

    /// The assistant messages of the stub's request at an index.
    static func assistantMessages(_ stub: HTTPStub, request index: Int) throws -> [JSONValue] {
        let sent = try #require(stub.requests.dropFirst(index).first)
        return messages(try JSONValue(json: sent.body)).filter { $0["role"] == "assistant" }
    }

    /// The text of each reasoning entry.
    static func reasoningTexts(_ entries: some Sequence<Transcript.Entry>) -> [String] {
        reasoningEntries(in: entries).map { $0.segments.compactMap(\.text).joined() }
    }

    /// The text of an entry that is a prompt, or `nil` for any other.
    static func promptText(_ entry: Transcript.Entry?) -> String? {
        guard case .prompt(let prompt)? = entry else { return nil }
        return prompt.segments.compactMap(\.text).joined()
    }

    /// The body of the stub's request at an index.
    static func sentBody(_ stub: HTTPStub, _ index: Int = 0) throws -> JSONValue {
        try JSONValue(json: try #require(stub.requests.dropFirst(index).first).body)
    }

    /// A model of the plain format, sending to a stub.
    static func plainModel(_ stub: HTTPStub) -> ChatCompletions.Model<ChatCompletions.PlainExchange> {
        var model = ChatCompletions.Model(name: "vendor/model", url: stub.baseURL)
        model.connection = Connection(
            session: stub.session, authentication: .unauthenticated, idleTimeout: nil, retries: .disabled, retrying: { _ in false })
        return model
    }

    /// A model of a provider named `Test`, sending to a stub.
    static func model(_ stub: HTTPStub) -> ChatCompletions.Model<ChatCompletionsTestExchange> {
        .test(url: stub.baseURL, session: stub.session)
    }

    /// A session's exchange with a stub, for one prompt.
    static func answer(_ stub: HTTPStub) async -> ExactExchange {
        await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
            try await session.respond(to: "Hello").usage
        }
    }

    /// The error a session's one prompt ends in, or `nil` when it's answered.
    static func error(of stub: HTTPStub) async -> (any Error)? {
        do {
            _ = try await LanguageModelSession(model: model(stub)).respond(to: "Hello")
            return nil
        } catch {
            return error
        }
    }

    /// Runs one exchange of the test model with a stub, reading the channel's events without looking at them, since a
    /// channel waits for its reader.
    ///
    /// - Returns: The answer, or the failure it ended in.
    static func respond(
        _ stub: HTTPStub,
        to entries: [Transcript.Entry],
        schema: GenerationSchema? = nil
    ) async -> (DetailedLanguageModelAnswer?, RequestFailure<APIErrorBody>?) {
        let model = ChatCompletions.Model<ChatCompletionsTestExchange>.test(url: stub.baseURL, session: stub.session)
        let channel = LanguageModelExecutorGenerationChannel()
        let reader = Task { for try await _ in channel {} }
        defer { reader.cancel() }
        do {
            let text = try await model.run(generationRequest(entries, schema: schema), streamingInto: channel)
            return (DetailedLanguageModelAnswer(responseText: text), nil)
        } catch let failure as RequestFailure<APIErrorBody> {
            return (nil, failure)
        } catch {
            Issue.record("The model threw \(error)")
            return (nil, nil)
        }
    }
}
