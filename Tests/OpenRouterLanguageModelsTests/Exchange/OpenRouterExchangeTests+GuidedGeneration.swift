import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Guided generation")
    struct GuidedGeneration {
        @Test(arguments: [OpenRouterModelID("anthropic/claude-haiku-5.5"), "~anthropic/claude-haiku-latest"])
        func `an Anthropic model gets the portable schema`(id: OpenRouterModelID) async throws {
            let stub = HTTPStub(events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub, id: id))

            _ = try await session.respond(to: "A recipe.", generating: Recipe.self)

            let schema = try body(stub)["response_format"]?["json_schema"]?["schema"]
            #expect(schema?["properties"]?["servings"]?["maximum"] == nil)
        }

        @Test func `another model's schema keeps its constraints`() async throws {
            let stub = HTTPStub(events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub, id: "openai/gpt-5"))

            _ = try await session.respond(to: "A recipe.", generating: Recipe.self)

            let schema = try body(stub)["response_format"]?["json_schema"]?["schema"]
            #expect(schema?["properties"]?["servings"]?["maximum"] == 12)
        }

        @Test(arguments: [Set<OpenRouterParameter>([.maxTokens]), [.responseFormat]])
        func `a model without structured outputs is refused before any request, even with JSON mode`(
            parameters: Set<OpenRouterParameter>
        ) async throws {
            let stub = HTTPStub(events(text(#"{"name":"Soup","servings":2}"#), done()))
            let session = LanguageModelSession(model: model(stub, parameters: parameters))

            let error = try await #require(throws: LanguageModelError.self) {
                try await session.respond(to: "A dinner idea.", generating: Meal.self)
            }

            guard case .unsupportedCapability = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(stub.requests.isEmpty)
        }
    }
}

/// A recipe whose servings have a range, which the portable schema moves into the description.
@Generable
private struct Recipe {
    @Guide(.range(1...12))
    var servings: Int

    /// An answer that matches the schema.
    static let answer = #"{"servings":2}"#
}

@Generable
private struct Meal {
    var name: String
    var servings: Int
    var notes: String?
}
