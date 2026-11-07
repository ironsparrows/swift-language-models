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
            let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": #"{"stars":9}"#], "finish_reason": "stop"]]]))

            await #expect(throws: GeneratedContent.ParsingError.self) {
                _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)
            }
        }

        @Test func `a host that rejects a constraint of the schema gets the portable schema once`() async throws {
            let rejection = #"{"error":{"message":"Keyword 'maximum' is not supported for type 'integer'"}}"#
            let stub = HTTPStub(
                .json(rejection, status: 400),
                chatCompletionsEvents(["choices": [["delta": ["content": #"{"stars":4}"#], "finish_reason": "stop"]]]))

            let (answer, failure) = await respond(stub, to: [prompt(text("Rate it."))], schema: Rating.generationSchema)

            if let failure { Issue.record("The answer failed: \(failure)") }
            #expect(answer?.responseText == #"{"stars":4}"#)
            let bodies = try stub.requests.map { try JSONValue(json: $0.body) }
            #expect(bodies.count == 2)
            #expect(bodies.first?["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == 5)
            #expect(bodies.last?["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
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

        @Test func `an exchange that sends the portable schema from the start has no body to retry with`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.usesPortableSchema = true }
            let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

            let completion = try ChatCompletionsSentRequest(request, model: model)

            #expect(completion.body["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
            #expect(completion.portableSchemaBody == nil)
        }
    }
}
