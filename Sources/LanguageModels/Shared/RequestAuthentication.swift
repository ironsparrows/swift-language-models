package import Foundation

/// How a provider's requests authenticate, and where they go: the headers to send, read for every request and never
/// stored, and a base URL that stands in for the provider's own API, such as a proxy's.
package struct RequestAuthentication: Sendable {
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
        header: @escaping @Sendable (String) -> [HTTPHeaderName: String]
    ) -> Self {
        Self(baseURL: baseURL) {
            let key = try await key()
            return key.isEmpty ? [:] : Dictionary(uniqueKeysWithValues: header(key).map { ($0.key.rawValue, $0.value) })
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
