import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Guided generation")
    struct GuidedGeneration {
        @Test func `a plain model holds an answer to its schema's guides`() async {
            let stub = HTTPStub(chatCompletionsEvents(textChunk(#"{"stars":9}"#, finishReason: "stop")))

            await #expect(throws: GeneratedContent.ParsingError.self) {
                _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)
            }
        }

        @Test func `an answer is held to the full schema's guides, even when the portable schema went out`() async {
            let stub = HTTPStub(chatCompletionsEvents(textChunk(#"{"stars":9}"#, finishReason: "stop")))
            var model = model(stub)
            model.exchange.prepares = { $0.usesPortableSchema = true }

            let error = await #expect(throws: GeneratedContent.ParsingError.self) {
                _ = try await LanguageModelSession(model: model).respond(to: "Rate it.", generating: Rating.self)
            }

            #expect(error?.debugDescription == "The answer breaks its schema's guides: stars is 9, above the maximum of 5.")
        }

        @Test(arguments: [
            "Invalid decoding guidance syntax: Keyword 'maxItems' is not supported for type 'array' at path '$.properties.steps'",
            "invalid request: response_format validation: invalid 'json_schema' provided: error at 'properties.steps': "
                + "received non-supported constraint for type: 'array'. constraint: 'minItems'",
            "output_format.schema: For 'integer' type, properties maximum, minimum are not supported",
            "Invalid schema for response_format 'Recipe': In context=('properties', 'name'), 'pattern' is not permitted.",
        ])
        func `a host that rejects a constraint of the schema gets the portable schema once`(message: String) async throws {
            let stub = HTTPStub(rejection(message), chatCompletionsEvents(textChunk(#"{"stars":4}"#, finishReason: "stop")))

            let rating = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self).content

            #expect(rating.stars == 4)
            #expect(stub.requests.count == 2)
            let first = try sentBody(stub, 0)
            let second = try sentBody(stub, 1)
            #expect(first["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == 5)
            #expect(second["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
            #expect(withoutResponseFormat(first) == withoutResponseFormat(second))
        }

        @Test func `a portable schema that's rejected too isn't sent a third time`() async {
            let message = "Keyword 'maximum' is not supported for type 'integer'"
            let stub = HTTPStub(
                rejection(message), rejection(message), chatCompletionsEvents(textChunk(#"{"stars":4}"#, finishReason: "stop")))

            let failure = await #expect(throws: RequestFailure<APIErrorBody>.self) {
                try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)
            }

            #expect(failure?.status == 400)
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
        func `a failure that doesn't reject a schema constraint isn't sent again`(status: Int, message: String) async {
            let stub = HTTPStub(
                rejection(message, status: status), chatCompletionsEvents(textChunk(#"{"stars":4}"#, finishReason: "stop")))

            let failure = await #expect(throws: RequestFailure<APIErrorBody>.self) {
                try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)
            }

            #expect(failure?.status == status)
            #expect(stub.requests.count == 1)
        }

        @Test func `a schema goes as strict structured outputs, with a portable body for a host that rejects a constraint`() throws {
            let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

            let completion = try ChatCompletionsSentRequest(request)

            let format = try #require(completion.body["response_format"])
            #expect(format["type"] == "json_schema")
            #expect(format["json_schema"]?["name"] == "Rating")
            #expect(format["json_schema"]?["strict"] == true)
            #expect(format["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == 5)
            let portable = try #require(completion.portableSchemaBody?["response_format"]?["json_schema"]?["schema"])
            #expect(portable["properties"]?["stars"]?["maximum"] == nil)
        }

        @Test func `a strict schema requires every property, and an optional one takes null`() throws {
            let request = generationRequest([prompt(text("A dinner idea."))], schema: Meal.generationSchema)

            let schema = try #require(try ChatCompletionsSentRequest(request).body["response_format"]?["json_schema"]?["schema"])

            #expect(schema["required"] == ["name", "servings", "notes"])
            #expect(schema["properties"]?["notes"]?["anyOf"]?[1]?["type"] == "null")
        }

        @Test func `an exchange that sends the portable schema from the start has no body to retry with`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.usesPortableSchema = true }
            let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

            let completion = try ChatCompletionsSentRequest(request, model: model)

            #expect(completion.body["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
            #expect(completion.portableSchemaBody == nil)
        }

        @Test func `a streamed answer becomes the generated value`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    textChunk(#"{"name":"So"#), textChunk(#"up","servings":"#), textChunk(#"2,"notes":null}"#, finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub))

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

        @Test func `a schema with a guide JSON can't hold throws unsupported generation guide before any request`() async {
            let stub = HTTPStub(chatCompletionsEvents(textChunk(#"{"value":1}"#, finishReason: "stop")))

            let error = await #expect(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: plainModel(stub)).respond(to: "A number.", generating: Unbounded.self)
            }

            guard case .unsupportedGenerationGuide? = error else {
                Issue.record("Expected an unsupported generation guide, got \(String(describing: error))")
                return
            }
            #expect(stub.requests.isEmpty)
        }

        @Test func `JSON that doesn't match the schema throws the parsing error`() async {
            let stub = HTTPStub(chatCompletionsEvents(textChunk(#"{"name":3}"#, finishReason: "stop")))

            await #expect(throws: GeneratedContent.ParsingError.self) {
                try await LanguageModelSession(model: plainModel(stub)).respond(to: "A dinner idea.", generating: Meal.self)
            }
        }

        @Test func `a guided answer cut off at its token limit throws the parsing error`() async {
            let stub = HTTPStub(chatCompletionsEvents(textChunk(#"{"name":"Soup","servings":4,"notes":"Ser"#, finishReason: "length")))

            let error = await #expect(throws: GeneratedContent.ParsingError.self) {
                try await LanguageModelSession(model: plainModel(stub)).respond(to: "A dinner idea.", generating: Meal.self)
            }

            #expect(error?.debugDescription == "The answer reached its token limit before it was complete.")
        }

        @Test func `text before a round of tool calls isn't checked, and the round that follows is`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    textChunk(#"{"stars":9}"#), toolCallChunk(0, id: "call_1", name: "lookUp", arguments: #"{"word":"egg"}"#),
                    finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk(#"{"stars":4}"#, finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])

            let rating = try await session.respond(to: "Rate it.", generating: Rating.self).content

            #expect(rating.stars == 4)
            #expect(stub.requests.count == 2)
        }

        @Test func `only the text after a reasoning block is checked`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(textChunk(#"<think>{"stars":9}</think>"#), textChunk(#"{"stars":4}"#, finishReason: "stop")))

            let rating = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self).content

            #expect(rating.stars == 4)
        }

        @Test func `a schema left out of the prompt goes only in the response format`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk(#"{"stars":4}"#, finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub))

            _ = try await session.respond(to: "Rate it.", generating: Rating.self, includeSchemaInPrompt: false)

            let body = try sentBody(stub)
            #expect(body["response_format"]?["type"] == "json_schema")
            #expect(messages(body).last?["content"] == "Rate it.")
        }

        @Test func `an earlier prompt keeps its schema text when a later request leaves its schema out`() async throws {
            let answer = chatCompletionsEvents(textChunk(#"{"stars":4}"#, finishReason: "stop"))
            let stub = HTTPStub(answer, answer)
            let session = LanguageModelSession(model: plainModel(stub))

            _ = try await session.respond(to: "Rate it.", generating: Rating.self)
            _ = try await session.respond(to: "Again.", generating: Rating.self, includeSchemaInPrompt: false)

            let first = try #require(messages(try sentBody(stub, 0)).last)
            let replayed = try #require(messages(try sentBody(stub, 1)).first { $0["role"] == "user" })
            #expect(replayed == first)
        }

        /// A host's failure, with its own message as the error's.
        private func rejection(_ message: String, status: Int = 400) -> StubResponse {
            let error: JSONValue = ["error": ["message": .string(message)]]
            return .json(error.text, status: status)
        }

        /// A request body without its response format, the only part that the portable schema changes.
        private func withoutResponseFormat(_ body: JSONValue) -> JSONValue {
            guard case .object(var object) = body else { return body }
            object["response_format"] = nil
            return .object(object)
        }
    }
}

@Generable
private struct Meal {
    var name: String
    var servings: Int
    var notes: String?
}

@Generable
private struct Unbounded {
    @Guide(.minimum(-Double.infinity))
    var value: Double
}
