package import Foundation
package import FoundationModels
import LanguageModelsCore

extension LanguageModelError {
    /// A failure a provider reported that Foundation Models has a case for.
    package enum ProviderFailure {
        /// The prompt is longer than the model's context, with the sizes when known; 0 stands for an unknown one.
        case contextSizeExceeded(contextSize: Int, tokenCount: Int)
        case rateLimited(resetDate: Date?)
        case guardrailViolation
        case refusal
        case timeout
        /// Content of these entries that the host can't use, such as an image in a format it doesn't take.
        case unsupportedContent([Transcript.Entry])
    }

    /// The error a provider's failure becomes.
    ///
    /// - Parameters:
    ///   - failure: The Foundation Models case the failure stands for.
    ///   - message: What went wrong, as the provider said it.
    ///   - metadata: The failure's facts, under the shared keys such as `status`, and the provider's own.
    package init(_ failure: ProviderFailure, message: String, metadata: [String: any Sendable]) {
        switch failure {
        case .contextSizeExceeded(let contextSize, let tokenCount):
            var exceeded = ContextSizeExceeded(contextSize: contextSize, tokenCount: tokenCount, debugDescription: message)
            // Foundation Models 2.1.14, in Xcode 27.2, drops the initializer's `metadata` argument, so it's set afterwards.
            exceeded.metadata = metadata
            self = .contextSizeExceeded(exceeded)
        case .rateLimited(let resetDate):
            self = .rateLimited(.init(resetDate: resetDate, debugDescription: message, metadata: metadata))
        case .guardrailViolation:
            self = .guardrailViolation(.init(debugDescription: message, metadata: metadata))
        case .refusal:
            self = .refusal(.init(explanation: message, debugDescription: message, metadata: metadata))
        case .timeout:
            self = .timeout(.init(debugDescription: message, metadata: metadata))
        case .unsupportedContent(let entries):
            self = .unsupportedTranscriptContent(.init(unsupportedContent: entries, debugDescription: message, metadata: metadata))
        }
    }
}

extension LanguageModelError.ProviderFailure {
    /// The sizes the message of an oversized prompt's error names, each when it names it: the model's context size,
    /// as in "maximum context length is 8192" or "context window of 8192", and the tokens the request needs, as in
    /// "requested about 9000" or "resulted in 9000".
    ///
    /// - Parameter message: The error's message.
    /// - Returns: The context size and the tokens the request needs.
    package static func contextSizes(in message: String) -> (limit: Int?, requested: Int?) {
        let limit = message.firstMatch(of: /(?:maximum context length is|context window of) (\d+)/).flatMap { Int($0.1) }
        let requested = message.firstMatch(of: /(?:requested (?:about )?|resulted in )(\d+)/).flatMap { Int($0.1) }
        return (limit, requested)
    }
}
