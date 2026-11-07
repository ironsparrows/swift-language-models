import Foundation
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

@Suite("Info cache", .timeLimit(.minutes(1)))
struct InfoCacheTests {
    @Test func `a second call while the answer is fresh reads the cache`() async throws {
        let stub = HTTPStub(.json("first"), .json("second"))
        let connection = connection(stub).isolatingCache()

        let first = try await call(connection, stub)
        let second = try await call(connection, stub)

        #expect(first == "first")
        #expect(second == first)
        #expect(stub.requests.count == 1)
    }

    @Test func `an answer is kept apart for each key`() async throws {
        let stub = HTTPStub(.json("keyless"), .json("key a"), .json("key b"))
        func connection(_ headers: [String: String]) -> Connection { self.connection(stub, headers: headers) }

        let keyless = try await call(connection([:]), stub)
        let keyed = try await call(connection(["Authorization": "Bearer sk-or-a"]), stub)
        let otherKey = try await call(connection(["Authorization": "Bearer sk-or-b"]), stub)
        let keyedAgain = try await call(connection(["Authorization": "Bearer sk-or-a"]), stub)

        #expect(keyless == "keyless")
        #expect(keyed == "key a")
        #expect(otherKey == "key b")
        #expect(keyedAgain == keyed)
        #expect(stub.requests.count == 3)
    }

    @Test func `an answer is kept apart for each path`() async throws {
        let stub = HTTPStub(.json("haiku"), .json("router"))
        let connection = connection(stub).isolatingCache()

        let haiku = try await call(connection, stub, path: "model/anthropic/claude-haiku-5.5")
        let router = try await call(connection, stub, path: "model/openrouter/auto")

        #expect(haiku != router)
        #expect(stub.requests.count == 2)
    }

    @Test func `an expired answer is fetched again`() async throws {
        let stub = HTTPStub(.json("first"), .json("second"))
        let connection = connection(stub).isolatingCache()

        _ = try await call(connection, stub, lifetime: .zero)
        _ = try await call(connection, stub, lifetime: .zero)

        #expect(stub.requests.count == 2)
    }

    @Test func `a failure isn't kept`() async throws {
        // A 501 is retried twice, so the first call fails three times.
        let failure = StubResponse.json(#"{"error":{"message":"Not Implemented"}}"#, status: 501)
        let stub = HTTPStub(failure, failure, failure, .json("answer"))
        let connection = connection(stub).isolatingCache()

        await #expect(throws: RequestFailure<APIErrorBody>.self) { try await call(connection, stub) }
        let answer = try await call(connection, stub)

        #expect(answer == "answer")
        #expect(stub.requests.count == 4)
    }

    @Test func `an error the authentication throws passes through a cached call, before any request`() async {
        struct KeychainLocked: Error {}
        let stub = HTTPStub(.json("answer"))
        let authentication = Connection.Authentication(baseURL: stub.baseURL) { throw KeychainLocked() }
        let connection = Connection(
            session: stub.session, authentication: authentication, idleTimeout: nil, retries: .disabled, retrying: { _ in false })

        await #expect(throws: KeychainLocked.self) { try await call(connection, stub) }

        #expect(stub.requests.isEmpty)
    }

    @Test func `a connection that isolates its cache reads no other connection's answers, and keeps its own`() async throws {
        let stub = HTTPStub(.json("shared"), .json("isolated"))
        let shared = connection(stub)
        let isolated = shared.isolatingCache()

        _ = try await call(shared, stub)
        let answer = try await call(isolated, stub)
        let again = try await call(isolated, stub)

        #expect(answer == "isolated")
        #expect(again == answer)
        #expect(stub.requests.count == 2)
    }

    @Test func `an entry expires after its lifetime`() throws {
        let cache = InfoCache()
        let key = InfoCache.Key(url: try #require(URL(string: "https://example.test/model/a/b")), headers: [:])
        let now = ContinuousClock.now

        cache.store("answer", for: key, lifetime: .seconds(60), now: now)

        #expect(cache.value(for: key, as: String.self, now: now + .seconds(59)) == "answer")
        #expect(cache.value(for: key, as: String.self, now: now + .seconds(60)) == nil)
    }

    @Test func `the cache keeps a digest of the key, never the key`() throws {
        let url = try #require(URL(string: "https://example.test/model/a/b"))

        let key = InfoCache.Key(url: url, headers: ["Authorization": "Bearer sk-or-secret"])

        #expect(key.account?.contains("sk-or-secret") == false)
        #expect(key != InfoCache.Key(url: url, headers: ["Authorization": "Bearer sk-or-other"]))
        #expect(key == InfoCache.Key(url: url, headers: ["Authorization": "Bearer sk-or-secret"]))
        #expect(InfoCache.Key(url: url, headers: [:]).account == nil)
    }

    /// A connection to a stub that retries a server failure at once. It shares the cache of every connection, and the
    /// stub's own host keeps its answers apart from other tests'.
    private func connection(_ stub: HTTPStub, headers: [String: String] = [:]) -> Connection {
        Connection(
            session: stub.session, authentication: Connection.Authentication(baseURL: stub.baseURL) { headers }, idleTimeout: nil,
            retries: RequestRetries(limit: 2, initialDelay: .zero), retrying: { $0 >= 500 })
    }

    /// Reads a path under the stub's URL as text.
    private func call(
        _ connection: Connection, _ stub: HTTPStub, path: String = "model/anthropic/claude-haiku-5.5", lifetime: Duration = .seconds(60)
    ) async throws -> String {
        try await connection.cachedValue(
            at: path, under: stub.baseURL, for: lifetime, provider: "Test", decode: { String(decoding: $0, as: UTF8.self) },
            failure: { (failure: RequestFailure<APIErrorBody>) in failure })
    }
}
