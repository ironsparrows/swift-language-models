import FoundationModels
import LanguageModels

/// What OpenAI reports about one answer beyond the format's facts: the request's id, from the response's headers.
struct OpenAIStreamState: Sendable {
    /// OpenAI's id for the request.
    let requestID: String?
}

extension OpenAIResponses {
    func streamState(_ headers: ResponseHeaders) -> OpenAIStreamState {
        OpenAIStreamState(requestID: headers.value(for: .requestID))
    }

    /// The request's id, on the entry that ends the answer.
    func facts(of state: OpenAIStreamState) -> AnswerFacts {
        var metadata: [String: any ConvertibleToGeneratedContent] = [:]
        metadata[LanguageModelMetadataKey.requestID] = state.requestID
        return AnswerFacts(metadata: metadata)
    }

    /// What a failure becomes: `LanguageModelError` for a rate limit, an oversized context, a safety system, a timeout
    /// or an image OpenAI can't use, and `OpenAIError` otherwise, with `invalidResponse` for a response the format
    /// couldn't use.
    func error(for failure: ResponsesFailure<Self>) -> MappedError<OpenAIError> {
        let requestID = failure.state?.requestID
        switch failure.kind {
        case .rejected(let rejection):
            return OpenAIFailure(rejection).error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .errorEvent(let body):
            return OpenAIFailure(streamError: body, requestID: requestID)
                .error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .failedResponse(let body):
            return OpenAIFailure(streamError: body, requestID: requestID)
                .error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .unusableResponse:
            return .provider(OpenAIError(message: failure.message, code: .invalidResponse, requestID: requestID))
        }
    }
}
