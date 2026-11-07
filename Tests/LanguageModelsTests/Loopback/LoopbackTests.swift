import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

/// What only a real socket shows, on the plain model. A stub answers inside `URLSession`.
@Suite("Loopback", .tags(.loopback), .timeLimit(.minutes(1)))
struct LoopbackTests {
    private static let session = URLSession(configuration: .ephemeral)

    private static let answer = """
        data: {"choices":[{"delta":{"content":"Héllo, "}}]}

        data: {"choices":[{"delta":{"content":"wörld"},"finish_reason":"stop"}]}

        data: [DONE]


        """

    @Test func `an answer written a few bytes at a time arrives whole`() async throws {
        let server = try await LoopbackServer(.eventStream(Self.answer, writing: 5))

        let response = try await LanguageModelSession(model: model(server)).respond(to: "Hello")

        #expect(response.content == "Héllo, wörld")
        #expect(server.requests.first?.request.url?.path == "/chat/completions")
    }

    @Test func `a 503 and then a 200 on a real connection is retried once`() async throws {
        let server = try await LoopbackServer(LoopbackReply(status: 503), .eventStream(Self.answer))

        let response = try await LanguageModelSession(model: model(server, retries: 2)).respond(to: "Hello")

        #expect(response.content == "Héllo, wörld")
        #expect(server.requests.count == 2)
        #expect(server.requests.first?.body == server.requests.last?.body)
    }

    @Test func `a redirect to another host isn't followed and carries no credentials`() async throws {
        // The same server under another name, so only the URL host differs, and following it would reach this server
        // again.
        let server = try await LoopbackServer { url in
            let target = "http://localhost:\(url.port ?? 0)/chat/completions"
            return [LoopbackReply(status: 307, headers: ["Location": target]), .eventStream(Self.answer)]
        }

        await #expect(throws: RequestFailure<APIErrorBody>.self) {
            _ = try await LanguageModelSession(model: model(server, key: "sk-secret")).respond(to: "Hello")
        }

        #expect(server.requests.count == 1)
        #expect(server.requests.first?.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-secret")
    }

    @Test func `cancelling mid-stream closes the connection`() async throws {
        let chunks = (1...6).map { #"data: {"choices":[{"delta":{"content":"\#($0) "}}]}"# + "\n\n" }
        let server = try await LoopbackServer(.eventStream(chunks.joined(), writing: chunks[0].utf8.count, ending: .staysOpen))
        let session = LanguageModelSession(model: model(server))
        let (snapshots, arrived) = AsyncStream.makeStream(of: Void.self)

        let answer = Task {
            for try await _ in session.streamResponse(to: "Hello") { arrived.yield() }
        }
        var snapshot = snapshots.makeAsyncIterator()
        #expect(await snapshot.next() != nil)
        answer.cancel()

        var closed = server.closedConnections.makeAsyncIterator()
        #expect(await closed.next() != nil)
    }

    @Test func `a stream that goes quiet fails after the idle timeout`() async throws {
        let start = #"data: {"choices":[{"delta":{"content":"Hi"}}]}"# + "\n\n"
        let server = try await LoopbackServer(.eventStream(start, ending: .staysOpen))
        let clock = ContinuousClock()
        let started = clock.now

        let error = await #expect(throws: LanguageModelError.self) {
            _ = try await LanguageModelSession(model: model(server, idleTimeout: .milliseconds(200))).respond(to: "Hello")
        }

        guard case .timeout? = error else {
            Issue.record("The answer ended with \(String(describing: error))")
            return
        }
        #expect(clock.now - started >= .milliseconds(200))
        #expect(clock.now - started < .seconds(5))
        #expect(server.requests.count == 1)
    }

    /// The plain model, sending to a server.
    private func model(
        _ server: LoopbackServer,
        retries: Int = 0,
        idleTimeout: Duration? = nil,
        key: String = "sk-test"
    ) -> ChatCompletions.Model<ChatCompletions.PlainExchange> {
        var model = ChatCompletions.Model(name: "vendor/model", url: server.baseURL)
        model.connection = Connection(
            session: Self.session,
            authentication: Connection.Authentication(baseURL: nil) { ["Authorization": "Bearer \(key)"] }, idleTimeout: idleTimeout,
            retries: RequestRetries(limit: retries, initialDelay: .zero), retrying: .serverErrors)
        return model
    }
}
