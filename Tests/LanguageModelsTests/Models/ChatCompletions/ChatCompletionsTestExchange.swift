import Foundation
import FoundationModels
import LanguageModelsTestSupport

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
