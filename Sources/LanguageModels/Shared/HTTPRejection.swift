package import Foundation

/// A response whose status isn't a success, as a provider's error mapping reads it: the status, the `error` object of
/// its body in the provider's type, the body as it arrived, the wait it asks for, and its headers.
///
/// Only ``ProviderHTTP`` makes one, from the response it received, so a mapping can't be handed a made-up failure.
package struct HTTPRejection<Body: Decodable & Sendable>: Sendable {
    /// The HTTP status, or 0 for a response that isn't HTTP.
    package let status: Int

    /// The `error` object of the body, `{"error": {…}}`, or `nil` when the body isn't one the provider sends, such as a
    /// gateway's HTML page.
    package let body: Body?

    /// The body as it arrived, for what a provider sends beside the `error` object.
    package let rawBody: Data

    /// The wait the response's `Retry-After` header asks for.
    package let retryAfter: Duration?

    /// The response's headers.
    package let headers: ResponseHeaders

    init(_ failure: ProviderHTTP.Failure) {
        status = failure.status
        body = try? ProviderHTTP.decoder.decode(Envelope.self, from: failure.body).error
        rawBody = failure.body
        retryAfter = failure.retryAfter
        headers = ResponseHeaders(failure.response)
    }

    /// The body of a failed response, `{"error": {…}}`.
    private struct Envelope: Decodable {
        let error: Body
    }
}

extension ProviderHTTP.Failure {
    /// The failure as a provider's error mapping reads it, with the body's `error` object in the provider's type.
    package func rejection<Body>(as body: Body.Type) -> HTTPRejection<Body> {
        HTTPRejection(self)
    }
}
