import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterOptionsTests {
    @Suite("Response cache")
    struct ResponseCache {
        @Test func `without a response cache, a request sends no cache headers and keeps the session id in the body`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            try await respond(stub)

            let request = try #require(stub.requests.first)
            let names = ["X-OpenRouter-Cache", "X-OpenRouter-Cache-TTL", "X-OpenRouter-Cache-Clear", "X-Session-Id"]
            #expect(names.compactMap { request.request.value(forHTTPHeaderField: $0) }.isEmpty)
            #expect(try body(request)["session_id"]?.stringValue?.isEmpty == false)
        }

        @Test(arguments: [
            (OpenRouterResponseCache(), 300),
            (OpenRouterResponseCache(timeToLive: .seconds(3_600)), 3_600),
            (OpenRouterResponseCache(timeToLive: .milliseconds(1_500)), 1),
            (OpenRouterResponseCache(timeToLive: .milliseconds(400)), 1),
            (OpenRouterResponseCache(timeToLive: .seconds(-10)), 1),
            (OpenRouterResponseCache(timeToLive: .seconds(86_400)), 86_400),
            (OpenRouterResponseCache(timeToLive: .seconds(100_000)), 86_400),
        ])
        func `a response cache turns the cache on for its time to live, in whole seconds from 1 second to 24 hours`(
            cache: OpenRouterResponseCache,
            seconds: Int
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            _ = try await LanguageModelSession(model: model(stub, responseCache: cache)).respond(to: "Hi")

            let request = try #require(stub.requests.first).request
            #expect(cache.timeToLive == .seconds(seconds))
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Cache") == "true")
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Cache-TTL") == String(seconds))
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Cache-Clear") == nil)
        }

        @Test func `a refreshing cache asks OpenRouter to replace the kept answer`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            var cache = OpenRouterResponseCache(timeToLive: .seconds(60))
            cache.refreshes = true

            _ = try await LanguageModelSession(model: model(stub, responseCache: cache)).respond(to: "Hi")

            let request = try #require(stub.requests.first).request
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Cache") == "true")
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Cache-TTL") == "60")
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Cache-Clear") == "true")
        }

        @Test func `with the cache on, the session id goes in a header, so new sessions that ask the same send the same body`()
            async throws
        {
            let stub = HTTPStub(events(text("Hi"), done()), events(text("Hi"), done()), events(text("Again"), done()))
            let cached = model(stub, responseCache: OpenRouterResponseCache())

            _ = try await LanguageModelSession(model: cached, instructions: "Be brief.").respond(to: "Hi")
            let second = LanguageModelSession(model: cached, instructions: "Be brief.")
            _ = try await second.respond(to: "Hi")
            _ = try await second.respond(to: "Again?")

            let requests = stub.requests
            try #require(requests.count == 3)
            #expect(requests[0].body == requests[1].body)
            #expect(try body(requests[0])["session_id"] == nil)
            let sessionIDs = requests.map { $0.request.value(forHTTPHeaderField: "X-Session-Id") }
            #expect(sessionIDs.allSatisfy { $0?.isEmpty == false })
            #expect(sessionIDs[0] != sessionIDs[1])
            #expect(sessionIDs[1] == sessionIDs[2])
        }
    }
}
