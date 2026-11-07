import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Retries")
    struct Retries {
        @Test(arguments: [
            (500, true), (501, true), (502, true), (503, true), (504, true), (524, true), (529, true), (599, true),
            (400, false), (408, false), (409, false), (429, false),
        ])
        func `only a status from 500 up goes out again, up to the configuration's limit`(status: Int, isRetried: Bool) async {
            let stub = HTTPStub(failure(status), failure(status), events(text("Hi"), done()))

            await #expect(throws: (any Error).self) { try await respond(stub, retryLimit: 1) }

            #expect(stub.requests.count == (isRetried ? 2 : 1))
        }

        @Test func `a model's default configuration retries twice, without an idle timeout`() {
            let configuration = OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey { "" }).configuration

            #expect(configuration.retries == .standard)
            #expect(configuration.idleTimeout == nil)
            #expect(configuration.images == .standard)
            #expect(configuration.infoCacheLifetime == .seconds(60))
        }

        private func failure(_ status: Int) -> StubResponse {
            .json(#"{"error":{"code":\#(status),"message":"Unavailable"}}"#, status: status)
        }
    }
}
