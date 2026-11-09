import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

/// What the typed readers read of an answer's facts and a failure's, and the keys saved transcripts keep.
@Suite("Metadata", .timeLimit(.minutes(1)))
struct OpenAICompatibleMetadataTests {
    @Test func `an answer's facts read as the module's types, with its usage's`() async throws {
        let usage: JSONValue = [
            "id": "chatcmpl-1", "choices": [],
            "usage": [
                "prompt_tokens": 12, "completion_tokens": 5, "prompt_tokens_details": ["cached_tokens": 4, "cache_write_tokens": 2],
            ],
        ]
        let stub = HTTPStub(chunks(headers: ["x-request-id": "req_1"], text("Hi"), finish("length"), usage))
        let session = LanguageModelSession(model: model(stub))

        let response = try await session.respond(to: "Hi")

        guard case .response(let answer)? = session.transcript.last else {
            Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
            return
        }
        let facts = answer.openAICompatible
        #expect(facts.model == "test-model-2026-10-01")
        #expect(facts.responseID == "chatcmpl-1")
        #expect(facts.requestID == "req_1")
        #expect(facts.finishReason == .length)
        #expect(facts.citations.isEmpty)
        #expect(facts.usage.cacheWriteTokenCount == 2)
        #expect(response.usage.openAICompatible.cacheWriteTokenCount == 2)
    }

    @Test func `the facts of a request that ended in tool calls read from its first call`() async throws {
        let call: JSONValue = delta(
            [
                "tool_calls": [
                    ["index": 0, "id": "call_1", "type": "function", "function": ["name": "lookUp", "arguments": #"{"word":"sea"}"#]]
                ]
            ],
            finishReason: "tool_calls")
        let stub = HTTPStub(chunks(call), chunks(text("Blue."), finish()))
        let session = LanguageModelSession(model: model(stub), tools: [LookUpTool()])

        _ = try await session.respond(to: "Look up sea.")

        let calls = session.transcript.compactMap { entry -> Transcript.ToolCalls? in
            if case .toolCalls(let calls) = entry { calls } else { nil }
        }
        #expect(calls.first?.openAICompatible.finishReason == .toolCalls)
        #expect(calls.first?.openAICompatible.model == "test-model-2026-10-01")
    }

    @Test func `a Responses answer keeps its messages' phases under the key saved transcripts keep`() async throws {
        let stub = HTTPStub(
            events(
                item("response.output_item.added", at: 0, ["type": "message", "role": "assistant", "phase": "final_answer"]),
                textDelta("Hi"), completed()))
        let session = LanguageModelSession(model: model(stub, format: .responses))

        _ = try await session.respond(to: "Hi")

        guard case .response(let answer)? = session.transcript.last else {
            Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
            return
        }
        #expect(answer.metadata["openAICompatible.phases"] != nil)
        #expect(OpenAICompatibleResponseMetadata.serverToolsKey == "openAICompatible.serverTools")
    }

    @Test func `a failure's facts read the provider's name from its key`() {
        let error = LanguageModelError.timeout(
            .init(
                debugDescription: "Timed out.",
                metadata: ["openAICompatible.providerName": "Gateway", "status": 504, "errorCode": "server"]))

        #expect(error.openAICompatible.providerName == "Gateway")
        #expect(error.openAICompatible.status == 504)
        #expect(error.openAICompatible.code == .server)
        #expect(LanguageModelError.timeout(.init(debugDescription: "Timed out.")).openAICompatible.providerName == nil)
    }
}
