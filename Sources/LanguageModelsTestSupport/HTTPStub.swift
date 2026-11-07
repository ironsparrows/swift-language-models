package import Foundation
import Synchronization

// MARK: - Stub

/// A fake HTTP server for one test.
///
/// Requests sent through ``session`` to ``baseURL`` get the stub's responses, in order, and the stub records each one.
/// Every stub has its own random URL host, so tests with different stubs run in parallel. A request after the last
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

// MARK: - Recorded requests

/// A request that reached an ``HTTPStub``, with its body read out of the request's stream.
package struct RecordedRequest: Sendable {
    /// The request as the stub received it.
    package let request: URLRequest

    /// The request body.
    package let body: Data
}

// MARK: - Responses

/// A canned HTTP response that an ``HTTPStub`` serves.
package struct StubResponse: Sendable {
    /// How a request ends.
    fileprivate enum Ending: Sendable {
        /// The body ends after its last chunk.
        case finished

        /// The request fails before any response arrives, as when the server can't be reached.
        case failedBeforeResponse(URLError)

        /// The body stops with an error after its last chunk, as when the connection drops mid-stream.
        case droppedConnection(URLError)

        /// The connection stays open after the last chunk and sends nothing more, so the client waits until it
        /// cancels.
        case openConnection

        /// The response redirects the request to a URL, or to a path on the same URL host.
        case redirected(to: String)
    }

    /// The HTTP status code.
    package let status: Int

    /// The response headers.
    package let headers: [String: String]

    /// The body, delivered to the client one chunk at a time.
    package let chunks: [Data]

    /// How the request ends.
    fileprivate let ending: Ending

    /// Creates a response that delivers its body in the given chunks.
    ///
    /// - Parameters:
    ///   - status: The HTTP status code.
    ///   - headers: The response headers.
    ///   - chunks: The body, split into the pieces the client receives.
    package init(status: Int = 200, headers: [String: String] = [:], chunks: [Data]) {
        self.init(status: status, headers: headers, chunks: chunks, ending: .finished)
    }

    private init(status: Int, headers: [String: String], chunks: [Data], ending: Ending) {
        self.status = status
        self.headers = headers
        self.chunks = chunks
        self.ending = ending
    }

    /// A request that fails with an error before any response arrives, as when the server can't be reached.
    ///
    /// - Parameter error: The error the request fails with, such as `URLError(.notConnectedToInternet)`.
    /// - Returns: The response.
    package static func failure(_ error: URLError) -> Self {
        StubResponse(status: 0, headers: [:], chunks: [], ending: .failedBeforeResponse(error))
    }

    /// This response with its body cut off by an error after the last chunk, as when the connection drops mid-stream.
    ///
    /// The chunks and the error reach `URLSession` at once, so it may report the error before the client reads any
    /// chunk.
    ///
    /// - Parameter error: The error the body ends with, such as `URLError(.networkConnectionLost)`.
    /// - Returns: The response.
    package func droppingConnection(with error: URLError) -> Self {
        StubResponse(status: status, headers: headers, chunks: chunks, ending: .droppedConnection(error))
    }

    /// This response with its connection left open after the last chunk, as when a server stops sending, so the client
    /// waits for more until it cancels.
    ///
    /// Give the response a `Content-Type` such as `text/event-stream`, as ``eventStream(_:chunkSize:status:)`` does.
    /// Without one, or with `text/plain`, `URLSession` holds the response back while it guesses the type, so the client
    /// gets nothing.
    ///
    /// - Returns: The response.
    package func keepingConnectionOpen() -> Self {
        StubResponse(status: status, headers: headers, chunks: chunks, ending: .openConnection)
    }

    /// A redirect to another URL, which the session follows as its delegate allows, without the request's
    /// `Authorization` header, as `URLSession` drops it.
    ///
    /// A redirect to another stub's URL reaches that stub, since every stub's session reaches every stub.
    ///
    /// - Parameters:
    ///   - location: Where the redirect points: a URL, or a path on the stub's own URL host, such as `/v2/chat`.
    ///   - status: The redirect's status, such as 307.
    /// - Returns: The response.
    package static func redirect(to location: String, status: Int = 307) -> Self {
        StubResponse(status: status, headers: ["Location": location], chunks: [], ending: .redirected(to: location))
    }

    /// A JSON response delivered in one piece.
    ///
    /// - Parameters:
    ///   - body: The JSON text.
    ///   - status: The HTTP status code.
    ///   - headers: Headers added to `Content-Type: application/json`.
    /// - Returns: The response.
    package static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
        StubResponse(
            status: status,
            headers: ["Content-Type": "application/json"].merging(headers) { $1 },
            chunks: [Data(body.utf8)]
        )
    }

    /// A server-sent event stream delivered in small chunks, so lines arrive split across reads.
    ///
    /// - Parameters:
    ///   - body: The raw event stream, such as a recorded fixture.
    ///   - chunkSize: The most bytes in one chunk.
    ///   - status: The HTTP status code.
    /// - Returns: The response.
    package static func eventStream(_ body: Data, chunkSize: Int = 16, status: Int = 200) -> Self {
        let chunks = stride(from: 0, to: body.count, by: chunkSize).map { start in
            body.subdata(in: start..<min(start + chunkSize, body.count))
        }
        return StubResponse(status: status, headers: ["Content-Type": "text/event-stream"], chunks: chunks)
    }
}

