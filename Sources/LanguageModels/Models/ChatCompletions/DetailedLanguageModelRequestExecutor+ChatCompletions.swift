package import FoundationModels
package import LanguageModelsCore

extension DetailedLanguageModelRequestExecutor {
    /// Sends one request in OpenAI's Chat Completions format, in a provider's dialect, and streams its answer.
    ///
    /// The format's executor builds the body from Foundation Models' request with the dialect's members, logs what it
    /// sends and what it changed from what the app asked for, and sends it with the authentication's headers and the
    /// dialect's. A request is retried before any data arrives as the retry policy of the dialect's connection says,
    /// and once with the portable schema when the host rejects a constraint of the full one. The answer streams into
    /// the channel, with the dialect's own members of each chunk read alongside the format's. Every failure becomes
    /// what the dialect maps it to.
    ///
    /// It's the format's only way in: the dialect is created here from the model and this request executor, so a
    /// request executor can only run a dialect made for its own model.
    ///
    /// - Parameters:
    ///   - request: The transcript, tools, schema and options to send.
    ///   - model: The model to answer with.
    ///   - channel: Where the answer's events go.
    ///   - dialect: The provider's dialect.
    /// - Returns: The answer's response text, which the model's executor checks against the request's schema, or
    ///   empty text when the answer ends in tool calls.
    /// - Throws: `LanguageModelError` for failures Foundation Models has a case for, the provider's errors for the
    ///   rest, a failed connection's error as `URLError` maps it, what the authentication throws, and
    ///   `CancellationError` when the task is cancelled.
    package func respond<Dialect: ChatCompletionsDialect>(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel,
        as dialect: Dialect.Type
    ) async throws -> DetailedLanguageModelAnswer where Dialect.Model == Model, Dialect.Model.RequestExecutor == Self {
        let executor = ChatCompletionsExecutor(dialect: Dialect(model: model, executor: self))
        return try await executor.respond(to: request, streamingInto: channel)
    }
}
