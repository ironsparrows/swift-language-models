import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenAILanguageModels

extension ExactExchange {
    /// A streamed answer with reasoning, instructions, a token limit, metadata, OpenAI's options, and the organization
    /// and project headers.
    static func textWithOptions() async -> ExactExchange {
        let stub = HTTPStub(
            responseStream(
                headers: ["x-request-id": "req_1"],
                [created()],
                reasoningItem(at: 0, id: "rs_1", summary: "Plan it.", encrypted: "blob-1"),
                [
                    item("response.output_item.added", at: 1, ["type": "message", "id": "msg_1", "role": "assistant", "content": []]),
                    textDelta("Start ", at: 1), textDelta("Monday.", at: 1),
                    item("response.output_item.done", at: 1, ["type": "message", "id": "msg_1", "phase": "final_answer"]),
                    completed(input: 12, cached: 4, output: 9, reasoning: 3),
                ]))
        let options = OpenAIOptions(
            serviceTier: .flex, verbosity: .low, reasoningSummary: .auto, cacheKey: .session, endUserID: "user-1", storage: .notStored)
        let languageModel = model(
            stub, details(efforts: [ContextOptions.ReasoningLevel.high, .medium, .low, .off]), options: options,
            auth: .apiKey(organization: "org-1", project: "proj-1") { "sk-test" })
        let generation = GenerationOptions(temperature: 0.5, maximumResponseTokens: 100)
        return await ExactExchange(stub, LanguageModelSession(model: languageModel, instructions: "Be brief.")) { session, lastSnapshot in
            try await stream(
                session.streamResponse(
                    to: "Plan the week.", options: generation, contextOptions: ContextOptions(reasoningLevel: .light),
                    metadata: ["team": "coach"]),
                into: &lastSnapshot)
        }
    }

    /// An answer that reasons and calls a tool twice at once, then the answer to the tools' outputs, with the reasoning
    /// item going back before the calls.
    static func toolRound() async -> ExactExchange {
        let stub = HTTPStub(
            responseStream(
                [created()],
                reasoningItem(at: 0, id: "rs_1", summary: "Look both up.", encrypted: "blob-1"),
                functionCall(at: 1, callID: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                functionCall(at: 2, callID: "call_2", name: "lookUpFood", arguments: #"{"food":"rice"}"#),
                [completed(output: 20, reasoning: 8)]),
            responseStream([created()], [textDelta("Both have 100 kcal."), completed(input: 40, cached: 12, output: 6)]))
        let languageModel = reasoningModel(stub, options: OpenAIOptions(parallelToolCalls: .allowed))
        return await ExactExchange(stub, LanguageModelSession(model: languageModel, tools: [FoodTool()])) { session, _ in
            try await session.respond(to: "Calories in an egg and rice?").usage
        }
    }

    /// A model that doesn't reason, with its instructions as a system message and its sampling settings sent.
    static func plain() async -> ExactExchange {
        let stub = HTTPStub(responseStream([created(model: "gpt-plain")], [textDelta("Hello."), completed(model: "gpt-plain")]))
        let generation = GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9, seed: 7), temperature: 0.5)
        return await ExactExchange(stub, LanguageModelSession(model: plainModel(stub), instructions: "Be brief.")) { session, _ in
            try await session.respond(to: "Hi", options: generation).usage
        }
    }

    /// A streamed answer that an error event ends partway, after the response's HTTP 200.
    static func errorMidStream() async -> ExactExchange {
        let failure: JSONValue = [
            "type": "error", "code": "server_error", "message": "The server had an error.", "param": nil, "sequence_number": 3,
        ]
        let stub = HTTPStub(responseStream(headers: ["x-request-id": "req_9"], [created(), textDelta("Partial "), failure]))
        return await ExactExchange(stub, LanguageModelSession(model: reasoningModel(stub))) { session, lastSnapshot in
            try await stream(session.streamResponse(to: "Plan the week."), into: &lastSnapshot)
        }
    }

    /// A real streamed answer with reasoning, recorded from OpenAI.
    static func realStream() async throws -> ExactExchange {
        let recorded = try Bundle.module.fixture("reasoning-stream.sse")
        let stub = HTTPStub(StubResponse(status: 200, headers: ["Content-Type": "text/event-stream"], chunks: [recorded]))
        return await ExactExchange(stub, LanguageModelSession(model: reasoningModel(stub))) { session, _ in
            try await session.respond(to: "What is 17 times 23? Reply with the number only.").usage
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    /// An earlier prompt with an image and a labeled PDF, which go back with the next prompt.
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    static func attachments() async throws -> ExactExchange {
        let stub = HTTPStub(responseStream([created()], [textDelta("A menu and a photo."), completed()]))
        let photo = Transcript.ImageAttachment(try #require(TestImage.halves(width: 8, height: 4)))
        let pdf = Transcript.DataAttachment(contentType: .pdf, content: pdfDocument(showing: "Soup of the day"))
        let transcript = Transcript(entries: [
            .prompt(
                Transcript.Prompt(segments: [
                    .text(.init(content: "Keep these.")),
                    .attachment(.init(content: .image(photo), label: "Photo")),
                    .attachment(.init(content: .data(pdf), label: "Menu")),
                ])),
            .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Kept."))])),
        ])
        return await ExactExchange(stub, LanguageModelSession(model: reasoningModel(stub), transcript: transcript)) { session, _ in
            try await session.respond(to: "What's in these?").usage
        }
    }
    #endif
}
