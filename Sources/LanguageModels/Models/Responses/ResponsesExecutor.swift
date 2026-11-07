import Foundation
import FoundationModels
import LanguageModelsCore

/// Sends a dialect's Responses requests and streams each answer into Foundation Models.
struct ResponsesExecutor<Dialect: ResponsesDialect>: FormatExecutor {
    let dialect: Dialect

    /// The path of the responses call under the provider's base URL.
    static var path: String { "responses" }

    /// The body's members that aren't options: the model, the input and `stream`.
    static var nonOptions: Set<String> {
        [Responses.Member.model.rawValue, Responses.Member.input.rawValue, Responses.Member.stream.rawValue]
    }

    func request(for request: LanguageModelExecutorGenerationRequest) throws -> ResponsesRequest {
        try ResponsesRequest(request, dialect: dialect)
    }

    /// No headers beyond the authentication's.
    func headers(for request: LanguageModelExecutorGenerationRequest) -> [HTTPHeaderName: String] {
        [:]
    }

    func error(rejecting failure: ProviderHTTP.Failure, of request: ResponsesRequest) -> any Error {
        let rejected = ResponsesFailure<Dialect>(
            .rejected(failure.rejection(as: Dialect.ErrorBody.self)), imageEntries: request.imageEntries)
        return dialect.error(for: rejected).error
    }

    func answer(
        to request: ResponsesRequest,
        of generationRequest: LanguageModelExecutorGenerationRequest,
        streamingInto channel: LanguageModelExecutorGenerationChannel,
        headers: ResponseHeaders
    ) -> ResponsesAnswerStream<Dialect> {
        ResponsesAnswerStream(
            channel: channel, dialect: dialect, headers: headers, imageEntries: request.imageEntries,
            requiresCompleteAnswer: generationRequest.schema != nil)
    }
}
