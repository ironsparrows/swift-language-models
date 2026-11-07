import Foundation
import FoundationModels
import LanguageModelsCore

/// Sends a dialect's Chat Completions requests and streams each answer into Foundation Models.
struct ChatCompletionsExecutor<Dialect: ChatCompletionsDialect>: FormatExecutor {
    let dialect: Dialect

    /// The path of the chat completions call under the provider's base URL.
    static var path: String { "chat/completions" }

    /// The body's members that aren't options: the model, the transcript and `stream`.
    static var nonOptions: Set<String> {
        [ChatCompletions.Member.model.rawValue, ChatCompletions.Member.messages.rawValue, ChatCompletions.Member.stream.rawValue]
    }

    func request(for request: LanguageModelExecutorGenerationRequest) throws -> ChatCompletionRequest {
        try ChatCompletionRequest(request, dialect: dialect)
    }

    func headers(for request: LanguageModelExecutorGenerationRequest) -> [HTTPHeaderName: String] {
        dialect.headers(HeaderContext(request))
    }

    func error(rejecting failure: ProviderHTTP.Failure, of request: ChatCompletionRequest) -> any Error {
        let rejected = ChatCompletionsFailure<Dialect>(
            .rejected(failure.rejection(as: Dialect.ErrorBody.self)), imageEntries: request.imageEntries)
        return dialect.error(for: rejected).error
    }

    func answer(
        to request: ChatCompletionRequest,
        of generationRequest: LanguageModelExecutorGenerationRequest,
        streamingInto channel: LanguageModelExecutorGenerationChannel,
        headers: ResponseHeaders
    ) -> ChatCompletionsAnswerStream<Dialect> {
        ChatCompletionsAnswerStream(
            channel: channel, dialect: dialect, headers: headers, imageEntries: request.imageEntries,
            requiresCompleteAnswer: generationRequest.schema != nil)
    }
}
