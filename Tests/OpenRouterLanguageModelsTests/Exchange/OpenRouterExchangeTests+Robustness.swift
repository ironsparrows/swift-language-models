import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Robustness")
    struct Robustness {
        @Test func `an empty reasoning list goes back on the next turn`() async throws {
            let stub = HTTPStub(events(chunk(["reasoning_details": []]), text("Hi"), done()), events(text("Again."), done()))
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Hi")
            _ = try await session.respond(to: "Again?")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["reasoning_details"] == [])
            #expect(assistant["reasoning"] == nil)
        }

        @Test func `a 402 for too many requests in flight is a rate limit`() async throws {
            let body = #"{"error":{"code":402,"message":"Too many in flight","metadata":{"limit_source":"openrouter_in_flight_budget"}}}"#
            let stub = HTTPStub(.json(body, status: 402, headers: ["Retry-After": "2"]))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            #expect(info.resetDate != nil)
        }
    }
}
