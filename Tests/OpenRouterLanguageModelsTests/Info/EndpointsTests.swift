import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels
@testable import OpenRouterLanguageModels

@Suite("Info: a model's endpoints")
struct EndpointsTests {
    @Test func `each endpoint decodes with its host, slug, limits, prices and health`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))

        let endpoints = try await fallback("anthropic/claude-haiku-5.5").endpoints(
            auth: .proxied(baseURL: stub.baseURL), session: stub.session)

        #expect(endpoints.map(\.tag) == ["google-vertex/global", "anthropic", "amazon-bedrock/us-east-1"])
        #expect(endpoints.map(\.name) == ["Google", "Anthropic", "Amazon Bedrock"])
        let google = try #require(endpoints.first)
        #expect(google.modelID == "anthropic/claude-haiku-5.5")
        #expect(google.serviceTier == nil)
        #expect(google.quantization == .unknown)
        #expect(google.contextSize == 1_000_000)
        #expect(google.maximumOutputTokens == 128_000)
        #expect(google.maximumPromptTokens == nil)
        #expect(google.pricing?.discount == 0)
        #expect(google.status == 0)
        #expect(google.uptimeLast5Minutes == 100)
        #expect(google.uptimeLast30Minutes == 100)
        #expect(google.uptimeLastDay == 100)
        #expect(google.supportedParameters.contains(.tools))
        #expect(google.supportedParameters.count == 10)
        #expect(!google.supportsImplicitCaching)
        #expect(endpoints.last?.uptimeLast5Minutes == nil)
    }

    @Test func `an endpoint's prices decode as decimals, with the long-prompt override`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))

        let pricing = try #require(
            try await fallback("anthropic/claude-haiku-5.5").endpoints(auth: .proxied(baseURL: stub.baseURL), session: stub.session).first?
                .pricing)

        #expect(pricing.prompt == Decimal(string: "0.0000001"))
        #expect(pricing.completion == Decimal(string: "0.0000005"))
        #expect(pricing.cacheRead == Decimal(string: "0.00000001"))
        #expect(pricing.cacheWrite == Decimal(string: "0.000000125"))
        #expect(pricing.cacheWriteOneHour == Decimal(string: "0.0000002"))
        #expect(pricing.webSearch == Decimal(string: "0.01"))
        #expect(pricing.request == nil)
        let override = try #require(pricing.overrides.first)
        #expect(override.condition == .init(promptTokensAbove: 100_000))
        #expect(pricing.prices(forPromptTokens: 200_000).prompt == Decimal(string: "0.0000005"))
        #expect(pricing.prices(forPromptTokens: 1_000).prompt == Decimal(string: "0.0000001"))
    }

    @Test func `without a key, no endpoint has latency or throughput`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))

        let endpoints = try await fallback("anthropic/claude-haiku-5.5").endpoints(
            auth: .proxied(baseURL: stub.baseURL), session: stub.session)

        #expect(endpoints.allSatisfy { $0.latencyLast30Minutes == nil && $0.throughputLast30Minutes == nil })
    }

    @Test func `with a key, latency decodes in milliseconds and throughput in tokens per second`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints-keyed.json"))

        let endpoints = try await fallback("anthropic/claude-haiku-5.5").endpoints(
            auth: .apiKey(baseURL: stub.baseURL) { "sk-or-test" }, session: stub.session)

        let latency = try #require(endpoints.first?.latencyLast30Minutes)
        #expect(latency.p50 == .milliseconds(512.5))
        #expect(latency.p99 == .milliseconds(2_875.25))
        let throughput = try #require(endpoints.first?.throughputLast30Minutes)
        #expect(throughput.p50 == 182.4)
        #expect(throughput.p90 == 98.6)
    }

    @Test func `a flex endpoint decodes its tier, precision, discount, status and time-of-day prices`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints-keyed.json"))

        let flex = try #require(
            try await fallback("anthropic/claude-haiku-5.5").endpoints(auth: .proxied(baseURL: stub.baseURL), session: stub.session).last)

        #expect(flex.tag == "tencent/fp8/flex")
        #expect(flex.serviceTier == .flex)
        #expect(flex.quantization == .fp8)
        #expect(flex.status == -2)
        #expect(flex.pricing?.discount == 0.5)
        #expect(flex.maximumPromptTokens == 120_000)
        #expect(flex.supportsImplicitCaching)
        let hours = try #require(flex.pricing?.overrides.map(\.condition.hours))
        #expect(hours == [.init(start: .zero, end: .seconds(16 * 3_600)), .init(start: .seconds(16 * 3_600), end: .zero)])
    }

    @Test func `the call is a GET of the model's endpoints path under the base URL`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))

        _ = try await fallback("anthropic/claude-haiku-5.5").endpoints(auth: .proxied(baseURL: stub.baseURL), session: stub.session)
        let request = try #require(stub.requests.first?.request)

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/models/anthropic/claude-haiku-5.5/endpoints")
    }

    @Test func `paths go under OpenRouter's API when no base URL is set`() {
        #expect(
            API.defaultBaseURL?.appending(path: "models/x/y/endpoints").absoluteString
                == "https://openrouter.ai/api/v1/models/x/y/endpoints")
    }

    @Test func `a base URL with a path keeps it`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))
        let proxy = stub.baseURL.appending(path: "openrouter/v1")

        _ = try await fallback("anthropic/claude-haiku-5.5").endpoints(auth: .proxied(baseURL: proxy), session: stub.session)

        #expect(stub.requests.first?.request.url?.path() == "/openrouter/v1/models/anthropic/claude-haiku-5.5/endpoints")
    }

    @Test func `a call without a key sends no Authorization, and names the package`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))

        _ = try await fallback("anthropic/claude-haiku-5.5").endpoints(auth: .proxied(baseURL: stub.baseURL), session: stub.session)

        #expect(header("Authorization", of: stub) == nil)
        #expect(header("User-Agent", of: stub) == UserAgent.current)
        #expect(header("Accept", of: stub) == "application/json")
    }

    @Test func `an empty key sends no Authorization`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))

        _ = try await fallback("anthropic/claude-haiku-5.5").endpoints(auth: .apiKey(baseURL: stub.baseURL) { "" }, session: stub.session)

        #expect(header("Authorization", of: stub) == nil)
    }

    @Test func `a call with a key sends it as a bearer token`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))

        _ = try await fallback("anthropic/claude-haiku-5.5").endpoints(
            auth: .apiKey(baseURL: stub.baseURL) { "sk-or-key" }, session: stub.session)

        #expect(header("Authorization", of: stub) == "Bearer sk-or-key")
    }

    @Test func `the language model's endpoints use its key, session and base URL, for its first model`() async throws {
        let stub = HTTPStub(try fixtureResponse("model-endpoints.json"))
        let languageModel = model(stub, id: "anthropic/claude-haiku-5.5")

        let endpoints = try await languageModel.endpoints()

        #expect(endpoints.count == 3)
        #expect(stub.requests.first?.request.url?.path() == "/models/anthropic/claude-haiku-5.5/endpoints")
        #expect(header("Authorization", of: stub) == "Bearer sk-or-test")
    }

    @Test func `an alias has no endpoints of its own`() async throws {
        let stub = HTTPStub(.json(#"{"data": {"id": "~anthropic/claude-haiku-latest", "name": "Latest", "endpoints": []}}"#))

        let endpoints = try await fallback("~anthropic/claude-haiku-latest").endpoints(
            auth: .proxied(baseURL: stub.baseURL), session: stub.session)

        #expect(endpoints.isEmpty)
        #expect(stub.requests.first?.request.url?.path() == "/models/~anthropic/claude-haiku-latest/endpoints")
    }

    @Test func `an endpoint with only its host and slug decodes, and unknown fields are ignored`() async throws {
        let body = #"""
            {"data": {"endpoints": [{"provider_name": "Vendor", "tag": "vendor/eu", "model_id": "vendor/model",
            "status": -10, "quantization": "fp3", "service_tier": "turbo", "new_field": {"nested": [1, 2]}}]}}
            """#
        let stub = HTTPStub(.json(body))

        let provider = try #require(try await connection(stub).endpoints(of: "vendor/model", for: .seconds(60)).first)

        #expect(
            provider
                == OpenRouterEndpoint(
                    name: "Vendor", tag: "vendor/eu", modelID: "vendor/model", serviceTier: "turbo", quantization: "fp3", status: -10))
        #expect(provider.pricing == nil)
        #expect(provider.supportedParameters.isEmpty)
    }
}
