package import Foundation

/// A fake HTTP host for one test.
///
/// Requests sent through ``session`` to ``baseURL`` get the stub's responses, in order, and the stub records each one.
/// Every stub has its own random host, so tests with different stubs run in parallel. A request after the last
/// response fails with `URLError.resourceUnavailable`.
package final class HTTPStub: Sendable {
    /// The stub's base URL, such as `https://<random>.test`.
    package let baseURL: URL

    /// A session that sends its requests to the stub.
    package let session: URLSession

    /// An element for each request the stub answers, once it has sent the response's chunks, so a test can act while a
    /// response kept open is still in flight.
    package let sentResponses: AsyncStream<Void>

    private let host: String

    /// Creates a stub that serves the given responses, in order.
    ///
    /// - Parameter responses: The responses, one for each request.
    package convenience init(_ responses: StubResponse...) {
        self.init(responses: responses)
    }

    /// Creates a stub that serves the given responses, in order.
    ///
    /// - Parameter responses: The responses, one for each request.
    package init(responses: [StubResponse]) {
        host = "\(UUID().uuidString.lowercased()).test"
        guard let baseURL = URL(string: "https://\(host)") else { preconditionFailure("\(host) isn't a valid host.") }
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        let (sentResponses, sent) = AsyncStream.makeStream(of: Void.self)
        self.sentResponses = sentResponses
        StubURLProtocol.register(host, responses: responses, sent: sent)
    }

    deinit {
        session.invalidateAndCancel()
        StubURLProtocol.unregister(host)
    }

    /// The requests the stub received, oldest first.
    package var requests: [RecordedRequest] {
        StubURLProtocol.requests(for: host)
    }
}