// MARK: - URL protocol

/// Serves the responses an ``HTTPStub`` registered for a request's URL host, and records each request.
private final class StubURLProtocol: URLProtocol {
    /// What one stub's URL host has left to serve, what it received, and where it signals a sent response.
    private struct Host {
        var responses: [StubResponse]
        var requests: [RecordedRequest] = []
        let sent: AsyncStream<Void>.Continuation
    }

    private static let hosts = Mutex<[String: Host]>([:])

    static func register(_ host: String, responses: [StubResponse], sent: AsyncStream<Void>.Continuation) {
        hosts.withLock { $0[host] = Host(responses: responses, sent: sent) }
    }

    static func unregister(_ host: String) {
        hosts.withLock { $0.removeValue(forKey: host) }?.sent.finish()
    }

    static func requests(for host: String) -> [RecordedRequest] {
        hosts.withLock { $0[host]?.requests ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client else { return }
        guard let url = request.url, let host = url.host() else {
            client.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (response, sent) = nextResponse(for: host)
        defer { sent?.yield() }
        switch response {
        case .success(let response):
            send(response, from: url, to: client)
        case .failure(let error):
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func send(_ response: StubResponse, from url: URL, to client: any URLProtocolClient) {
        switch response.ending {
        case .failedBeforeResponse(let error):
            client.urlProtocol(self, didFailWithError: error)
        case .finished:
            guard sendHeadAndChunks(of: response, from: url, to: client) else { return }
            client.urlProtocolDidFinishLoading(self)
        case .droppedConnection(let error):
            guard sendHeadAndChunks(of: response, from: url, to: client) else { return }
            client.urlProtocol(self, didFailWithError: error)
        case .openConnection:
            sendHeadAndChunks(of: response, from: url, to: client)
        case .redirected(let location):
            guard
                let target = URL(string: location, relativeTo: url)?.absoluteURL,
                let redirect = HTTPURLResponse(
                    url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)
            else {
                client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            var redirected = request
            redirected.url = target
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
            client.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: redirect)
            // A redirect the delegate refuses ends the request with the redirect itself, as a server's does.
            client.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
        }
    }

    /// Sends the response's status, headers and chunks, or fails the request when they don't make a response.
    @discardableResult
    private func sendHeadAndChunks(of response: StubResponse, from url: URL, to client: any URLProtocolClient) -> Bool {
        guard
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )
        else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return false
        }
        client.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        for chunk in response.chunks {
            client.urlProtocol(self, didLoad: chunk)
        }
        return true
    }

    /// Records the request and takes its URL host's next response, with the continuation to signal once it's sent.
    private func nextResponse(for host: String) -> (Result<StubResponse, URLError>, AsyncStream<Void>.Continuation?) {
        let recorded = RecordedRequest(request: request, body: Self.body(of: request))
        return Self.hosts.withLock { hosts in
            guard var entry = hosts[host] else { return (.failure(URLError(.cannotFindHost)), nil) }
            entry.requests.append(recorded)
            let response = entry.responses.isEmpty ? nil : entry.responses.removeFirst()
            hosts[host] = entry
            return (response.map { .success($0) } ?? .failure(URLError(.resourceUnavailable)), entry.sent)
        }
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            // `InputStream.read` writes through a pointer into `buffer`, which outlives the call.
            let count = unsafe stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(contentsOf: buffer[..<count])
        }
        return body
    }
}
