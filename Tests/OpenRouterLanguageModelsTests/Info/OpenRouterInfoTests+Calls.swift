import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterInfoTests {
    @Suite("Calls")
    struct Calls {
        /// What a failed call surfaces as.
        enum Outcome: Sendable {
            case openRouterError(OpenRouterError.Code, status: Int?)
            case rateLimited
            case timeout

            func matches(_ error: (any Error)?) -> Bool {
                switch (self, error) {
                case (.openRouterError(let code, let status), let error as OpenRouterError):
                    return error.code == code && error.status == status
                case (.rateLimited, let error as LanguageModelError):
                    if case .rateLimited = error { return true }
                    return false
                case (.timeout, let error as LanguageModelError):
                    if case .timeout = error { return true }
                    return false
                default:
                    return false
                }
            }
        }

        @Test(arguments: [
            (
                401, #"{"error":{"message":"No cookie auth credentials found","code":401}}"#,
                Outcome.openRouterError(.authentication, status: 401)
            ),
            (404, #"{"error":{"message":"Not Found","code":404}}"#, .openRouterError(.notFound, status: 404)),
            (429, #"{"error":{"message":"Rate limit exceeded","code":429}}"#, .rateLimited),
            (500, "<html>Internal Server Error</html>", .openRouterError(.server, status: 500)),
            (524, #"{"error":{"message":"Timed out","code":524}}"#, .timeout),
        ])
        func `a failed response throws what a chat request throws for it`(status: Int, body: String, outcome: Outcome) async throws {
            let failure = StubResponse.json(body, status: status)
            let stub = HTTPStub(failure, failure, failure)

            let error = await #expect(throws: (any Error).self) {
                try await connection(stub).endpoints(of: "vendor/model", for: .seconds(60))
            }

            #expect(outcome.matches(error), "Got \(String(describing: error))")
        }

        @Test func `a rate limit carries its reset date from Retry-After`() async throws {
            let stub = HTTPStub(.json(#"{"error":{"message":"Slow down","code":429}}"#, status: 429, headers: ["Retry-After": "30"]))

            let error = await #expect(throws: LanguageModelError.self) {
                try await connection(stub).endpoints(of: "vendor/model", for: .seconds(60))
            }

            guard case .rateLimited(let context)? = error else {
                Issue.record("Expected a rate limit, got \(String(describing: error))")
                return
            }
            let wait = try #require(context.resetDate).timeIntervalSinceNow
            #expect((25...31).contains(wait))
        }

        @Test func `a third server failure throws`() async throws {
            let failure = StubResponse.json("{}", status: 503)
            let stub = HTTPStub(failure, failure, failure)

            let error = await #expect(throws: OpenRouterError.self) {
                try await connection(stub).endpoints(of: "vendor/model", for: .seconds(60))
            }

            #expect(error?.code == .providerUnavailable)
            #expect(stub.requests.count == 3)
        }

        @Test(arguments: ["not json", #"{"data": {"endpoints": [{"tag": "vendor"}]}}"#, #"{"error": "no data"}"#])
        func `a body that doesn't decode throws an invalid response error`(body: String) async throws {
            let stub = HTTPStub(.json(body))

            let error = await #expect(throws: OpenRouterError.self) {
                try await connection(stub).endpoints(of: "vendor/model", for: .seconds(60))
            }

            #expect(error?.code == .invalidResponse)
        }

        @Test func `the public calls share a cache`() async throws {
            let stub = HTTPStub(try fixtureResponse("model.json"), try fixtureResponse("model.json"))

            _ = try await fallback("anthropic/claude-haiku-5.5").currentDetails(
                auth: .proxied(baseURL: stub.baseURL), session: stub.session)
            _ = try await fallback("anthropic/claude-haiku-5.5").currentPricing(
                auth: .proxied(baseURL: stub.baseURL), session: stub.session)

            #expect(stub.requests.count == 1)
        }

        @Test func `a catalog model's second call for its endpoints reads the cache`() async throws {
            let endpoints = try fixtureResponse("model-endpoints.json")
            let stub = HTTPStub(endpoints, endpoints)
            let model = fallback("anthropic/claude-haiku-5.5")

            let first = try await model.endpoints(auth: .proxied(baseURL: stub.baseURL), session: stub.session)
            let second = try await model.endpoints(auth: .proxied(baseURL: stub.baseURL), session: stub.session)

            #expect(first == second)
            #expect(stub.requests.count == 1)
        }

        @Test func `a language model's second call for its endpoints reads the cache`() async throws {
            let endpoints = try fixtureResponse("model-endpoints.json")
            let stub = HTTPStub(endpoints, endpoints)
            let languageModel = model(stub, efforts: [Efforts.Unsupported]())

            let first = try await languageModel.endpoints()
            let second = try await languageModel.endpoints()

            #expect(first == second)
            #expect(stub.requests.count == 1)
        }

        @Test func `a catalog model's calls keep answers only as long as their configuration says`() async throws {
            let (endpoints, details) = (try fixtureResponse("model-endpoints.json"), try fixtureResponse("model.json"))
            let stub = HTTPStub(endpoints, endpoints, details, details)
            let auth = OpenRouterAuthentication.proxied(baseURL: stub.baseURL)
            let configuration = OpenRouterConfiguration(infoCacheLifetime: .zero)
            let model = fallback("anthropic/claude-haiku-5.5")

            for _ in 1...2 {
                _ = try await model.endpoints(auth: auth, session: stub.session, configuration: configuration)
            }
            for _ in 1...2 {
                _ = try await model.currentDetails(auth: auth, session: stub.session, configuration: configuration)
            }

            #expect(stub.requests.count == 4)
        }

        @Test func `a language model's calls keep answers only as long as its configuration says`() async throws {
            let (endpoints, details) = (try fixtureResponse("model-endpoints.json"), try fixtureResponse("model.json"))
            let stub = HTTPStub(endpoints, endpoints, details, details)
            let languageModel = model(
                stub, efforts: [Efforts.Unsupported](), configuration: OpenRouterConfiguration(infoCacheLifetime: .zero))

            for _ in 1...2 {
                _ = try await languageModel.endpoints()
            }
            for _ in 1...2 {
                _ = try await languageModel.currentDetails()
            }

            #expect(stub.requests.count == 4)
        }

        @Test func `a catalog model's call retries a server failure as its configuration says`() async throws {
            let stub = HTTPStub(.json("{}", status: 503), try fixtureResponse("model-endpoints.json"))
            let configuration = OpenRouterConfiguration(retries: .immediate())

            let endpoints = try await fallback("vendor/model")
                .endpoints(auth: .proxied(baseURL: stub.baseURL), session: stub.session, configuration: configuration)

            #expect(endpoints.count == 3)
            #expect(stub.requests.count == 2)
        }

        @Test func `a catalog model's call isn't retried when its configuration says so`() async throws {
            let failure = StubResponse.json("{}", status: 503)
            let stub = HTTPStub(failure, failure)
            let configuration = OpenRouterConfiguration(retries: .disabled)

            await #expect(throws: OpenRouterError.self) {
                try await fallback("vendor/model")
                    .endpoints(auth: .proxied(baseURL: stub.baseURL), session: stub.session, configuration: configuration)
            }

            #expect(stub.requests.count == 1)
        }
    }
}
