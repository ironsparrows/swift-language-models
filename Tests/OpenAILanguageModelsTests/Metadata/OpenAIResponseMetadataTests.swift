import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

@Suite("Response metadata", .timeLimit(.minutes(1)))
struct OpenAIResponseMetadataTests {
    @Test func `the facts of an answer reach its response entry as typed values`() async throws {
        let citation: JSONValue = [
            "type": "response.output_text.annotation.added", "output_index": 0, "content_index": 0, "annotation_index": 0,
            "annotation": ["type": "url_citation", "url": "https://example.com/week", "title": "Week", "start_index": 0, "end_index": 5],
        ]
        let stub = HTTPStub(
            events(
                headers: ["x-request-id": "req_1"], created(),
                item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1", "phase": "final_answer"]),
                textDelta("Seven", at: 0), citation, completed()))

        let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "How many days in a week?")

        let metadata = try #require(lastAnswer(in: response.transcriptEntries)).openAI
        let url = try #require(URL(string: "https://example.com/week"))
        #expect(metadata.model == "gpt-test-2026-10-01")
        #expect(metadata.responseID == "resp_1")
        #expect(metadata.requestID == "req_1")
        #expect(metadata.finishReason == .stop)
        #expect(metadata.serviceTier == .default)
        #expect(metadata.citations == [Citation(url: url, title: "Week", startOffset: 0, endOffset: 5)])
        #expect(metadata.messages.map(\.phase) == [.finalAnswer])
        #expect(metadata.messages.map(\.length) == [5])
        #expect(metadata.messages.map(\.heldText) == [nil])
    }

    @Test func `a guided answer's commentary reads as a message held out of its text`() async throws {
        let stub = HTTPStub(
            events(
                created(), item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1", "phase": "commentary"]),
                textDelta("Here it is. ", at: 0),
                item("response.output_item.added", at: 1, ["type": "message", "id": "msg_2", "phase": "final_answer"]),
                textDelta(#"{"stars":4}"#, at: 1), completed()))

        let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)

        let messages = try #require(lastAnswer(in: response.transcriptEntries)).openAI.messages
        #expect(response.content.stars == 4)
        #expect(messages.map(\.phase) == [.commentary, .finalAnswer])
        #expect(messages.map(\.length) == [0, 11])
        #expect(messages.map(\.heldText) == ["Here it is. ", nil])
    }

    @Test func `a request that ends in tool calls keeps its facts on its first call`() async throws {
        let stub = HTTPStub(
            responseStream(
                headers: ["x-request-id": "req_1"], [created()],
                [item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1", "phase": "commentary"])],
                [textDelta("Checking. ", at: 0)], functionCall(at: 1, callID: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                [completed()]),
            responseStream([created()], [textDelta("An egg has 100 kcal."), completed()]))

        let response = try await LanguageModelSession(model: plainModel(stub), tools: [FoodTool()]).respond(to: "Calories in an egg?")

        let calls = try #require(
            response.transcriptEntries.lazy.compactMap { entry -> Transcript.ToolCalls? in
                if case .toolCalls(let calls) = entry { calls } else { nil }
            }.first)
        #expect(calls.openAI.model == "gpt-test-2026-10-01")
        #expect(calls.openAI.requestID == "req_1")
        #expect(calls.openAI.finishReason == .toolCalls)
        #expect(calls.openAI.messages.map(\.phase) == [.commentary])
    }

    @Test func `the prompt tokens written to the cache read from the usage and from the entry that ends the request`() async throws {
        let usage: JSONValue = [
            "input_tokens": 120, "input_tokens_details": ["cached_tokens": 0, "cache_write_tokens": 96], "output_tokens": 4,
            "output_tokens_details": ["reasoning_tokens": 0],
        ]
        let stub = HTTPStub(
            events(created(), textDelta("Hi"), lifecycle("response.completed", ["id": "resp_1", "model": "gpt-test", "usage": usage])))

        let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hi")

        #expect(response.usage.openAI.cacheWriteTokenCount == 96)
        #expect(try #require(lastAnswer(in: response.transcriptEntries)).openAI.usage.cacheWriteTokenCount == 96)
    }

    @Test func `an entry without OpenAI's facts reads as none`() {
        let metadata = OpenAIResponseMetadata([:])

        #expect(metadata.model == nil)
        #expect(metadata.requestID == nil)
        #expect(metadata.finishReason == nil)
        #expect(metadata.citations.isEmpty)
        #expect(metadata.messages.isEmpty)
        #expect(metadata.usage.cacheWriteTokenCount == nil)
    }
}

/// A rating, for a guided answer.
@Generable
private struct Rating {
    var stars: Int
}
