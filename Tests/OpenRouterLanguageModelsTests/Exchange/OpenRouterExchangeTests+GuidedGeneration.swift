import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Guided generation")
    struct GuidedGeneration {
        @Test func `a model with structured outputs gets a strict schema`() async throws {
            let stub = HTTPStub(events(text(#"{"name":"So"#), text(#"up","servings":2}"#), done()))
            let session = LanguageModelSession(model: model(stub))

            let meal = try await session.respond(to: "A dinner idea.", generating: Meal.self).content

            #expect(meal.name == "Soup")
            #expect(meal.servings == 2)
            let format = try body(stub)["response_format"]
            #expect(format?["type"] == "json_schema")
            #expect(format?["json_schema"]?["name"] == "Meal")
            #expect(format?["json_schema"]?["strict"] == true)
            #expect(format?["json_schema"]?["schema"]?["required"] == ["name", "servings", "notes"])
        }

        @Test(arguments: [OpenRouterModelID("anthropic/claude-haiku-5.5"), "~anthropic/claude-haiku-latest"])
        func `an Anthropic model gets the portable schema, with its constraints in descriptions`(id: OpenRouterModelID) async throws {
            let stub = HTTPStub(events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub, id: id))

            _ = try await session.respond(to: "A recipe.", generating: Recipe.self)

            expectPortable(try #require(try body(stub)["response_format"]?["json_schema"]?["schema"]))
        }

        @Test func `another model's schema keeps its constraints`() async throws {
            let stub = HTTPStub(events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub, id: "openai/gpt-5"))

            _ = try await session.respond(to: "A recipe.", generating: Recipe.self)

            expectFull(try #require(try body(stub)["response_format"]?["json_schema"]?["schema"]))
        }

        @Test(arguments: [
            (
                "Seed",
                "Invalid decoding guidance syntax: Keyword 'maxItems' is not supported for type 'array' at path '$.properties.steps'"
            ),
            (
                "Cohere",
                "invalid request: response_format validation: invalid 'json_schema' provided: error at 'properties.steps': "
                    + "received non-supported constraint for type: 'array'. constraint: 'minItems'"
            ),
            ("Anthropic", "output_format.schema: For 'integer' type, properties maximum, minimum are not supported"),
            ("OpenAI", "Invalid schema for response_format 'Recipe': In context=('properties', 'name'), 'pattern' is not permitted."),
        ])
        func `a host that rejects a schema constraint gets the portable schema once`(provider: String, message: String) async throws {
            let stub = HTTPStub(rejection(message, by: provider), events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub))

            let recipe = try await session.respond(to: "A recipe.", generating: Recipe.self).content

            #expect(recipe.servings == 2)
            #expect(stub.requests.count == 2)
            expectFull(try #require(try body(stub, 0)["response_format"]?["json_schema"]?["schema"]))
            expectPortable(try #require(try body(stub, 1)["response_format"]?["json_schema"]?["schema"]))
            #expect(withoutResponseFormat(try body(stub, 0)) == withoutResponseFormat(try body(stub, 1)))
        }

        @Test func `a portable schema that's rejected too isn't sent again`() async throws {
            let message = "Keyword 'maxItems' is not supported for type 'array'"
            let stub = HTTPStub(rejection(message), rejection(message), events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub))

            let error = try await #require(throws: OpenRouterError.self) {
                try await session.respond(to: "A recipe.", generating: Recipe.self)
            }

            #expect(error.status == 400)
            #expect(error.message == message)
            #expect(stub.requests.count == 2)
        }

        @Test(arguments: [
            (400, "swift-language-models/no-such-model is not a valid model ID"),
            (400, "max_tokens: the maximum for this model is 4096"),
            (400, "json_schema response format is not supported by this provider"),
            (400, "Parameter 'maximum_tokens' is not supported"),
            (422, "Keyword 'maxItems' is not supported for type 'array'"),
            (501, "Keyword 'maxItems' is not supported for type 'array'"),
        ])
        func `a failure that doesn't reject a schema constraint isn't sent again`(status: Int, message: String) async throws {
            // A 501 is retried twice as a server failure, but never with the portable schema.
            let failure = rejection(message, status: status)
            let stub = HTTPStub(failure, failure, failure, events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub))

            let error = try await #require(throws: OpenRouterError.self) {
                try await session.respond(to: "A recipe.", generating: Recipe.self)
            }

            #expect(error.status == status)
            #expect(stub.requests.count == (status >= 500 ? 3 : 1))
        }

        @Test func `a request that already sends the portable schema isn't sent again`() async throws {
            let stub = HTTPStub(rejection("Keyword 'maxItems' is not supported"), events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub, id: "anthropic/claude-haiku-5.5"))

            await #expect(throws: OpenRouterError.self) {
                try await session.respond(to: "A recipe.", generating: Recipe.self)
            }

            #expect(stub.requests.count == 1)
        }

        @Test func `a streamed answer becomes the generated value`() async throws {
            let stub = HTTPStub(events(text(#"{"name":"So"#), text(#"up","servings":"#), text(#"2,"notes":null}"#), done()))
            let session = LanguageModelSession(model: model(stub, parameters: [.structuredOutputs]))

            var snapshots: [Meal.PartiallyGenerated] = []
            for try await snapshot in session.streamResponse(to: "A dinner idea.", generating: Meal.self) {
                snapshots.append(snapshot.content)
            }

            let meal = try #require(snapshots.last)
            #expect(meal.name == "Soup")
            #expect(meal.servings == 2)
            #expect(meal.notes == nil)
            // Every snapshot's name is the start of the final one.
            #expect(snapshots.allSatisfy { "Soup".hasPrefix($0.name ?? "") })
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

        @Test func `a schema with a guide JSON can't hold throws unsupported generation guide before any request`() async throws {
            let stub = HTTPStub(events(text(#"{"value":1}"#), done()))
            let session = LanguageModelSession(model: model(stub, parameters: [.structuredOutputs]))

            let error = await #expect(throws: LanguageModelError.self) {
                try await session.respond(to: "A number.", generating: Unbounded.self)
            }

            guard case .unsupportedGenerationGuide? = error else {
                Issue.record("Expected an unsupported generation guide, got \(String(describing: error))")
                return
            }
            #expect(stub.requests.isEmpty)
        }

        @Test func `JSON that doesn't match the schema throws the parsing error`() async throws {
            let stub = HTTPStub(events(text(#"{"name":3}"#), done()))
            let session = LanguageModelSession(model: model(stub, parameters: [.structuredOutputs]))

            await #expect(throws: GeneratedContent.ParsingError.self) {
                try await session.respond(to: "A dinner idea.", generating: Meal.self)
            }
        }

        @Test func `a guided answer cut off at its token limit throws the parsing error`() async throws {
            let stub = HTTPStub(events(text(#"{"name":"Soup","servings":4,"notes":"Ser"#), done("length")))
            let session = LanguageModelSession(model: model(stub, parameters: [.structuredOutputs]))

            let error = await #expect(throws: GeneratedContent.ParsingError.self) {
                try await session.respond(to: "A dinner idea.", generating: Meal.self)
            }

            #expect(error?.debugDescription == "The answer reached its token limit before it was complete.")
        }

        @Test(arguments: [OpenRouterModelID("anthropic/claude-haiku-5.5"), "openai/gpt-5"])
        func `an answer that breaks a guide throws the parsing error, whichever schema the model got`(id: OpenRouterModelID) async throws {
            let answer = #"{"name":"Soup","servings":0,"steps":["Boil."],"ingredients":[{"grams":200},{"grams":10},{"grams":5}]}"#
            let stub = HTTPStub(events(text(answer), done()))
            let session = LanguageModelSession(model: model(stub, id: id))

            let error = await #expect(throws: GeneratedContent.ParsingError.self) {
                try await session.respond(to: "A recipe.", generating: Recipe.self)
            }

            #expect(error?.debugDescription == "The answer breaks its schema's guides: servings is 0, below the minimum of 1.")
        }

        @Test func `text before a round of tool calls isn't checked, and the round that follows is`() async throws {
            let stub = HTTPStub(
                events(
                    text(#"{"name":"Soup","servings":0,"steps":[],"ingredients":[]}"#),
                    toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    done("tool_calls")),
                events(text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            let recipe = try await session.respond(to: "A recipe.", generating: Recipe.self).content

            #expect(recipe.servings == 2)
            #expect(stub.requests.count == 2)
        }

        @Test func `only the text after a reasoning block is checked`() async throws {
            let stub = HTTPStub(events(text(#"<think>{"servings":0}</think>"#), text(Recipe.answer), done()))
            let session = LanguageModelSession(model: model(stub))

            let recipe = try await session.respond(to: "A recipe.", generating: Recipe.self).content

            #expect(recipe.servings == 2)
        }

        /// A host's failure as OpenRouter passes it on, with the host's own message in the metadata.
        private func rejection(_ message: String, by provider: String = "Seed", status: Int = 400) -> StubResponse {
            let metadata: JSONValue = ["raw": .string(message), "provider_name": .string(provider)]
            let error: JSONValue = ["error": ["code": .integer(status), "message": "Provider returned error", "metadata": metadata]]
            return .json(error.text, status: status)
        }

        /// A request body without its response format, the only part that the portable schema changes.
        private func withoutResponseFormat(_ body: JSONValue) -> JSONValue {
            guard case .object(var object) = body else { return body }
            object["response_format"] = nil
            return .object(object)
        }

        /// Checks that a recipe's schema keeps its constraints.
        private func expectFull(_ schema: JSONValue) {
            #expect(
                schema["properties"]?["servings"] == ["description": "How many it serves.", "maximum": 12, "minimum": 1, "type": "integer"]
            )
            #expect(schema["properties"]?["steps"]?["maxItems"] == 5)
        }

        /// Checks that a recipe's schema has its constraints in descriptions, after any description of its own.
        private func expectPortable(_ schema: JSONValue) {
            let servings = schema["properties"]?["servings"]
            #expect(servings == ["description": "How many it serves.\n\n{maximum: 12, minimum: 1}", "type": "integer"])
            #expect(schema["properties"]?["name"]?["anyOf"]?[0] == ["description": #"{pattern: "[A-Z].*"}"#, "type": "string"])
            let steps = schema["properties"]?["steps"]
            #expect(steps?["minItems"] == nil)
            #expect(steps?["maxItems"] == nil)
            #expect(steps?["description"] == "{maxItems: 5, minItems: 1}")
            let grams = schema["$defs"]?["Ingredient"]?["properties"]?["grams"]
            #expect(grams == ["description": "{minimum: 1}", "type": "integer"])
            #expect(schema["properties"]?["ingredients"]?["description"] == "{maxItems: 3, minItems: 3}")
        }
    }
}

/// A recipe with the guides that become JSON Schema constraints.
@Generable
private struct Recipe {
    @Guide(.pattern(/[A-Z].*/))
    var name: String?

    @Guide(description: "How many it serves.", .range(1...12))
    var servings: Int

    @Guide(.count(1...5))
    var steps: [String]

    @Guide(.count(3))
    var ingredients: [Ingredient]

    /// An answer that matches the schema.
    static let answer =
        #"{"name":"Soup","servings":2,"steps":["Boil."],"ingredients":[{"grams":200},{"grams":10},{"grams":5}]}"#
}

@Generable
private struct Ingredient {
    @Guide(.minimum(1))
    var grams: Int
}

@Generable
private struct Unbounded {
    @Guide(.minimum(-Double.infinity))
    var value: Double
}

@Generable
private struct Meal {
    var name: String
    var servings: Int
    var notes: String?
}
