import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport

@testable import OpenAILanguageModels

/// The settings of a typical model that reasons, with tools and structured outputs, which takes sampling settings
/// while its effort is `none`.
let reasoningParameters: Set<OpenAIParameter> = [
    .maxOutputTokens, .parallelToolCalls, .reasoning, .structuredOutputs, .temperature, .toolChoice, .tools, .topP,
]

/// The settings of a typical model that doesn't reason.
let plainParameters: Set<OpenAIParameter> = [
    .maxOutputTokens, .parallelToolCalls, .structuredOutputs, .temperature, .toolChoice, .tools, .topP,
]

/// A model's details, for a test.
func details<Effort: ModelEffort>(
    id: OpenAIModelID = "gpt-test",
    parameters: Set<OpenAIParameter> = reasoningParameters,
    inputs: Set<OpenAIInputModality> = [.text, .image, .pdf],
    reasoning: ModelReasoning = .onByDefault,
    efforts: [Effort] = []
) -> OpenAIModel<Effort> {
    OpenAIModel(
        id: id,
        displayName: "GPT Test",
        releaseDate: .distantPast,
        contextSize: 400_000,
        inputModalities: inputs,
        supportedParameters: parameters,
        reasoning: reasoning,
        reasoningEfforts: efforts
    )
}

/// A model served by a stub, with the standard retries without their waits unless a test sets its own configuration.
func model<Effort: ModelEffort>(
    _ stub: HTTPStub,
    _ details: OpenAIModel<Effort>,
    options: OpenAIOptions = OpenAIOptions(),
    configuration: OpenAIConfiguration = .stubbed,
    auth: (URL) -> OpenAIAuthentication = { url in .apiKey(baseURL: url) { "sk-test" } }
) -> OpenAILanguageModel<Effort> {
    OpenAILanguageModel(
        details: details,
        options: options,
        session: stub.session,
        // The stub stands in for OpenAI, so the authentication goes to the stub's URL.
        auth: auth(stub.baseURL),
        configuration: configuration
    )
}

extension OpenAIConfiguration {
    /// A stub's configuration: no idle timeout, and the standard retries without their waits.
    static let stubbed = OpenAIConfiguration(idleTimeout: nil, retries: RequestRetries(initialDelay: .zero))
}

/// A model that reasons, with the efforts of GPT-6 Luna, served by a stub.
func reasoningModel(_ stub: HTTPStub, options: OpenAIOptions = OpenAIOptions()) -> OpenAILanguageModel<ContextOptions.ReasoningLevel> {
    model(stub, details(efforts: [.max, .xhigh, .high, .medium, .low, .off]), options: options)
}

/// A model that doesn't reason, served by a stub.
func plainModel(_ stub: HTTPStub, options: OpenAIOptions = OpenAIOptions()) -> OpenAILanguageModel<Efforts.Unsupported> {
    model(stub, details(id: "gpt-plain", parameters: plainParameters, reasoning: .unsupported), options: options)
}

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

/// The event that a response was created, with its id and model.
func created(model: String = "gpt-test-2026-10-01") -> JSONValue {
    lifecycle("response.created", ["id": "resp_1", "model": .string(model), "service_tier": "default"])
}

/// The event that a response completed, with its usage.
func completed(model: String = "gpt-test-2026-10-01", input: Int = 12, cached: Int = 0, output: Int = 5, reasoning: Int = 0) -> JSONValue {
    lifecycle(
        "response.completed",
        [
            "id": "resp_1", "model": .string(model), "service_tier": "default",
            "usage": [
                "input_tokens": .integer(input), "input_tokens_details": ["cached_tokens": .integer(cached)],
                "output_tokens": .integer(output), "output_tokens_details": ["reasoning_tokens": .integer(reasoning)],
            ],
        ])
}

/// A text delta of the message at an output index.
func textDelta(_ delta: String, at index: Int = 0) -> JSONValue {
    ["type": "response.output_text.delta", "output_index": .integer(index), "content_index": 0, "delta": .string(delta)]
}

/// The event that adds or ends an output item.
func item(_ type: String, at index: Int, _ item: JSONValue) -> JSONValue {
    ["type": .string(type), "output_index": .integer(index), "item": item]
}

/// The events of a reasoning item with a summary and its reasoning encrypted.
func reasoningItem(at index: Int, id: String, summary: String, encrypted: String) -> [JSONValue] {
    [
        item("response.output_item.added", at: index, ["type": "reasoning", "id": .string(id), "summary": []]),
        [
            "type": "response.reasoning_summary_text.delta", "output_index": .integer(index), "summary_index": 0,
            "delta": .string(summary),
        ],
        item(
            "response.output_item.done", at: index,
            [
                "type": "reasoning", "id": .string(id), "summary": [["type": "summary_text", "text": .string(summary)]],
                "encrypted_content": .string(encrypted),
            ]),
    ]
}

/// The events of a function call whose arguments stream in one delta.
func functionCall(at index: Int, callID: String, name: String, arguments: String) -> [JSONValue] {
    [
        item(
            "response.output_item.added", at: index,
            ["type": "function_call", "id": .string("fc_\(index)"), "call_id": .string(callID), "name": .string(name), "arguments": ""]),
        ["type": "response.function_call_arguments.delta", "output_index": .integer(index), "delta": .string(arguments)],
        item(
            "response.output_item.done", at: index,
            [
                "type": "function_call", "id": .string("fc_\(index)"), "call_id": .string(callID), "name": .string(name),
                "arguments": .string(arguments),
            ]),
    ]
}

/// A streamed response made of groups of events, such as a reasoning item's.
func responseStream(headers: [String: String] = [:], _ groups: [JSONValue]...) -> StubResponse {
    let lines = groups.flatMap(\.self).map { "event: \($0["type"]?.stringValue ?? "")\ndata: \($0.text)\n\n" }
    let stream = StubResponse.eventStream(Data(lines.joined().utf8))
    return StubResponse(status: stream.status, headers: stream.headers.merging(headers) { $1 }, chunks: stream.chunks)
}

/// The JSON body of a request a stub received.
func body(_ stub: HTTPStub, _ index: Int = 0) throws -> JSONValue {
    try JSONValue(json: stub.requests[index].body)
}

/// The input items of a request body.
func input(_ body: JSONValue) -> [JSONValue] {
    if case .array(let items)? = body["input"] { items } else { [] }
}

/// A text segment.
func text(_ content: String) -> Transcript.Segment {
    .text(.init(content: content))
}

extension ExactExchange {
    /// Runs a session against a stub and reads what it sent and got back, with OpenAI's own headers.
    init(
        _ stub: HTTPStub,
        _ session: LanguageModelSession,
        answer: (LanguageModelSession, inout String?) async throws -> LanguageModelSession.Usage
    ) async {
        await self.init(stub, session, recordingHeaders: /^OpenAI-/, answer: answer)
    }
}

/// A tool that looks up a food's calories.
struct FoodTool: Tool {
    let name = "lookUpFood"
    let description = "Looks up a food's calories."

    @Generable
    struct Arguments {
        var food: String
    }

    func call(arguments: Arguments) async throws -> String {
        "\(arguments.food): 100 kcal"
    }
}
