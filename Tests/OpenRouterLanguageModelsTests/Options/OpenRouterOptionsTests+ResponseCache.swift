import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Synchronization
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterOptionsTests {
    @Suite("Response cache")
    struct ResponseCache {
        @Test func `without a response cache, a request sends no cache headers and keeps the session id in the body`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            try await respond(stub)

            let request = try #require(stub.requests.first)
            for header in ["X-OpenRouter-Cache", "X-OpenRouter-Cache-TTL", "X-OpenRouter-Cache-Clear", "X-Session-Id"] {
                #expect(request.request.value(forHTTPHeaderField: header) == nil)
            }
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

        @Test func `a hit repeats the answer's tool calls under their ids, so the session runs the tool again`() async throws {
            let call = toolCall(0, id: "call_1", name: "addOne", arguments: #"{"order":"A"}"#)
            let stub = HTTPStub(
                events(headers: ["X-OpenRouter-Cache-Status": "MISS"], call, done("tool_calls")),
                events(text("Added."), done()),
                events(headers: ["X-OpenRouter-Cache-Status": "HIT"], call, done("tool_calls")),
                events(text("Added."), done())
            )
            let counter = CounterTool()

            let first = try await LanguageModelSession(model: model(stub, responseCache: OpenRouterResponseCache()), tools: [counter])
                .respond(to: "Add one.")
            let repeated = try await LanguageModelSession(model: model(stub, responseCache: OpenRouterResponseCache()), tools: [counter])
                .respond(to: "Add one.")

            #expect(counter.count == 2)
            #expect(toolCallIDs(first.transcriptEntries) == ["call_1"])
            #expect(toolCallIDs(repeated.transcriptEntries) == ["call_1"])
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

        @Test(arguments: [
            (
                ["X-OpenRouter-Cache-Status": "HIT", "X-OpenRouter-Cache-Age": "12", "X-OpenRouter-Cache-Source-Id": "gen-abc123"],
                JSONValue?.some("HIT"), JSONValue?.some(12), JSONValue?.some("gen-abc123")
            ),
            (["X-OpenRouter-Cache-Status": "MISS", "X-OpenRouter-Cache-TTL": "300"], "MISS", nil, nil),
            (["X-OpenRouter-Cache-Status": "BYPASS"], "BYPASS", nil, nil),
            ([:], nil, nil, nil),
        ])
        func `the cache status, age and source id in the response's headers reach the answer's entry`(
            headers: [String: String],
            status: JSONValue?,
            age: JSONValue?,
            sourceID: JSONValue?
        ) async throws {
            let stub = HTTPStub(events(headers: headers, text("Hi"), done()))

            let response = try await LanguageModelSession(model: model(stub, responseCache: OpenRouterResponseCache())).respond(to: "Hi")

            let metadata = try lastResponse(of: response).metadata
            #expect(try metadataJSON(metadata, OpenRouterMetadataKey.responseCacheStatus) == status)
            #expect(try metadataJSON(metadata, OpenRouterMetadataKey.responseCacheAge) == age)
            #expect(try metadataJSON(metadata, OpenRouterMetadataKey.responseCacheSourceID) == sourceID)
            #expect(metadataString(metadata, LanguageModelMetadataKey.responseID) == "gen-1")
        }

        @Test func `a time to live outside OpenRouter's range is clamped to whole seconds from 1 second to 24 hours`() {
            #expect(OpenRouterResponseCache.timeToLive(clamping: .milliseconds(1_500)) == .seconds(1))
            #expect(OpenRouterResponseCache.timeToLive(clamping: .zero) == .seconds(1))
            #expect(OpenRouterResponseCache.timeToLive(clamping: .seconds(90_000)) == .seconds(86_400))
            #expect(OpenRouterResponseCache.timeToLive(clamping: .seconds(600)) == .seconds(600))
        }
    }
}

/// The ids of the tool calls in a transcript, in order.
private func toolCallIDs(_ entries: some Collection<Transcript.Entry>) -> [String] {
    entries.flatMap { entry -> [String] in
        guard case .toolCalls(let calls) = entry else { return [] }
        return calls.map(\.id)
    }
}

/// A tool that counts its calls, like one that writes data.
private final class CounterTool: Tool {
    let name = "addOne"
    let description = "Adds one to the order's count."
    private let calls = Mutex(0)

    @Generable
    struct Arguments {
        var order: String
    }

    var count: Int { calls.withLock { $0 } }

    func call(arguments: Arguments) async throws -> String {
        calls.withLock { $0 += 1 }
        return "Added one to \(arguments.order)."
    }
}
