import Foundation
package import FoundationModels
import LanguageModelsCore

/// Why a request failed, as a dialect's ``ChatCompletionsDialect/error(for:)`` reads it before it becomes the
/// provider's error.
///
/// Only the format's executor creates one.
package struct ChatCompletionsFailure<Dialect: ChatCompletionsDialect>: Error {
    /// What failed.
    package enum Kind: Sendable {
        /// A response whose status isn't a success, after the retries.
        case rejected(HTTPRejection<Dialect.ErrorBody>)

        /// An error event in the stream, which arrives after the response's HTTP 200: the event's `error` object.
        case errorEvent(Dialect.ErrorBody)

        /// A response the format couldn't use.
        case unusableResponse(StreamProblem)

        /// An answer whose finish reason, `error`, says the host failed while it generated.
        case failedAnswer
    }

    package let kind: Kind

    /// What the provider tracked across the answer when it failed, or `nil` before the answer started.
    package let state: Dialect.StreamState?

    /// The request's entries that carry an image, which an error for an image the host rejects names.
    package let imageEntries: [Transcript.Entry]

    init(_ kind: Kind, state: Dialect.StreamState? = nil, imageEntries: [Transcript.Entry]) {
        self.kind = kind
        self.state = state
        self.imageEntries = imageEntries
    }

    /// The format's own words for what went wrong: the status of a failed response, and a sentence for any other
    /// failure.
    package var message: String {
        switch kind {
        case .rejected(let rejection): HTTPURLResponse.localizedString(forStatusCode: rejection.status)
        case .errorEvent: "\(Dialect.name) sent an error."
        case .unusableResponse(let problem): problem.message(provider: Dialect.name)
        case .failedAnswer: "The model's response ended in an error."
        }
    }
}
