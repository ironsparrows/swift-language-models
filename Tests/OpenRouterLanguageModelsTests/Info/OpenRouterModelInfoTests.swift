import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

@Suite("Info: calls")
struct OpenRouterModelInfoTests {
    /// What a failed call surfaces as.
    enum Outcome: Sendable {
        case openRouterError(OpenRouterError.Code, status: Int?)
        case urlError(URLError.Code)
        case rateLimited
        case timeout
        case cancellation

        func matches(_ error: (any Error)?) -> Bool {
            switch (self, error) {
            case (.openRouterError(let code, let status), let error as OpenRouterError):
                return error.code == code && error.status == status
            case (.urlError(let code), let error as URLError):
                return error.code == code
            case (.rateLimited, let error as LanguageModelError):
                if case .rateLimited = error { return true }
                return false
            case (.timeout, let error as LanguageModelError):
                if case .timeout = error { return true }
                return false
            case (.cancellation, let error):
                return error is CancellationError
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
        // A status from 500 up is retried twice, so it fails three times.
        let failure = StubResponse.json(body, status: status)
        let stub = HTTPStub(failure, failure, failure)

        let error = await #expect(throws: (any Error).self) { try await connection(stub).endpoints(of: "vendor/model", for: .seconds(60)) }

        #expect(outcome.matches(error), "Got \(String(describing: error))")
        #expect(stub.requests.count == (status >= 500 ? 3 : 1))
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

    @Test(arguments: [500, 501, 502, 503, 504, 524, 529, 599])
    func `a server failure is retried twice`(status: Int) async throws {
        let failure = StubResponse.json("{}", status: status)
        let stub = HTTPStub(failure, failure, try fixtureResponse("model-endpoints.json"))

        let providers = try await connection(stub).endpoints(of: "anthropic/claude-haiku-5.5", for: .seconds(60))

        #expect(providers.count == 3)
        #expect(stub.requests.count == 3)
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

    @Test(arguments: [URLError.Code.notConnectedToInternet, .cannotFindHost, .timedOut])
    func `a failed connection is retried`(code: URLError.Code) async throws {
        let stub = HTTPStub(.failure(URLError(code)), try fixtureResponse("model-endpoints.json"))

        let providers = try await connection(stub).endpoints(of: "vendor/model", for: .seconds(60))

        #expect(providers.count == 3)
        #expect(stub.requests.count == 2)
    }

    @Test func `a cancelled request isn't retried`() async throws {
        let stub = HTTPStub(.failure(URLError(.cancelled)), try fixtureResponse("model-endpoints.json"))

        let error = await #expect(throws: (any Error).self) {
            try await connection(stub).endpoints(of: "vendor/model", for: .seconds(60))
        }

        #expect(Outcome.cancellation.matches(error), "Got \(String(describing: error))")
        #expect(stub.requests.count == 1)
    }

    @Test func `the public calls share a cache`() async throws {
        let stub = HTTPStub(try fixtureResponse("model.json"), try fixtureResponse("model.json"))

        _ = try await fallback("anthropic/claude-haiku-5.5").currentDetails(auth: .proxied(baseURL: stub.baseURL), session: stub.session)
        _ = try await fallback("anthropic/claude-haiku-5.5").currentPricing(auth: .proxied(baseURL: stub.baseURL), session: stub.session)

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
        let languageModel = model(stub, efforts: [Efforts.Unsupported](), configuration: OpenRouterConfiguration(infoCacheLifetime: .zero))

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

    @Test func `an error that the language model's key closure throws passes through, before any request`() async throws {
        struct KeychainLocked: Error {}
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))
        let languageModel = model(stub, efforts: [Efforts.Unsupported](), auth: .apiKey { throw KeychainLocked() })

        await #expect(throws: KeychainLocked.self) { try await languageModel.endpoints() }
        #expect(stub.requests.isEmpty)
    }
}
