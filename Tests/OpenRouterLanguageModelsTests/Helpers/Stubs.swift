import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport

@testable import OpenRouterLanguageModels

/// The parameters of a typical chat model with tools, structured outputs and reasoning.
let chatParameters: Set<OpenRouterParameter> = [
    .maxTokens, .reasoning, .responseFormat, .seed, .structuredOutputs, .temperature, .toolChoice, .tools, .topK, .topP,
]

/// A model served by a stub, with the shared retry policy without its waits.
func model<Effort: ModelEffort>(
    _ stub: HTTPStub,
    id: OpenRouterModelID = "vendor/model",
    parameters: Set<OpenRouterParameter> = chatParameters,
    inputs: Set<OpenRouterInputModality> = [.text],
    outputs: Set<OpenRouterOutputModality> = [.text],
    reasoning: ModelReasoning = .offByDefault,
    efforts: [Effort] = [],
    cachesOnlyMarkedPrompts: Bool = false,
    fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>] = [],
    serverTools: [OpenRouterServerTool] = [],
    routing: OpenRouterRouting = OpenRouterRouting(),
    cacheControl: OpenRouterCacheControl? = .automatic,
    responseCache: OpenRouterResponseCache? = nil,
    options: OpenRouterOptions = OpenRouterOptions(),
    retryLimit: Int = RequestRetries.standard.limit,
    configuration: OpenRouterConfiguration? = nil
) -> OpenRouterLanguageModel<Effort> {
    OpenRouterLanguageModel(
        details: OpenRouterModel(
            id: id,
            displayName: "Vendor: Model",
            releaseDate: .distantPast,
            contextSize: 200_000,
            inputModalities: inputs,
            outputModalities: outputs,
            supportedParameters: parameters,
            reasoning: reasoning,
            reasoningEfforts: efforts,
            cachesOnlyMarkedPrompts: cachesOnlyMarkedPrompts
        ),
        fallbacks: fallbacks,
        serverTools: serverTools,
        routing: routing,
        options: options,
        cacheControl: cacheControl,
        responseCache: responseCache,
        app: OpenRouterApp(name: "Coach"),
        session: stub.session,
        // The stub stands in for OpenRouter, so the authentication goes to the stub's URL.
        auth: .apiKey(baseURL: stub.baseURL) { "sk-or-test" },
        configuration: configuration ?? OpenRouterConfiguration(retries: .immediate(limit: retryLimit))
    )
}

/// A model without reasoning efforts to choose from.
func model(
    _ stub: HTTPStub,
    id: OpenRouterModelID = "vendor/model",
    parameters: Set<OpenRouterParameter> = chatParameters,
    inputs: Set<OpenRouterInputModality> = [.text],
    outputs: Set<OpenRouterOutputModality> = [.text],
    cachesOnlyMarkedPrompts: Bool = false,
    fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>] = [],
    serverTools: [OpenRouterServerTool] = [],
    routing: OpenRouterRouting = OpenRouterRouting(),
    cacheControl: OpenRouterCacheControl? = .automatic,
    responseCache: OpenRouterResponseCache? = nil,
    options: OpenRouterOptions = OpenRouterOptions(),
    retryLimit: Int = RequestRetries.standard.limit
) -> OpenRouterLanguageModel<Efforts.Unsupported> {
    model(
        stub, id: id, parameters: parameters, inputs: inputs, outputs: outputs, efforts: [Efforts.Unsupported](),
        cachesOnlyMarkedPrompts: cachesOnlyMarkedPrompts, fallbacks: fallbacks, serverTools: serverTools, routing: routing,
        cacheControl: cacheControl,
        responseCache: responseCache, options: options, retryLimit: retryLimit)
}

