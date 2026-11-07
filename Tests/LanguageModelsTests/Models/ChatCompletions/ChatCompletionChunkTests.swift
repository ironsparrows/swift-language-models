import Foundation
import Testing

@testable import LanguageModels

@Suite("Chat completion chunk")
struct ChatCompletionChunkTests {
    @Test func `a chunk and the provider's own members are read from the same event`() throws {
        let data: JSONValue = [
            "id": "gen-1", "model": "vendor/model", "host": "Vendor", "service_tier": "flex",
            "choices": [
                [
                    "delta": [
                        "content": "Hi", "refusal": "No.", "reasoning": "Think.",
                        "tool_calls": [["index": 0, "id": "call_1", "function": ["name": "lookUp", "arguments": "{}"]]],
                        "annotations": [
                            ["type": "url_citation", "url_citation": ["url": "https://example.com", "start_index": 0, "end_index": 2]]
                        ],
                    ],
                    "finish_reason": "stop",
                ]
            ],
            "usage": [
                "prompt_tokens": 12, "completion_tokens": 5, "prompt_tokens_details": ["cached_tokens": 4],
                "completion_tokens_details": ["reasoning_tokens": 2],
            ],
        ]

        let event = try ChatCompletionChunk.StreamEvent<TestExtras>(ServerSentEvent(data: data.text))

        guard case .chunk(let chunk, let extras, _)? = event else {
            Issue.record("The event isn't a chunk: \(String(describing: event))")
            return
        }
        let delta = try #require(chunk.choices?.first?.delta)
        #expect(chunk.id == "gen-1")
        #expect(chunk.model == "vendor/model")
        #expect(chunk.serviceTier == "flex")
        #expect(chunk.choices?.first?.finishReason == .stop)
        #expect(delta.content == "Hi")
        #expect(delta.refusal == "No.")
        #expect(delta.toolCalls?.first?.function?.name == "lookUp")
        #expect(delta.annotations?.first?.urlCitation?.url == "https://example.com")
        #expect(chunk.usage?.promptTokensDetails?.cachedTokens == 4)
        #expect(chunk.usage?.completionTokensDetails?.reasoningTokens == 2)
        #expect(extras.host == "Vendor")
        #expect(extras.choices?.first?.delta?.reasoning == "Think.")
    }

    @Test func `[DONE] ends the stream, and an event without data is skipped`() throws {
        let done = try ChatCompletionChunk.StreamEvent<NoMembers>(ServerSentEvent(data: "[DONE]"))
        let empty = try ChatCompletionChunk.StreamEvent<NoMembers>(ServerSentEvent(data: ""))

        guard case .done? = done else {
            Issue.record("[DONE] isn't the end: \(String(describing: done))")
            return
        }
        #expect(empty == nil)
    }

    @Test func `an event that isn't a chunk throws`() {
        #expect(throws: DecodingError.self) { try ChatCompletionChunk.StreamEvent<NoMembers>(ServerSentEvent(data: "[1, 2]")) }
    }
}
