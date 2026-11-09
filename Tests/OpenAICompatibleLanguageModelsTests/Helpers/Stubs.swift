import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport

@testable import OpenAICompatibleLanguageModels

/// A provider described by its name and URL, served by a stub.
func provider(
    _ stub: HTTPStub,
    name: String = "Gateway",
    format: OpenAICompatibleProvider.Format = .chatCompletions,
    keyHeader: OpenAICompatibleProvider.KeyHeader = .bearer,
    headers: [String: String] = [:]
) -> OpenAICompatibleProvider {
    OpenAICompatibleProvider(name: name, url: stub.baseURL, format: format, keyHeader: keyHeader, headers: headers)
}

/// A model that reasons when asked, with a context of 128,000 tokens, on a provider served by a stub.
func model(
    _ stub: HTTPStub,
    on given: OpenAICompatibleProvider? = nil,
    format: OpenAICompatibleProvider.Format = .chatCompletions,
    options: OpenAICompatibleOptions = OpenAICompatibleOptions(),
    configuration: OpenAICompatibleConfiguration? = .stubbed,
    auth: OpenAICompatibleAuthentication = .apiKey { "sk-test" }
) -> OpenAICompatibleLanguageModel {
    let details = OpenAICompatibleModel("test-model", on: given ?? provider(stub, format: format), contextSize: 128_000)
    return OpenAICompatibleLanguageModel(details, options: options, session: stub.session, configuration: configuration, auth: auth)
}

extension OpenAICompatibleConfiguration {
    /// A stub's configuration: no idle timeout, and the standard retries without their waits.
    static let stubbed = OpenAICompatibleConfiguration(idleTimeout: nil, retries: RequestRetries(initialDelay: .zero))
}

// MARK: - Chat Completions

/// A streamed chat completion made of the given chunks, then `[DONE]`.
func chunks(headers: [String: String] = [:], _ chunks: JSONValue...) -> StubResponse {
    let lines = chunks.map { "data: \($0.text)\n\n" }.joined() + "data: [DONE]\n\n"
    let stream = StubResponse.eventStream(Data(lines.utf8))
    return StubResponse(status: stream.status, headers: stream.headers.merging(headers) { $1 }, chunks: stream.chunks)
}

/// A chunk whose delta has the given members.
func delta(_ delta: JSONValue, finishReason: String? = nil) -> JSONValue {
    let reason: JSONValue = finishReason.map(JSONValue.string) ?? .null
    return ["id": "chatcmpl-1", "model": "test-model-2026-10-01", "choices": [["index": 0, "delta": delta, "finish_reason": reason]]]
}

/// A chunk of answer text.
func text(_ content: String) -> JSONValue {
    delta(["content": .string(content)])
}

/// The chunk that ends an answer.
func finish(_ reason: String = "stop") -> JSONValue {
    delta([:], finishReason: reason)
}

/// The chunk with an answer's usage and no choices, as a provider sends it when asked.
func usage(input: Int = 12, output: Int = 5) -> JSONValue {
    ["id": "chatcmpl-1", "choices": [], "usage": ["prompt_tokens": .integer(input), "completion_tokens": .integer(output)]]
}

// MARK: - Responses

/// A streamed response made of the given events, each with its `type` as the event's name.
func events(headers: [String: String] = [:], _ events: JSONValue...) -> StubResponse {
    let lines = events.map { "event: \($0["type"]?.stringValue ?? "")\ndata: \($0.text)\n\n" }
    let stream = StubResponse.eventStream(Data(lines.joined().utf8))
    return StubResponse(status: stream.status, headers: stream.headers.merging(headers) { $1 }, chunks: stream.chunks)
}

/// A lifecycle event, such as `response.completed`, with the response's members.
func lifecycle(_ type: String, _ response: JSONValue = [:]) -> JSONValue {
    ["type": .string(type), "response": response]
}

/// The event that a response completed, with its id, model and usage.
func completed(input: Int = 12, output: Int = 5) -> JSONValue {
    lifecycle(
        "response.completed",
        ["id": "resp_1", "model": "test-model-2026-10-01", "usage": ["input_tokens": .integer(input), "output_tokens": .integer(output)]])
}

/// A text delta of the message at an output index.
func textDelta(_ delta: String, at index: Int = 0) -> JSONValue {
    ["type": "response.output_text.delta", "output_index": .integer(index), "content_index": 0, "delta": .string(delta)]
}

/// The event that adds or ends an output item.
func item(_ type: String, at index: Int, _ item: JSONValue) -> JSONValue {
    ["type": .string(type), "output_index": .integer(index), "item": item]
}

/// The events of a reasoning item with a summary.
func reasoningItem(at index: Int, id: String, summary: String) -> [JSONValue] {
    [
        item("response.output_item.added", at: index, ["type": "reasoning", "id": .string(id), "summary": []]),
        [
            "type": "response.reasoning_summary_text.delta", "output_index": .integer(index), "summary_index": 0,
            "delta": .string(summary),
        ],
        item(
            "response.output_item.done", at: index,
            ["type": "reasoning", "id": .string(id), "summary": [["type": "summary_text", "text": .string(summary)]]]),
    ]
}

/// A streamed response made of groups of events, such as a reasoning item's.
func responseStream(headers: [String: String] = [:], _ groups: [JSONValue]...) -> StubResponse {
    let lines = groups.flatMap(\.self).map { "event: \($0["type"]?.stringValue ?? "")\ndata: \($0.text)\n\n" }
    let stream = StubResponse.eventStream(Data(lines.joined().utf8))
    return StubResponse(status: stream.status, headers: stream.headers.merging(headers) { $1 }, chunks: stream.chunks)
}

// MARK: - Requests

/// The JSON body of a request a stub received.
func body(_ stub: HTTPStub, _ index: Int = 0) throws -> JSONValue {
    try JSONValue(json: stub.requests[index].body)
}
