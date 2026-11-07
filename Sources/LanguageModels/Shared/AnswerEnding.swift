import FoundationModels
package import LanguageModelsCore

/// Why an answer that arrived whole fails anyway: the model declined, a content filter stopped it, or it reached its
/// token limit inside a tool call or a guided answer.
package enum AnswerEnding: Equatable {
    /// The model declined, with its explanation.
    case refusal(String)

    /// A content filter stopped the answer.
    case contentFilter

    /// The answer reached its token limit inside a tool call, so no tool may get partial arguments. Each format reports
    /// it as a failure of its own.
    case tokenLimitInToolCall

    /// A guided answer reached its token limit, so it would decode as a wrong value.
    case tokenLimitInGuidedAnswer

    /// The way an answer fails, or `nil` when it ended well, in this order: a refusal, a content filter, then the token
    /// limit.
    ///
    /// - Parameters:
    ///   - refusal: The refusal text the model sent, empty for none.
    ///   - finishReason: Why the answer ended.
    ///   - hasToolCalls: Whether the answer has tool calls.
    ///   - requiresCompleteAnswer: Whether the answer must be whole, as a guided answer must.
    package init?(refusal: String, finishReason: FinishReason?, hasToolCalls: Bool, requiresCompleteAnswer: Bool) {
        switch finishReason {
        case _ where !refusal.isEmpty: self = .refusal(refusal)
        case .contentFilter?: self = .contentFilter
        case .length? where hasToolCalls: self = .tokenLimitInToolCall
        case .length? where requiresCompleteAnswer: self = .tokenLimitInGuidedAnswer
        default: return nil
        }
    }

    /// The error the answer ends in, or `nil` for ``tokenLimitInToolCall``, which the format reports as a failure of
    /// its own.
    ///
    /// - Parameters:
    ///   - responseText: The answer's text, which a parsing error carries.
    ///   - host: The company whose servers ran the model, when the provider names one.
    /// - Returns: `LanguageModelError.refusal` or `.guardrailViolation`, or `GeneratedContent.ParsingError`.
    package func error(responseText: String, host: String?) -> (any Error)? {
        let metadata = LanguageModelError.failureMetadata(status: nil, code: nil, provider: host)
        switch self {
        case .refusal(let refusal):
            return LanguageModelError(.refusal, message: refusal, metadata: metadata)
        case .contentFilter:
            return LanguageModelError(.guardrailViolation, message: "A content filter stopped the response.", metadata: metadata)
        case .tokenLimitInToolCall:
            return nil
        case .tokenLimitInGuidedAnswer:
            return GeneratedContent.ParsingError(
                rawContent: responseText, debugDescription: "The answer reached its token limit before it was complete.")
        }
    }
}

/// Why an answer whose stream ended fails anyway, as
/// ``AnswerChannel/finish(report:facts:refusal:requiresCompleteAnswer:failedAnswer:)`` says.
package enum AnswerFailure {
    /// A problem the format reports as a failure of its own, such as the token limit reached inside a tool call.
    case unusable(StreamProblem)

    /// The error the answer ends in, such as Foundation Models' refusal.
    case failed(any Error)
}

extension FinishReason {
    /// The reason for an answer a content filter stopped, which throws instead of ending an entry.
    package static let contentFilter: Self = "content_filter"
}
