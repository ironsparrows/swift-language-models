package import Foundation

/// The headers of a provider's response, as a provider and an error mapping read them.
///
/// Only ``ProviderHTTP`` makes them, from the response it received.
package struct ResponseHeaders: Sendable {
    private let response: HTTPURLResponse?

    init(_ response: HTTPURLResponse?) {
        self.response = response
    }

    /// The value of a header by its name, as a provider asks for it, or `nil` when the response has none.
    func value(named name: String) -> String? {
        response?.value(forHTTPHeaderField: name)
    }

    /// The value of one of the headers, or `nil` when the response has none.
    package func value(for header: HTTPHeaderName) -> String? {
        response?.value(forHTTPHeaderField: header.rawValue)
    }
}
