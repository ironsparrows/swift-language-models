package import Foundation
package import LanguageModelsCore

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
