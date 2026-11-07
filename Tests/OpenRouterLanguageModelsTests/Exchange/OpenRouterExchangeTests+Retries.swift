import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Retries")
    struct Retries {
        private static let retriedStatuses = [500, 501, 502, 503, 504, 524, 529, 599]

        @Test(arguments: retriedStatuses)
        func `a server failure is retried twice, until it succeeds`(status: Int) async throws {
            let rejection = failure(status)
            let stub = HTTPStub(rejection, rejection, events(text("Hi"), done()))

            #expect(try await respond(stub) == "Hi")
            #expect(stub.requests.count == 3)
        }

        @Test(arguments: [400, 408, 409, 429])
        func `a non-server failure isn't retried`(status: Int) async throws {
            let stub = HTTPStub(failure(status), events(text("Hi"), done()))

            await #expect(throws: (any Error).self) { try await respond(stub) }
            #expect(stub.requests.count == 1)
        }

        @Test(arguments: [URLError.Code.timedOut, .cannotConnectToHost, .networkConnectionLost])
        func `a failed connection is retried until it succeeds`(code: URLError.Code) async throws {
            let failure = StubResponse.failure(URLError(code))
            let stub = HTTPStub(failure, failure, events(text("Hi"), done()))

            #expect(try await respond(stub) == "Hi")
            #expect(stub.requests.count == 3)
        }

        @Test func `the configuration's retry limit caps the retries`() async throws {
            let rejection = failure(503)
            let stub = HTTPStub(rejection, rejection, events(text("Hi"), done()))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub, retryLimit: 1) }

            #expect(error.status == 503)
            #expect(stub.requests.count == 2)
        }

        @Test func `disabled retries send a failed request once`() async throws {
            let stub = HTTPStub(failure(503), events(text("Hi"), done()))
            var model = model(stub)
            model.configuration.retries = .disabled

            await #expect(throws: OpenRouterError.self) { try await LanguageModelSession(model: model).respond(to: "Hi") }

            #expect(stub.requests.count == 1)
        }

        @Test func `a model's default configuration retries twice, without an idle timeout`() {
            let configuration = OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey { "" }).configuration

            #expect(configuration.retries == .standard)
            #expect(configuration.idleTimeout == nil)
            #expect(configuration.images == .standard)
            #expect(configuration.infoCacheLifetime == .seconds(60))
        }

        @Test func `a gateway status in the stream isn't retried, since the answer already started`() async throws {
            let streamError: JSONValue = ["error": ["code": 503, "message": "Provider overloaded"]]
            let stub = HTTPStub(events(text("Hi"), streamError), events(text("Hello"), done()))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.status == 503)
            #expect(stub.requests.count == 1)
        }

        @Test func `a dropped stream isn't retried`() async throws {
            let stub = HTTPStub(
                unfinishedEvents(text("Hel")).droppingConnection(with: URLError(.networkConnectionLost)),
                events(text("Hello"), done())
            )

            let error = try await #require(throws: URLError.self) { try await respond(stub) }

            #expect(error.code == .networkConnectionLost)
            #expect(stub.requests.count == 1)
        }

        private func failure(_ status: Int) -> StubResponse {
            .json(#"{"error":{"code":\#(status),"message":"Unavailable"}}"#, status: status)
        }
    }
}
