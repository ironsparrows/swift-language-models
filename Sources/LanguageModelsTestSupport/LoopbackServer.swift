package import Foundation
import Network
import Synchronization
package import Testing

// MARK: - Server

/// A scripted HTTP server on 127.0.0.1, with a port the system picks.
///
/// An ``HTTPStub`` answers inside `URLSession` and never touches a socket. This server does, for what only a socket
/// shows: an answer that arrives in pieces, a second request on a real connection, a redirect that `URLSession` handles
/// itself, a connection the client closes.
///
/// Each connection gets the next reply, in order, and the server records its request. A request after the last reply
/// is closed unanswered.
package final class LoopbackServer: Sendable {
    /// The server's base URL, such as `http://127.0.0.1:52014`.
    package let baseURL: URL

    /// An element for each reply the server has written, so a test can act while a reply kept open is in flight.
    private let sentReplies: AsyncStream<Void>

    /// An element each time a client closes a connection that a reply kept open.
    package let closedConnections: AsyncStream<Void>

    private let listener: NWListener
    private let script: Script

    /// Starts a server that sends the given replies, in order.
    ///
    /// - Parameter replies: The replies, one for each request.
    /// - Throws: The listener's error, when it can't start.
    package convenience init(_ replies: LoopbackReply...) async throws {
        try await self.init { _ in replies }
    }

    /// Starts a server that sends replies that name its own URL, such as a redirect.
    ///
    /// - Parameter replies: Returns the replies, one for each request, for the server's base URL.
    /// - Throws: The listener's error, when it can't start.
    package init(_ replies: (URL) -> [LoopbackReply]) async throws {
        let (sentReplies, sent) = AsyncStream.makeStream(of: Void.self)
        let (closedConnections, closed) = AsyncStream.makeStream(of: Void.self)
        let script = Script(sent: sent, closed: closed)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in Task { await script.serve(connection) } }
        do {
            try await withCheckedThrowingContinuation { (started: CheckedContinuation<Void, any Error>) in
                let started = Mutex<CheckedContinuation<Void, any Error>?>(started)
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready: started.withLock { $0.take()?.resume() }
                    case .failed(let error), .waiting(let error): started.withLock { $0.take()?.resume(throwing: error) }
                    case .cancelled: started.withLock { $0.take()?.resume(throwing: CancellationError()) }
                    default: break
                    }
                }
                listener.start(queue: .global())
            }
        } catch {
            listener.cancel()
            throw error
        }
        guard let port = listener.port?.rawValue, let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            preconditionFailure("A ready listener has a port.")
        }
        script.add(replies(baseURL))
        self.baseURL = baseURL
        self.sentReplies = sentReplies
        self.closedConnections = closedConnections
        self.listener = listener
        self.script = script
    }

    deinit {
        listener.cancel()
        script.finish()
    }

    /// The requests the server received, oldest first.
    package var requests: [RecordedRequest] {
        script.requests
    }
}

// MARK: - Replies

/// What a ``LoopbackServer`` sends for one request.
package struct LoopbackReply: Sendable {
    /// What happens to the connection after the last write.
    package enum Ending: Sendable {
        /// The server closes the connection, which ends the body.
        case closes

        /// The connection stays open and quiet until the client closes it.
        case staysOpen
    }

    fileprivate let status: Int
    fileprivate let headers: [String: String]
    fileprivate let writes: [Data]
    fileprivate let ending: Ending

    /// Creates a reply.
    ///
    /// - Parameters:
    ///   - status: The HTTP status code.
    ///   - headers: The response headers.
    ///   - writes: The body, each element written to the socket on its own.
    ///   - ending: What happens to the connection after the last write.
    package init(status: Int = 200, headers: [String: String] = [:], writes: [Data] = [], ending: Ending = .closes) {
        self.status = status
        self.headers = headers
        self.writes = writes
        self.ending = ending
    }

    /// A stream of server-sent events, written a few bytes at a time.
    ///
    /// - Parameters:
    ///   - body: The whole body.
    ///   - size: The bytes in each write.
    ///   - ending: What happens to the connection after the last write.
    /// - Returns: The reply.
    package static func eventStream(_ body: String, writing size: Int = .max, ending: Ending = .closes) -> Self {
        let bytes = Data(body.utf8)
        let writes = stride(from: 0, to: bytes.count, by: min(size, max(bytes.count, 1))).map {
            bytes[$0..<min($0 + size, bytes.count)]
        }
        return LoopbackReply(headers: ["Content-Type": "text/event-stream"], writes: writes, ending: ending)
    }
}

