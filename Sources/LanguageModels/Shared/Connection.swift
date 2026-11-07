import CryptoKit
package import Foundation
package import LanguageModelsCore
import Synchronization
import os

// MARK: - Connection

/// How a provider's requests reach it: the URL session that sends them, how they authenticate, how long they wait
/// for data and when a request that fails is sent again.
///
/// A provider builds one from its model and its request executor's configuration, or for a call that has no model, such
/// as a catalog entry's info call. The shared models and the provider's info calls send requests through it.
package struct Connection: Sendable {
    /// The URL session that sends the requests.
    private let session: URLSession

    /// The headers that authenticate a request, read for every request.
    package let authentication: Authentication

    /// How long to wait for the next data, or `nil` for the session's own timeout.
    let idleTimeout: Duration?

    /// When a request that fails is sent again, and how long it waits first.
    private let retryPolicy: ProviderHTTP.RetryPolicy

    /// Creates a connection.
    ///
    /// - Parameters:
    ///   - session: The URL session that sends the requests.
    ///   - authentication: The headers that authenticate a request, read for every request.
    ///   - idleTimeout: How long to wait for the next data, or `nil` for the session's own timeout.
    ///   - retries: How a request that fails is sent again, as the app set it.
    ///   - statuses: Whether a response's status is retried when its `x-should-retry` doesn't say.
    package init(
        session: URLSession, authentication: Authentication, idleTimeout: Duration?,
        retries: RequestRetries, retrying statuses: @escaping @Sendable (Int) -> Bool
    ) {
        self.session = session
        self.authentication = authentication
        self.idleTimeout = idleTimeout
        retryPolicy = retries.policy(statuses: statuses)
    }

    /// The client that sends the connection's requests, retrying them as the retry policy says.
    package var http: ProviderHTTP {
        ProviderHTTP(session: session, retryPolicy: retryPolicy)
    }
}

// MARK: - Authentication

extension Connection {
    /// How a provider's requests authenticate, and where they go: the headers to send, read for every request and never
    /// stored, and a base URL that stands in for the provider's own API, such as a proxy's.
    package struct Authentication: Sendable {
        /// The server that stands in for the provider's API, or `nil` for the provider's own.
        package let baseURL: URL?

        private let headers: @Sendable () async throws -> [String: String]

        /// - Parameters:
        ///   - baseURL: The server that stands in for the provider's API, or `nil` for the provider's own.
        ///   - headers: Returns the headers that authenticate a request. It's called for every request.
        package init(baseURL: URL?, headers: @escaping @Sendable () async throws -> [String: String]) {
            self.baseURL = baseURL
            self.headers = headers
        }

        /// No authentication: requests send no credentials and go to the provider's own API.
        package static var unauthenticated: Self {
            Self(baseURL: nil) { [:] }
        }

        /// An API key, sent in the header it makes, such as `Authorization: Bearer …` or `x-api-key`. An empty key sends no
        /// header, as a local server without keys needs.
        ///
        /// - Parameters:
        ///   - key: Returns the key. It's called for every request and never stored.
        ///   - baseURL: The server that stands in for the provider's API, or `nil` for the provider's own.
        ///   - header: The header a key goes in.
        /// - Returns: The authentication.
        package static func apiKey(
            _ key: @escaping @Sendable () async throws -> String,
            baseURL: URL?,
            header: @escaping @Sendable (String) -> [String: String]
        ) -> Self {
            Self(baseURL: baseURL) {
                let key = try await key()
                return key.isEmpty ? [:] : header(key)
            }
        }

        /// Reads the headers, and throws a `URLError` that reading them throws the way a failed connection's is thrown.
        package func requestHeaders() async throws -> [HTTPHeaderName: String] {
            do {
                let read = try await headers()
                return Dictionary(read.map { (HTTPHeaderName(rawValue: $0.key), $0.value) }, uniquingKeysWith: { $1 })
            } catch let error as URLError {
                throw error.thrownError
            }
        }
    }
}

// MARK: - Opening a stream

