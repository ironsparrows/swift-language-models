import Foundation
import FoundationModels
import LanguageModelsTestSupport

@testable import LanguageModels

/// An exchange that adds only what a test gives it, so the format's own behavior shows.
///
/// Its errors are the format's failures themselves, so a test can read what failed.
struct ResponsesTestExchange: Responses.Exchange {
    /// What the exchange adds to a request's members and choices.
    var prepares: @Sendable (inout Responses.Request) throws -> Void = { _ in }

    func prepare(_ request: inout Responses.Request) throws {
        try prepares(&request)
    }

    func error(for failure: RequestFailure<APIErrorBody>) -> any Error {
        failure
    }
}

extension Responses.Model<ResponsesTestExchange> {
    /// A model of a provider named `Test`, sending to a URL with no retries.
    static func test(url: URL = URL(fileURLWithPath: "/"), session: URLSession = .shared) -> Self {
        Self(
            name: "vendor/model", url: url,
            connection: Connection(
                session: session, authentication: Connection.Authentication(baseURL: nil) { [:] }, idleTimeout: nil, retries: .disabled,
                retrying: { _ in false }),
            providerName: "Test", capabilities: LanguageModelCapabilities([.guidedGeneration, .toolCalling, .reasoning]), reaching: [],
            exchange: ResponsesTestExchange())
    }
}

/// What a model sends for a request, after its exchange prepared it.
struct SentRequest {
    let body: JSONValue
    let portableSchemaBody: JSONValue?
    let adjustments: [RequestAdjustment]
    let imageEntries: [Transcript.Entry]

    init(_ generation: LanguageModelExecutorGenerationRequest, model: Responses.Model<ResponsesTestExchange> = .test()) throws {
        let exchange = model.exchange
        var request = try Responses.Request(generation, model: model, exchange: exchange)
        try exchange.prepare(&request)
        let sent = try request.body()
        body = sent.json
        portableSchemaBody = sent.portableJSON
        adjustments = sent.adjustments
        imageEntries = request.imageEntries
    }
}

/// The input items of a request body.
func input(_ body: JSONValue) -> [JSONValue] {
    if case .array(let items)? = body["input"] { items } else { [] }
}

/// A streamed response made of the given events, each with its `type` as the event's name.
func events(_ events: JSONValue...) -> StubResponse {
    let lines = events.map { "event: \($0["type"]?.stringValue ?? "")\ndata: \($0.text)\n\n" }
    return .eventStream(Data(lines.joined().utf8))
}

/// A lifecycle event, such as `response.completed`, with the response's members.
func lifecycle(_ type: String, _ response: JSONValue = [:]) -> JSONValue {
    ["type": .string(type), "response": response]
}

/// A text delta of the message at an output index.
func textDelta(_ delta: String, at index: Int = 0) -> JSONValue {
    ["type": "response.output_text.delta", "output_index": .integer(index), "content_index": 0, "delta": .string(delta)]
}

/// The event that adds or ends an output item.
func item(_ type: String, at index: Int, _ item: JSONValue) -> JSONValue {
    ["type": .string(type), "output_index": .integer(index), "item": item]
}
