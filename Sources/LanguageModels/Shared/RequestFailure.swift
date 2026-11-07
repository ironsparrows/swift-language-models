package import Foundation
package import FoundationModels

/// A request that failed, before a provider says what it becomes.
///
/// An exchange's `error(for:)` reads it and returns the error a session throws: Foundation Models' own when it has a case
/// for the failure, so apps handle it the same way for every model, and otherwise the provider's. Only a shared model
/// creates one, from what it received.
package struct RequestFailure<ErrorBody: Decodable & Sendable>: Error {
    /// What failed.
    package enum Kind: Sendable {
        /// A response whose status isn't a success, after the retries.
        case rejected

        /// An error event in the stream, which arrives after the response's HTTP 200.
        case errorEvent

        /// An answer that ended in an error the host reported.
        case failedAnswer

        /// An event whose data couldn't be read.
        case unreadableEvent

        /// An answer that was cut off, or has a tool call that can't run.
        case unusableAnswer
    }

    /// What failed.
    package let kind: Kind

    /// The HTTP status of a rejected response, or 0 for a response that isn't HTTP; `nil` for a failure in the stream.
    package let status: Int?

    /// The `error` object, or `nil` when the failure carries none, or none in the provider's type, such as a gateway's
    /// HTML page.
    package let body: ErrorBody?

    /// The whole body of a rejected response, for what a provider sends beside the `error` object; empty otherwise.
    package let rawBody: Data

    /// The wait a rejected response's `retry-after-ms` or `Retry-After` header asks for.
    package let retryAfter: Duration?

    /// The format's own words for what went wrong: the status of a rejected response, and a sentence for any other
    /// failure.
    package let message: String

    /// The request's entries that carry an image, which an error for an image the host rejects names.
    package let imageEntries: [Transcript.Entry]

    private let headers: ResponseHeaders

    /// The value of a header of the response, whether it was rejected or failed while it streamed.
    ///
    /// - Parameter name: The header's name, such as `x-request-id`.
    /// - Returns: The value, or `nil` when the response has no such header.
    package func header(_ name: String) -> String? {
        headers.value(named: name)
    }
}

extension RequestFailure {
    /// A response whose status isn't a success, after the retries.
    ///
    /// - Parameters:
    ///   - failure: The response.
    ///   - imageEntries: The request's entries that carry an image.
    init(rejected failure: ProviderHTTP.Failure, imageEntries: [Transcript.Entry]) {
        let rejection = failure.rejection(as: ErrorBody.self)
        kind = .rejected
        status = rejection.status
        body = rejection.body
        rawBody = rejection.rawBody
        retryAfter = rejection.retryAfter
        message = HTTPURLResponse.localizedString(forStatusCode: rejection.status)
        self.imageEntries = imageEntries
        headers = rejection.headers
    }

    /// An error event in the stream.
    ///
    /// - Parameters:
    ///   - body: The event's `error` object.
    ///   - provider: The provider's name, which the message names.
    ///   - headers: The headers of the response whose stream failed.
    ///   - imageEntries: The request's entries that carry an image.
    init(errorEvent body: ErrorBody, provider: String, headers: ResponseHeaders, imageEntries: [Transcript.Entry]) {
        self.init(.errorEvent, body: body, message: "\(provider) sent an error.", headers: headers, imageEntries: imageEntries)
    }

    /// An answer that ended in an error the host reported.
    ///
    /// - Parameters:
    ///   - body: The answer's `error` object, or `nil` when it has none.
    ///   - headers: The headers of the response whose stream failed.
    ///   - imageEntries: The request's entries that carry an image.
    init(failedAnswer body: ErrorBody?, headers: ResponseHeaders, imageEntries: [Transcript.Entry]) {
        let message = "The model's response ended in an error."
        self.init(.failedAnswer, body: body, message: message, headers: headers, imageEntries: imageEntries)
    }

    /// A stream the format couldn't use.
    ///
    /// - Parameters:
    ///   - problem: What went wrong.
    ///   - provider: The provider's name, which the message names.
    ///   - headers: The headers of the response whose stream failed.
    ///   - imageEntries: The request's entries that carry an image.
    init(_ problem: StreamProblem, provider: String, headers: ResponseHeaders, imageEntries: [Transcript.Entry]) {
        let kind: Kind = if case .unreadableEvent = problem { .unreadableEvent } else { .unusableAnswer }
        self.init(kind, body: nil, message: problem.message(provider: provider), headers: headers, imageEntries: imageEntries)
    }

    private init(_ kind: Kind, body: ErrorBody?, message: String, headers: ResponseHeaders, imageEntries: [Transcript.Entry]) {
        self.kind = kind
        status = nil
        self.body = body
        rawBody = Data()
        retryAfter = nil
        self.message = message
        self.imageEntries = imageEntries
        self.headers = headers
    }
}
