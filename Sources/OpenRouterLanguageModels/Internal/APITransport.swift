import Foundation
import LanguageModels

/// Reads what OpenRouter's API lists about a model, besides chat completions, and decodes it, through the shared
/// ``InfoTransport``: to the base URL, or OpenRouter's own API, with a failure thrown as a chat request's would be.
struct APITransport: Sendable {
    /// How the calls reach OpenRouter: the session, the authentication and its base URL, and how a call retries.
    let connection: Connection

    /// How long an answer stays fresh in the cache.
    var cacheLifetime: Duration = OpenRouterConfiguration().infoCacheLifetime

    var cache = InfoCache.shared

    /// Reads a path and decodes the answer's body, or reuses a fresh answer from the cache.
    ///
    /// - Parameters:
    ///   - path: The path under the base URL, such as `models/anthropic/claude-haiku-5.5/endpoints`.
    ///   - type: The type of the answer's body.
    /// - Returns: The decoded body.
    /// - Throws: `OpenRouterError` with `invalidResponse` when the body doesn't decode, and otherwise what
    ///   ``OpenRouterFailure``, the authentication and a failed connection throw.
    func value<Value: Decodable & Sendable>(at path: String, as type: Value.Type) async throws -> Value {
        let headers = try await connection.authentication.requestHeaders()
        let base = try API.baseURL(connection.authentication.baseURL)
        let transport = InfoTransport(http: connection.http, logger: .openRouter, cacheLifetime: cacheLifetime, cache: cache)
        return try await transport.value(
            at: base.appending(path: path), path: path, headers: headers, decode: Self.decode,
            failure: { (rejection: HTTPRejection<OpenRouterErrorResponse>) in OpenRouterFailure(rejection).error(contextSize: nil) })
    }

    private static func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try ProviderHTTP.decoder.decode(Value.self, from: data)
        } catch {
            throw OpenRouterError(message: "OpenRouter sent a response that couldn't be read: \(error)", code: .invalidResponse)
        }
    }
}

extension APITransport {
    /// The transport of a catalog model's calls, which aren't tied to a language model.
    ///
    /// - Parameters:
    ///   - auth: How the calls authenticate, and where they go, or `nil` to call OpenRouter without a key.
    ///   - session: The URL session that sends the requests.
    ///   - configuration: How the calls wait, retry and reuse earlier answers.
    /// - Returns: The transport.
    static func calls(auth: OpenRouterAuthentication?, session: URLSession, configuration: OpenRouterConfiguration) -> Self {
        let authentication = auth?.requestAuthentication ?? .unauthenticated
        let connection = Connection(
            session: session, authentication: authentication, idleTimeout: configuration.idleTimeout,
            retries: configuration.retries, retrying: API.retriesStatus)
        return Self(connection: connection, cacheLifetime: configuration.infoCacheLifetime)
    }

    /// The body of OpenRouter's answers, `{"data": …}`.
    struct DataEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
        let data: Value
    }
}
