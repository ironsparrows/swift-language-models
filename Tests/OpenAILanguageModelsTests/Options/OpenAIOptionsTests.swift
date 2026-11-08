import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

/// What OpenAI's options send.
@Suite("OpenAI's options", .timeLimit(.minutes(1)))
struct OpenAIOptionsTests {
    @Test func `a verbosity goes as set to every model`() async throws {
        let options = OpenAIOptions(verbosity: .low)
        let reasoning = try await sentBody { reasoningModel($0, options: options) }
        let plain = try await sentBody { plainModel($0, options: options) }

        #expect(reasoning["text"] == ["verbosity": "low"])
        #expect(plain["text"] == ["verbosity": "low"])
    }

    @Test(
        arguments: [(OpenAIOptions.Storage.automatic, nil), (.stored, true), (.notStored, false)] as [(OpenAIOptions.Storage, Bool?)])
    func `the storage option sends store only when it isn't OpenAI's default`(storage: OpenAIOptions.Storage, store: Bool?) async throws {
        let body = try await sentBody { reasoningModel($0, options: OpenAIOptions(storage: storage)) }

        #expect(body["store"] == store.map(JSONValue.bool))
    }

    @Test func `a named cache key goes as the prompt cache key`() async throws {
        let body = try await sentBody { reasoningModel($0, options: OpenAIOptions(cacheKey: .named("coach"))) }

        #expect(body["prompt_cache_key"] == "coach")
    }

    @Test func `a session cache key is the session's first prompt id on every request`() async throws {
        let stub = HTTPStub(
            responseStream([created()], [textDelta("Hi."), completed()]), responseStream([created()], [textDelta("Hi."), completed()]))
        let session = LanguageModelSession(model: reasoningModel(stub, options: OpenAIOptions(cacheKey: .session)))

        _ = try await session.respond(to: "Hello")
        _ = try await session.respond(to: "Again")

        let first = try body(stub, 0)["prompt_cache_key"]
        #expect(first?.stringValue?.isEmpty == false)
        #expect(try body(stub, 1)["prompt_cache_key"] == first)
    }
}