// MARK: - Connections

extension LoopbackServer {
    /// The replies left, the requests received, and how each connection is served.
    private final class Script: Sendable {
        private struct State {
            var replies: [LoopbackReply] = []
            var requests: [RecordedRequest] = []
        }

        private let state: Mutex<State>
        private let sent: AsyncStream<Void>.Continuation
        private let closed: AsyncStream<Void>.Continuation

        init(sent: AsyncStream<Void>.Continuation, closed: AsyncStream<Void>.Continuation) {
            state = Mutex(State())
            self.sent = sent
            self.closed = closed
        }

        /// Adds replies, before any client knows the server's URL.
        func add(_ replies: [LoopbackReply]) {
            state.withLock { $0.replies += replies }
        }

        /// Ends what a test may be waiting for.
        func finish() {
            sent.finish()
            closed.finish()
        }

        var requests: [RecordedRequest] {
            state.withLock(\.requests)
        }

        /// Reads one request from a new connection and sends the next reply.
        func serve(_ connection: NWConnection) async {
            connection.start(queue: .global())
            defer { connection.cancel() }
            guard let request = await Self.readRequest(connection), let reply = record(request) else { return }
            await Self.send(Self.head(of: reply), on: connection)
            for write in reply.writes {
                await Self.send(write, on: connection)
                // The pause keeps each write apart on the socket.
                try? await Task.sleep(for: .milliseconds(1))
            }
            sent.yield()
            if reply.ending == .staysOpen {
                await Self.waitForClose(of: connection)
                closed.yield()
            }
        }

        /// Records a request, and takes its reply.
        private func record(_ request: RecordedRequest) -> LoopbackReply? {
            state.withLock { state in
                state.requests.append(request)
                return state.replies.isEmpty ? nil : state.replies.removeFirst()
            }
        }

        /// The status line and headers of a reply. `Connection: close` lets the end of the connection end the body.
        private static func head(of reply: LoopbackReply) -> Data {
            let reason = HTTPURLResponse.localizedString(forStatusCode: reply.status)
            let fields = reply.headers.merging(["Connection": "close"]) { $1 }.map { "\($0.key): \($0.value)\r\n" }
            return Data("HTTP/1.1 \(reply.status) \(reason)\r\n\(fields.joined())\r\n".utf8)
        }

        private static func send(_ data: Data, on connection: NWConnection) async {
            await withCheckedContinuation { sent in
                connection.send(content: data, completion: .contentProcessed { _ in sent.resume() })
            }
        }

        /// The next bytes of a connection, or `nil` once the client closed it.
        private static func receive(_ connection: NWConnection) async -> Data? {
            await withCheckedContinuation { received in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                    received.resume(returning: data?.isEmpty == false ? data : nil)
                }
            }
        }

        private static func waitForClose(of connection: NWConnection) async {
            while await receive(connection) != nil {}
        }

        /// Reads a request's head and the body its `Content-Length` announces.
        private static func readRequest(_ connection: NWConnection) async -> RecordedRequest? {
            let separator = Data("\r\n\r\n".utf8)
            var bytes = Data()
            while true {
                if let end = bytes.range(of: separator) {
                    let lines = String(decoding: bytes[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
                    guard var request = request(from: lines) else { return nil }
                    let length = request.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init) ?? 0
                    if bytes.count - end.upperBound >= length {
                        let body = bytes[end.upperBound...].prefix(length)
                        request.httpBody = Data(body)
                        return RecordedRequest(request: request, body: Data(body))
                    }
                }
                guard let next = await receive(connection) else { return nil }
                bytes.append(next)
            }
        }

        /// A request from its request line and header lines, or `nil` when the first line isn't a request line.
        private static func request(from lines: [String]) -> URLRequest? {
            let parts = lines[0].split(separator: " ")
            guard parts.count >= 2, let url = URL(string: "http://127.0.0.1\(parts[1])") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = String(parts[0])
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                request.setValue(value, forHTTPHeaderField: String(line[..<colon]))
            }
            return request
        }
    }
}

// MARK: - Tags

extension Tag {
    /// Tests that open real sockets on 127.0.0.1.
    @Tag package static var loopback: Self
}
