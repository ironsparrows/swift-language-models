package import Foundation
import LanguageModelsCore

/// Reads what a provider's API lists about a model, besides generation: a `GET` through ``ProviderHTTP``, logged as a
/// ``InfoTransport/CallLog``, with an answer from ``InfoCache`` reused while it's fresh.
package struct InfoTransport: Sendable {
    private let http: ProviderHTTP
    private let logger: PackageLogger

    /// How long an answer stays fresh in the cache.
    private let cacheLifetime: Duration

    private let cache: InfoCache

    package init(http: ProviderHTTP, logger: PackageLogger, cacheLifetime: Duration, cache: InfoCache = .shared) {
        self.http = http
        self.logger = logger
        self.cacheLifetime = cacheLifetime
        self.cache = cache
    }

    /// Reads a URL and decodes the answer's body, or reuses a fresh answer from the cache.
    ///
    /// - Parameters:
    ///   - url: The URL to read.
    ///   - path: The URL's path under the API, which names the call in the log.
    ///   - headers: The headers that authenticate the call, or none.
    ///   - decode: Decodes the body, throwing the provider's error for one it can't read.
    ///   - failure: The error a status that isn't a success becomes.
    /// - Returns: The decoded body.
    /// - Throws: What `decode` and `failure` give, and what a session's request throws for a failed connection.
    package func value<Value: Sendable, ErrorBody: Decodable & Sendable, ProviderError: Error>(
        at url: URL,
        path: String,
        headers: [HTTPHeaderName: String],
        decode: (Data) throws -> Value,
        failure: (HTTPRejection<ErrorBody>) -> MappedError<ProviderError>
    ) async throws -> Value {
        var log = InfoTransport.CallLog(path: path, logger: logger)
        let key = InfoCache.Key(url: url, headers: headers)
        if let value = cache.value(for: key, as: Value.self) {
            log.answeredFromCache()
            return value
        }
        do {
            let request = ProviderHTTP.request(url: url, authHeaders: headers)
            let (data, response): (Data, HTTPURLResponse?)
            do {
                (data, response) = try await http.data(for: request) { [log] in log.retrying($0) }
            } catch let rejected as ProviderHTTP.Failure {
                throw failure(rejected.rejection(as: ErrorBody.self)).error
            }
            log.received(status: response?.statusCode ?? 0)
            let value = try decode(data)
            cache.store(value, for: key, lifetime: cacheLifetime)
            log.finished()
            return value
        } catch {
            log.failed(error)
            throw error
        }
    }
}
