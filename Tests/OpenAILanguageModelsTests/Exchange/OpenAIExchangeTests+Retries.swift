import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

/// How OpenAI's requests retry, with the stubs' models waiting for nothing between retries.

extension OpenAIExchangeTests {
    @Suite("Retries")
    struct Retries {
        @Test(arguments: [(408, true), (409, true), (429, true), (500, true), (600, true), (400, false)])
        func `a status goes out again only if it may clear on another try, up to the configuration's limit`(
            status: Int, isRetried: Bool
        ) async {
            let stub = HTTPStub(failure(status), failure(status), answer())
            var limited = reasoningModel(stub)
            limited.configuration.retries.limit = 1

            await #expect(throws: (any Error).self) { try await LanguageModelSession(model: limited).respond(to: "Hi") }

            #expect(stub.requests.count == (isRetried ? 2 : 1))
        }

        @Test func `a rate limit that asks to wait more than 2 minutes fails at once, with the wait`() async throws {
            let stub = HTTPStub(failure(429, headers: ["Retry-After": "300"]), answer())

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .rateLimited(let context) = error, let reset = context.resetDate else {
                Issue.record("Threw \(error)")
                return
            }
            #expect(reset.timeIntervalSinceNow > 290)
        }

        @Test func `a wait past the configuration's longest server wait fails at once, with the wait`() async throws {
            let stub = HTTPStub(failure(503, headers: ["Retry-After": "10"]), answer())
            var model = reasoningModel(stub)
            model.configuration.retries.longestServerWait = .seconds(5)

            let error = try await #require(throws: OpenAIError.self) { try await LanguageModelSession(model: model).respond(to: "Hi") }

            #expect(error.retryAfter == .seconds(10))
        }

        @Test func `a model's default configuration retries twice and waits up to 10 minutes for data`() {
            let configuration = OpenAILanguageModel(.gpt6Luna, auth: .apiKey { "" }).configuration

            #expect(configuration.retries == .standard)
            #expect(configuration.retries.limit == 2)
            #expect(configuration.idleTimeout == .seconds(600))
            #expect(configuration.images == .standard)
        }

        private func respond(_ stub: HTTPStub) async throws -> String {
            try await LanguageModelSession(model: reasoningModel(stub)).respond(to: "Hi").content
        }

        private func answer() -> StubResponse {
            responseStream([created()], [textDelta("Hi."), completed()])
        }

        private func failure(_ status: Int, headers: [String: String] = [:]) -> StubResponse {
            .json(#"{"error":{"message":"Failed.","type":"server_error"}}"#, status: status, headers: headers)
        }
    }
}