extension Connection {
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
    ///   format turns into the provider's error; what the authentication and `url` throw; and a failed connection's
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

/// The constraints of a response schema that some hosts reject.
package enum SchemaConstraint {
    /// Whether a host rejected a constraint of the response schema: a 400 whose message names a constraint keyword,
    /// one the portable schema moves into descriptions, and says it isn't supported, permitted or allowed. Seed sends
    /// "Keyword 'maxItems' is not supported for type 'array'", and Cohere "received non-supported constraint for type:
    /// 'array'. constraint: 'minItems'".
    ///
    /// - Parameters:
    ///   - status: The response's HTTP status.
    ///   - message: The response's error, such as its body's text.
    /// - Returns: Whether the request may go again with the portable schema.
    package static func isRejected(status: Int, message: String) -> Bool {
        guard status == 400 else { return false }
        let constraint =
            #/
            \b(minItems | maxItems | uniqueItems | minimum | maximum | exclusiveMinimum | exclusiveMaximum | multipleOf
            | minLength | maxLength | pattern)\b
            /#
        return message.contains(constraint) && message.contains(/(?i)not supported|non-supported|unsupported|not permitted|not allowed/)
    }
}

// MARK: - Cached calls

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
        failure: (RequestFailure<ErrorBody>) -> MappedError<ProviderError>
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
                throw failure(RequestFailure(rejected: rejected, imageEntries: [])).error
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

extension InfoTransport {
    /// The messages one call to a provider's API besides generation logs, such as for a model's info.
    ///
    /// Calls log at `debug` how they end and whether the cache answered, at `info` their retries, and at `error` how
    /// they fail. They log the path, but never the key.
    struct CallLog {
        private let operation: OperationLog
        private var status: Int?

        /// Starts the log of a call, and its timing.
        ///
        /// - Parameters:
        ///   - path: The path under the base URL, such as `models/anthropic/claude-haiku-5.5/endpoints`.
        ///   - logger: The provider's log category.
        init(path: String, logger: PackageLogger) {
            operation = OperationLog("GET \(path)", logger: logger)
        }

        mutating func received(status: Int) {
            self.status = status
        }

        func answeredFromCache() {
            operation.logger(.debug)?.debug("\(operation.label, privacy: .public) answered from the cache.")
        }

        func retrying(_ retry: ProviderHTTP.Retry) {
            operation.retrying(retry)
        }

        func finished() {
            operation.logger(.debug)?.debug(
                "\(operation.label, privacy: .public) answered with HTTP \(status ?? 0) in \(operation.elapsedMilliseconds) ms.")
        }

        /// Logs a cancelled call at `debug`, and any other failure at `error`, with the error it became.
        func failed(_ error: any Error) {
            operation.failed(error)
        }
    }
}

/// Recent answers of a provider's info calls, kept in memory so repeated calls, such as one for each row of a list,
/// don't fetch them again.
///
/// An answer is kept by its URL and a digest of the headers that authenticated the call, never the headers themselves,
/// since some answers depend on the account. Failures aren't kept.
package final class InfoCache: Sendable {
    /// The cache that every call shares.
    package static let shared = InfoCache()

    /// What an answer is kept by.
    package struct Key: Hashable, Sendable {
        package let url: URL

        /// The SHA-256 digest of the headers that authenticated the call, or `nil` for a call without any.
        package let account: String?

        package init(url: URL, headers: [HTTPHeaderName: String]) {
            self.url = url
            let lines = headers.map { "\($0.key.rawValue.lowercased()): \($0.value)" }.sorted()
            account = lines.isEmpty ? nil : SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).description
        }
    }

    private struct Entry: Sendable {
        let value: any Sendable
        let expiry: ContinuousClock.Instant
    }

    private let entries = Mutex<[Key: Entry]>([:])

    /// Creates an empty cache, such as one of a test's own.
    package init() {}

    /// The answer kept for a key, or `nil` when there's none or it expired.
    package func value<Value: Sendable>(for key: Key, as type: Value.Type, now: ContinuousClock.Instant = .now) -> Value? {
        entries.withLock { entries in
            guard let entry = entries[key] else { return nil }
            guard entry.expiry > now else {
                entries[key] = nil
                return nil
            }
            return entry.value as? Value
        }
    }

    /// Keeps an answer for a while, and drops every answer that expired.
    ///
    /// - Parameters:
    ///   - value: The decoded answer.
    ///   - key: What the answer is kept by.
    ///   - lifetime: How long to keep it; zero or less keeps nothing.
    ///   - now: The time the lifetime counts from.
    package func store(_ value: some Sendable, for key: Key, lifetime: Duration, now: ContinuousClock.Instant = .now) {
        guard lifetime > .zero else { return }
        entries.withLock { entries in
            entries = entries.filter { $0.value.expiry > now }
            entries[key] = Entry(value: value, expiry: now + lifetime)
        }
    }
}
