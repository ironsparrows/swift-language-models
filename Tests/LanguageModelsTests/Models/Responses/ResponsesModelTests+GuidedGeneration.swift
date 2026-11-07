import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Guided generation")
    struct GuidedGeneration {
        @Test func `a plain model holds an answer to its schema's guides`() async {
            let stub = HTTPStub(events(textDelta(#"{"stars":9}"#), lifecycle("response.completed")))

            await #expect(throws: GeneratedContent.ParsingError.self) {
                _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)
            }
        }

        @Test func `a host that rejects a constraint of the schema gets the portable schema once`() async throws {
            let rejection = #"{"error":{"message":"Keyword 'maximum' is not supported for type 'integer'"}}"#
            let stub = HTTPStub(.json(rejection, status: 400), events(textDelta(#"{"stars":4}"#), lifecycle("response.completed")))

            let (answer, failure) = await respond(stub, to: [prompt(text("Rate it."))], schema: Rating.generationSchema)

            if let failure { Issue.record("The answer failed: \(failure)") }
            #expect(answer?.responseText == #"{"stars":4}"#)
            let bodies = try stub.requests.map { try JSONValue(json: $0.body) }
            #expect(bodies.count == 2)
            #expect(bodies.first?["text"]?["format"]?["schema"]?["properties"]?["stars"]?["maximum"] == 5)
            #expect(bodies.last?["text"]?["format"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
        }

        @Test func `a guided answer decodes only its final answer, and keeps its commentary in the metadata`() async {
            let stub = HTTPStub(
                events(
                    item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1", "phase": "commentary"]),
                    textDelta("Here it is. ", at: 0),
                    item("response.output_item.added", at: 1, ["type": "message", "id": "msg_2", "phase": "final_answer"]),
                    textDelta(#"{"stars":4}"#, at: 1), lifecycle("response.completed")))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "Rate it.", generating: Rating.self).usage
            }

            #expect(exchange.error == nil)
            #expect(
                exchange.transcript.last?.contains(
                    #""test.phases":[{"heldText":"Here it is. ","length":0,"phase":"commentary"},{"length":11,"phase":"final_answer"}]"#)
                    == true)
        }

        @Test func `a guided answer of two final messages decodes the first, and keeps the second in the metadata`() async {
            let stub = HTTPStub(
                events(
                    item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1"]), textDelta(#"{"stars":4}"#, at: 0),
                    item("response.output_item.added", at: 1, ["type": "message", "id": "msg_2"]), textDelta(#"{"stars":5}"#, at: 1),
                    lifecycle("response.completed")))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "Rate it.", generating: Rating.self).usage
            }

            #expect(exchange.error == nil)
            #expect(
                exchange.transcript.last?.contains(
                    #""test.phases":[{"length":11,"phase":null},{"heldText":"{\"stars\":5}","length":0,"phase":null}]"#) == true,
                "\(exchange.transcript)")
        }

        @Test func `the phase a message starts with decides which message a guided answer decodes`() async {
            let stub = HTTPStub(
                events(
                    item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1"]),
                    textDelta(#"{"stars":4}"#, at: 0),
                    item("response.output_item.done", at: 0, ["type": "message", "id": "msg_1", "phase": "final_answer"]),
                    item("response.output_item.added", at: 1, ["type": "message", "id": "msg_2", "phase": "commentary"]),
                    textDelta("Done.", at: 1), lifecycle("response.completed")))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "Rate it.", generating: Rating.self).usage
            }

            #expect(exchange.error == nil)
            #expect(
                exchange.transcript.last?.contains(
                    #""test.phases":[{"length":11,"phase":"final_answer"},{"heldText":"Done.","length":0,"phase":"commentary"}]"#) == true)
        }

        @Test func `a schema goes in full, with the portable schema ready`() throws {
            let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

            let sent = try SentRequest(request)

            #expect(sent.body["text"]?["format"]?["schema"]?["properties"]?["stars"]?["maximum"] == 5)
            #expect(sent.portableSchemaBody?["text"]?["format"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
            #expect(sent.portableSchemaBody?["text"]?["format"]?["schema"]?["properties"]?["stars"]?["description"] != nil)
        }
    }
}