/// A fallback model, with the stub model's limits unless a test sets its own.
func fallback(
    _ id: OpenRouterModelID = "vendor/fallback",
    parameters: Set<OpenRouterParameter> = chatParameters,
    inputs: Set<OpenRouterInputModality> = [.text],
    outputs: Set<OpenRouterOutputModality> = [.text],
    reasoning: ModelReasoning = .offByDefault,
    efforts: [ContextOptions.ReasoningLevel] = [],
    contextSize: Int = 200_000,
    cachesOnlyMarkedPrompts: Bool = false
) -> OpenRouterModel<ContextOptions.ReasoningLevel> {
    OpenRouterModel(
        id: id,
        displayName: "Vendor: Fallback",
        releaseDate: .distantPast,
        contextSize: contextSize,
        inputModalities: inputs,
        outputModalities: outputs,
        supportedParameters: parameters,
        reasoning: reasoning,
        reasoningEfforts: efforts,
        cachesOnlyMarkedPrompts: cachesOnlyMarkedPrompts
    )
}

/// A string value in an entry's metadata.
func metadataString(_ metadata: [String: GeneratedContent], _ key: String) -> String? {
    if case .string(let text)? = metadata[key]?.kind { text } else { nil }
}

/// A number value in an entry's or usage's metadata.
func metadataNumber(_ metadata: [String: GeneratedContent], _ key: String) -> Double? {
    if case .number(let number)? = metadata[key]?.kind { number } else { nil }
}

/// A value in an entry's or usage's metadata as JSON, with whole numbers as integers, so it compares with a literal.
func metadataJSON(_ metadata: [String: GeneratedContent], _ key: String) throws -> JSONValue? {
    try metadata[key].map { try JSONValue(json: JSONValue($0).data) }
}

/// The response entry that ends an answer.
func lastResponse(of response: LanguageModelSession.Response<String>) throws -> Transcript.Response {
    guard case .response(let answer)? = response.transcriptEntries.last else {
        throw MissingResponse(entries: Array(response.transcriptEntries))
    }
    return answer
}

/// An answer didn't end with a response entry.
struct MissingResponse: Error, CustomStringConvertible {
    let entries: [Transcript.Entry]

    var description: String { "The answer doesn't end with a response: \(entries)" }
}

/// The text of an entry's text segments, joined.
func plainText(_ segments: [Transcript.Segment]) -> String {
    segments.compactMap { segment in
        if case .text(let text) = segment { text.content } else { nil }
    }.joined()
}

/// A streamed answer made of the given chunks, then `[DONE]`.
func events(_ chunks: JSONValue...) -> StubResponse {
    eventStream(chunks, isComplete: true)
}

/// A streamed answer from the named model, made of the given chunks, then `[DONE]`.
func events(from model: String, _ chunks: JSONValue...) -> StubResponse {
    eventStream(chunks.map { adding(["model": .string(model)], to: $0) }, isComplete: true)
}

/// A streamed answer made of the given chunks, then `[DONE]`, with the given headers added to the response's.
func events(headers: [String: String], _ chunks: JSONValue...) -> StubResponse {
    let stream = eventStream(chunks, isComplete: true)
    return StubResponse(status: stream.status, headers: stream.headers.merging(headers) { $1 }, chunks: stream.chunks)
}

/// The start of a streamed answer: the given chunks, without the `[DONE]` that ends it.
func unfinishedEvents(_ chunks: JSONValue...) -> StubResponse {
    eventStream(chunks, isComplete: false)
}

private func eventStream(_ chunks: [JSONValue], isComplete: Bool) -> StubResponse {
    let data = chunks.map { "data: \(String(decoding: $0.data, as: UTF8.self))" }
    let lines = [": OPENROUTER PROCESSING"] + data + (isComplete ? ["data: [DONE]"] : [])
    return .eventStream(Data(lines.map { "\($0)\n\n" }.joined().utf8))
}

