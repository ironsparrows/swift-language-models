package import Foundation
package import LanguageModelsCore

extension ProviderConnection {
    /// Sends a format's request with the authentication's headers and the provider's, and opens its stream of
    /// server-sent events, sending it once more with the portable schema when the host rejects a constraint of the full
    /// one.
    ///
    /// The authentication's headers are read before the URL, so a failure to read them comes first.
    ///
    /// - Parameters:
    ///   - body: The request's body.
    ///   - portableSchemaBody: The body with its response schema in portable form, or `nil` when there's none to try.
    ///   - headers: The provider's headers, which take precedence over the authentication's.
    ///   - url: Returns where the request goes, or throws the provider's error when there's no valid URL.
    ///   - log: The request's log.
    /// - Returns: The stream, and the headers of its response.
    /// - Throws: ``ProviderHTTP/Failure`` for a response whose status isn't a success, after the retries, which the
    ///   format turns into the dialect's error; what the authentication and `url` throw; and a failed connection's
    ///   error.
    package func openEventStream(
        body: JSONValue,
        portableSchemaBody: JSONValue?,
        headers: [HTTPHeaderName: String],
        url: () throws -> URL,
        log: OperationLog
    ) async throws -> (URLSession.AsyncBytes, ResponseHeaders) {
        let authHeaders = try await authentication.requestHeaders()
        var request = ProviderHTTP.request(
            url: try url(), method: HTTPMethod.post, body: body.data, accept: MediaType.eventStream, authHeaders: authHeaders,
            headers: headers, idleTimeout: idleTimeout)
        var portableSchemaBody = portableSchemaBody
        while true {
            let rejected: ProviderHTTP.Failure
            do {
                return try await http.stream(for: request) { log.retrying($0) }
            } catch let failure as ProviderHTTP.Failure {
                rejected = failure
            }
            guard let body = portableSchemaBody,
                SchemaConstraint.isRejected(status: rejected.status, message: String(decoding: rejected.body, as: UTF8.self))
            else { throw rejected }
            log.retryingWithPortableSchema(host: nil)
            request.httpBody = body.data
            portableSchemaBody = nil
        }
    }
}
