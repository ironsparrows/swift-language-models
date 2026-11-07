import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterInfoTests {
    @Suite("A model's current details")
    struct CurrentDetails {
        @Test func `a model's details decode with its prices, limits and parameters`() async throws {
            let stub = HTTPStub(try fixtureResponse("model.json"))

            let details = try await fallback("anthropic/claude-haiku-5.5").currentDetails(
                auth: .proxied(baseURL: stub.baseURL), session: stub.session)

            #expect(details.id == "anthropic/claude-haiku-5.5")
            #expect(details.displayName == "Anthropic: Claude Haiku 5.5")
            #expect(details.aliasTarget == nil)
            #expect(details.contextSize == 1_000_000)
            #expect(details.maximumOutputTokens == 128_000)
            #expect(details.isModerated)
            #expect(details.expirationDate == nil)
            #expect(details.supportedParameters.count == 11)
            #expect(details.supportedParameters.isSuperset(of: [.tools, .structuredOutputs, .reasoningEffort]))
            let pricing = try #require(details.pricing)
            #expect(pricing.prompt == Decimal(string: "0.0000001"))
            #expect(pricing.completion == Decimal(string: "0.0000005"))
            #expect(pricing.overrides.map(\.condition.promptTokensAbove) == [100_000])
        }

        @Test func `the call goes to the model's path`() async throws {
            let stub = HTTPStub(try fixtureResponse("model.json"))

            _ = try await fallback("anthropic/claude-haiku-5.5").currentDetails(
                auth: .proxied(baseURL: stub.baseURL), session: stub.session)

            #expect(stub.requests.first?.request.url?.path() == "/model/anthropic/claude-haiku-5.5")
            #expect(header("Authorization", of: stub) == nil)
        }

        @Test func `current pricing is the details' prices`() async throws {
            let stub = HTTPStub(try fixtureResponse("model.json"))

            let pricing = try await fallback("anthropic/claude-haiku-5.5").currentPricing(
                auth: .proxied(baseURL: stub.baseURL), session: stub.session)

            #expect(pricing?.webSearch == Decimal(string: "0.01"))
            #expect(pricing?.cacheWriteOneHour == Decimal(string: "0.0000002"))
        }

        @Test func `a router, whose price depends on the request, has no pricing`() async throws {
            let stub = HTTPStub(try fixtureResponse("model-router.json"))

            let details = try await fallback("openrouter/auto").currentDetails(auth: .proxied(baseURL: stub.baseURL), session: stub.session)

            #expect(details.pricing == nil)
            #expect(details.maximumOutputTokens == nil)
        }

        @Test func `an alias names the model it points to`() async throws {
            let stub = HTTPStub(try fixtureResponse("model-alias.json"))

            let details = try await fallback("~anthropic/claude-haiku-latest").currentDetails(
                auth: .proxied(baseURL: stub.baseURL), session: stub.session)

            #expect(details.aliasTarget == "anthropic/claude-haiku-5.5")
            #expect(stub.requests.first?.request.url?.path() == "/model/~anthropic/claude-haiku-latest")
        }

        @Test func `an expiration date is midnight UTC of its day`() async throws {
            let stub = HTTPStub(try fixtureResponse("model-expiring.json"))

            let details = try await fallback("poolside/laguna-xs-2.1").currentDetails(
                auth: .proxied(baseURL: stub.baseURL), session: stub.session)

            #expect(details.expirationDate == (try Date("2026-10-31T00:00:00Z", strategy: .iso8601)))
        }

        @Test(arguments: [
            ("2026-11-02T02:00:00Z", "0.0000003"),
            ("2026-11-02T05:00:00Z", "0.00000015"),
            ("2026-11-02T23:30:00Z", "0.00000015"),
            ("2026-10-31T02:00:00Z", "0.00000015"),
        ])
        func `prices by weekday and hour apply at their times`(time: String, prompt: String) async throws {
            let stub = HTTPStub(try fixtureResponse("model-time-pricing.json"))

            let pricing = try #require(
                try await fallback("deepseek/deepseek-v4.1-flash-1017").currentPricing(
                    auth: .proxied(baseURL: stub.baseURL), session: stub.session))

            #expect(pricing.overrides.count == 6)
            #expect(pricing.overrides.first?.condition.weekdays == [.saturday, .sunday])
            #expect(pricing.prices(forPromptTokens: 1_000, at: try Date(time, strategy: .iso8601)).prompt == Decimal(string: prompt))
        }

        @Test func `the language model's details use its key, session and base URL`() async throws {
            let stub = HTTPStub(try fixtureResponse("model.json"), try fixtureResponse("model.json"))
            let languageModel = model(stub, id: "anthropic/claude-haiku-5.5")

            let details = try await languageModel.currentDetails()
            let pricing = try await languageModel.currentPricing()

            #expect(details.id == "anthropic/claude-haiku-5.5")
            #expect(pricing == details.pricing)
            #expect(header("Authorization", of: stub) == "Bearer sk-or-test")
            #expect(stub.requests.count == 1, "The second call reads the cache")
        }

        @Test func `a model OpenRouter doesn't list throws a not found error with OpenRouter's message`() async throws {
            let stub = HTTPStub(.json(#"{"error":{"message":"Model not found: vendor/missing","code":404}}"#, status: 404))

            let error = await #expect(throws: OpenRouterError.self) {
                try await fallback("vendor/missing").currentDetails(auth: .proxied(baseURL: stub.baseURL), session: stub.session)
            }

            #expect(error?.code == .notFound)
            #expect(error?.status == 404)
            #expect(error?.message == "Model not found: vendor/missing")
        }
    }
}
