import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Stream")
    struct Stream {
        @Test func `a request goes to chat/completions with the provider's headers, and its answer streams back`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(["choices": [["delta": ["content": "Hi"]]]], ["choices": [["delta": [:], "finish_reason": "stop"]]]))

            let (answer, failure) = await respond(stub, to: [prompt(text("Hello"))])

            if let failure { Issue.record("The answer failed: \(failure)") }
            #expect(answer?.responseText == "Hi")
            let sent = try #require(stub.requests.first)
            #expect(sent.request.url?.path == "/chat/completions")
            #expect(sent.request.value(forHTTPHeaderField: "X-Test") == "yes")
            #expect(
                String(decoding: sent.body, as: UTF8.self)
                    == #"{"model":"vendor/model","messages":[{"role":"user","content":"Hello"}],"stream":true}"#)
        }

        @Test func `a plain model answers in a session with no provider`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]]]))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")

            #expect(response.content == "Hi")
            #expect(stub.requests.first?.request.url?.path == "/chat/completions")
        }

        @Test func `the provider's own members of each chunk add reasoning and the host`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    ["host": "Vendor", "choices": [["delta": ["reasoning": "Think."]]]],
                    ["choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]]]))

            let (answer, failure) = await respond(stub, to: [prompt(text("Hello"))])

            if let failure { Issue.record("The answer failed: \(failure)") }
            #expect(answer?.responseText == "Hi")
        }

        @Test func `a chunk and the provider's own members are read from the same event`() async {
            let stub = HTTPStub(
                chatCompletionsEvents([
                    "id": "gen-1", "model": "vendor/model", "host": "Vendor", "service_tier": "flex",
                    "choices": [
                        [
                            "delta": [
                                "content": "Hi", "reasoning": "Think.",
                                "annotations": [
                                    [
                                        "type": "url_citation",
                                        "url_citation": ["url": "https://example.com", "start_index": 0, "end_index": 2],
                                    ]
                                ],
                            ],
                            "finish_reason": "stop",
                        ]
                    ],
                    "usage": [
                        "prompt_tokens": 12, "completion_tokens": 5, "prompt_tokens_details": ["cached_tokens": 4],
                        "completion_tokens_details": ["reasoning_tokens": 2],
                    ],
                ]))

            let exchange = await answer(stub)

            #expect(exchange.error == nil)
            #expect(
                exchange.transcript == [
                    #"prompt ["Hello"] metadata: {}"#,
                    #"reasoning ["Think."] metadata: {"model":"vendor/model","reasoningOrigin":"test"} signature: nil"#,
                    #"response ["Hi"] metadata: {"citations":[{"endOffset":2,"excerpt":null,"startOffset":0,"title":null,"url":"https://example.com"}],"finishReason":"stop","model":"vendor/model","provider":"Vendor","responseID":"gen-1","serviceTier":"flex"}"#,
                ])
            #expect(exchange.usage == #"input 12 cached 4, output 5 reasoning 2, metadata: {}"#)
        }

        @Test func `[DONE] ends the stream, and an event without data is skipped`() async {
            let chunk: JSONValue = ["choices": [["delta": ["content": "Hi"]]]]
            let stub = HTTPStub(.eventStream(Data("data:\n\ndata: \(chunk.text)\n\ndata: [DONE]\n\ndata: not a chunk\n\n".utf8)))

            let exchange = await answer(stub)

            #expect(exchange.error == nil)
            #expect(exchange.transcript.last == #"response ["Hi"] metadata: {}"#)
        }

        @Test func `a fact that a chunk reports replaces the earlier one, and one it leaves out keeps its value`() async {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    ["id": "gen-1", "model": "vendor/model", "provider": "Vendor", "service_tier": "flex"],
                    [
                        "model": "vendor/model-2026-10-01",
                        "choices": [["delta": [:], "finish_reason": "length"]],
                        "usage": ["prompt_tokens": 12, "completion_tokens": 5, "prompt_tokens_details": ["cache_write_tokens": 3]],
                    ],
                    ["choices": [["delta": [:]]]]))

            let exchange = await answer(stub)

            #expect(exchange.error == nil)
            #expect(
                exchange.transcript.last
                    == #"response [""] metadata: {"cacheWriteTokenCount":3,"finishReason":"length","model":"vendor/model-2026-10-01","responseID":"gen-1","serviceTier":"flex"}"#
            )
            #expect(exchange.usage == #"input 12 cached 0, output 5 reasoning 0, metadata: {"cacheWriteTokenCount":3}"#)
        }

        @Test func `the metadata names the answer's facts`() async {
            let stub = HTTPStub(
                chatCompletionsEvents([
                    "id": "gen-1", "model": "vendor/model", "service_tier": "priority",
                    "choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]],
                ]))

            let exchange = await answer(stub)

            #expect(
                exchange.transcript.last
                    == #"response ["Hi"] metadata: {"finishReason":"stop","model":"vendor/model","responseID":"gen-1","serviceTier":"priority"}"#
            )
        }

        @Test func `facts that no chunk reported are left out of the metadata`() async {
            let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": "Hi"]]]]))

            let exchange = await answer(stub)

            #expect(exchange.transcript.last == #"response ["Hi"] metadata: {}"#)
        }
    }
}
