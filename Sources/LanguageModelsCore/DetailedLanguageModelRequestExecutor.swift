public import FoundationModels

/// Sends a provider's requests: the part of a ``DetailedLanguageModel``'s executor that a provider module writes.
///
/// The model's executor is always a ``DetailedLanguageModelExecutor`` of its request executor, which this module owns.
/// Foundation Models calls the executor, which checks each request before it calls
/// ``execute(_:model:streamingInto:)``, and the answer it returns, so every provider module gets the same checks.
public protocol DetailedLanguageModelRequestExecutor: Sendable {
    /// What the request executor needs to send requests, such as a base URL. It holds no secrets: keep those, such as
    /// an API key closure, on the model.
    associatedtype Configuration: Hashable, Sendable

    /// The model the request executor sends requests for, a ``DetailedLanguageModel`` whose
    /// ``DetailedLanguageModel/RequestExecutor`` is this type.
    associatedtype Model: DetailedLanguageModelBase

    /// Creates a request executor, which the model's executor does from the model's `executorConfiguration`.
    ///
    /// - Parameter configuration: What the request executor needs to send requests.
    /// - Throws: An error when the configuration can't send requests.
    init(configuration: Configuration) throws

    /// Sends one request to the provider and streams its answer.
    ///
    /// - Parameters:
    ///   - request: The transcript, tools, schema and options to send.
    ///   - model: The model to answer with.
    ///   - channel: Where the answer's events go.
    /// - Returns: The answer's response text, which the model's executor checks against the request's schema, or empty
    ///   text when the answer ends in tool calls.
    /// - Throws: `LanguageModelError` for failures Foundation Models has a case for, and an error of the provider
    ///   module's own for the rest.
    func execute(
        _ request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws -> DetailedLanguageModelAnswer
}