/// A chunk whose delta is the given object.
func chunk(_ delta: JSONValue, finishReason: String? = nil, usage: JSONValue? = nil) -> JSONValue {
    let choice: JSONValue = ["index": 0, "delta": delta, "finish_reason": finishReason.map(JSONValue.string) ?? .null]
    return ["id": "gen-1", "model": "vendor/model", "provider": "Vendor", "choices": [choice], "usage": usage]
}

/// The chunk with the given top-level fields added or replaced, such as `service_tier`.
func adding(_ fields: [String: JSONValue], to chunk: JSONValue) -> JSONValue {
    guard case .object(var object) = chunk else { return chunk }
    for (key, value) in fields { object[key] = value }
    return .object(object)
}

/// A chunk of answer text.
func text(_ text: String, finishReason: String? = nil) -> JSONValue {
    chunk(["content": .string(text)], finishReason: finishReason)
}

/// A chunk with one tool-call fragment. A fragment without an index leaves the field out.
func toolCall(_ index: Int?, id: String? = nil, name: String? = nil, arguments: String? = nil) -> JSONValue {
    let function: JSONValue = ["name": name.map(JSONValue.string), "arguments": arguments.map(JSONValue.string)]
    let fragment: JSONValue = [
        "index": index.map(JSONValue.integer), "id": id.map(JSONValue.string), "type": "function", "function": function,
    ]
    return chunk(["tool_calls": [fragment]])
}

/// A chunk of reasoning details.
func reasoning(_ details: JSONValue...) -> JSONValue {
    chunk(["reasoning_details": .array(details)])
}

/// The final chunk, with usage.
func done(
    _ finishReason: String = "stop",
    prompt: Int = 12,
    cached: Int = 0,
    cacheWrite: Int? = nil,
    completion: Int = 5,
    reasoning: Int = 0
) -> JSONValue {
    let promptDetails: JSONValue = ["cached_tokens": .integer(cached), "cache_write_tokens": cacheWrite.map(JSONValue.integer)]
    let completionDetails: JSONValue = ["reasoning_tokens": .integer(reasoning)]
    let usage: JSONValue = [
        "prompt_tokens": .integer(prompt),
        "completion_tokens": .integer(completion),
        "total_tokens": .integer(prompt + completion),
        "prompt_tokens_details": promptDetails,
        "completion_tokens_details": completionDetails,
        "cost": .number(0.000_25),
    ]
    return chunk([:], finishReason: finishReason, usage: usage)
}

/// The JSON body of a recorded request.
func body(_ request: RecordedRequest) throws -> JSONValue {
    try JSONValue(json: request.body)
}

/// The JSON body of the stub's request at an index.
func body(_ stub: HTTPStub, _ index: Int = 0) throws -> JSONValue {
    let requests = stub.requests
    guard requests.indices.contains(index) else { throw MissingRequest(index: index, count: requests.count) }
    return try body(requests[index])
}

/// The stub received fewer requests than a test reads.
struct MissingRequest: Error, CustomStringConvertible {
    let index: Int
    let count: Int

    var description: String { "Request \(index) was read, but the stub received \(count)." }
}

/// The messages of a request body.
func messages(_ body: JSONValue) -> [JSONValue] {
    elements(body["messages"])
}

/// The elements of a JSON array, or none when the value isn't one.
func elements(_ value: JSONValue?) -> [JSONValue] {
    if case .array(let elements)? = value { elements } else { [] }
}

/// The assistant messages of the stub's request at an index.
func assistantMessages(_ stub: HTTPStub, _ index: Int = 0) throws -> [JSONValue] {
    messages(try body(stub, index)).filter { $0["role"] == "assistant" }
}

/// Sends one prompt through a new session with the stub's model.
///
/// - Returns: The answer's text.
@discardableResult
func respond(_ stub: HTTPStub, to prompt: String = "Hi", retryLimit: Int = RequestRetries.standard.limit) async throws -> String {
    try await LanguageModelSession(model: model(stub, retryLimit: retryLimit)).respond(to: prompt).content
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
