public import FoundationModels
import LanguageModels

extension OpenAILanguageModel.RequestExecutor {
    /// Sends one request and streams its answer.
    ///
    /// A failed request is retried up to twice, only before any data arrives, as the official SDKs retry it: after a
    /// failed connection, a 408, 409 or 429, any status from 500 up, or any status whose `x-should-retry` is `true`,
    /// unless its `x-should-retry` is `false` or its `retry-after-ms` or `Retry-After` asks for more than 2 minutes. A
    /// request whose schema has a constraint OpenAI rejects is sent once more with the portable schema, which carries
    /// its constraints in descriptions.
    ///
    /// - Parameters:
    ///   - request: The transcript, tools, schema and options to send.
    ///   - model: The model to answer with.
    ///   - channel: Where the answer's events go.
    /// - Returns: The answer's response text, which the model's executor checks against the request's schema.
    /// - Throws: `LanguageModelError` for failures Foundation Models has a case for, `OpenAIError` for the rest, and
    ///   `CancellationError` when the task is cancelled. An error that the model's authentication throws passes through
    ///   as it is, unless it's a `URLError`, which maps as a failed connection's does.
    public func execute(
        _ request: LanguageModelExecutorGenerationRequest,
        model: OpenAILanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws -> DetailedLanguageModelAnswer {
        try await respond(to: request, model: model, streamingInto: channel, as: OpenAIResponses<Effort>.self)
    }
}
