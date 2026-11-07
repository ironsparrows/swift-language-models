import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

@Suite("Chat Completions stream")
struct ChatCompletionsStreamTests {
    @Test func `a chunk and the provider's own members are read from the same event`() async {
        let stub = HTTPStub(
            chatCompletionsEvents([
                "id": "gen-1", "model": "vendor/model", "host": "Vendor", "service_tier": "flex",
                "choices": [
                    [
                        "delta": [
                            "content": "Hi", "reasoning": "Think.",
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

    @Test func `the fragments of a tool call form one call, whose answer goes back in the next round`() async throws {
        let stub = HTTPStub(
            chatCompletionsEvents(
                [
                    "choices": [
                        ["delta": ["tool_calls": [["index": 0, "id": "call_1", "function": ["name": "lookUp", "arguments": "{\"wo"]]]]]
                    ]
                ],
                [
                    "choices": [
                        [
                            "delta": ["tool_calls": [["index": 0, "function": ["arguments": "rd\":\"egg\"}"]]]],
                            "finish_reason": "tool_calls",
                        ]
                    ]
                ]),
            chatCompletionsEvents(["choices": [["delta": ["content": "Done."], "finish_reason": "stop"]]]))
        let session = LanguageModelSession(model: model(stub), tools: [LookUpTool()])

        let response = try await session.respond(to: "Define egg.")

        #expect(response.content == "Done.")
        let bodies = try stub.requests.map { try JSONValue(json: $0.body) }
        #expect(messages(try #require(bodies.last)).dropFirst().first?["tool_calls"]?[0]?["function"]?["arguments"] == #"{"word":"egg"}"#)
    }

    @Test func `a refusal fails the answer as Foundation Models' refusal`() async {
        let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["refusal": "No."], "finish_reason": "stop"]]]))

        let error = await error(of: stub)

        guard case .refusal? = error as? LanguageModelError else {
            Issue.record("The answer ended with \(String(describing: error))")
            return
        }
    }

    @Test func `[DONE] ends the stream, and an event without data is skipped`() async {
        let chunk: JSONValue = ["choices": [["delta": ["content": "Hi"]]]]
        let stub = HTTPStub(.eventStream(Data("data:\n\ndata: \(chunk.text)\n\ndata: [DONE]\n\ndata: not a chunk\n\n".utf8)))

        let exchange = await answer(stub)

        #expect(exchange.error == nil)
        #expect(exchange.transcript.last == #"response ["Hi"] metadata: {}"#)
    }

    @Test func `an event that isn't a chunk throws`() async {
        let stub = HTTPStub(.eventStream(Data("data: [1, 2]\n\n".utf8)))

        let failure = await error(of: stub) as? RequestFailure<APIErrorBody>

        guard case .unreadableEvent? = failure?.kind, failure?.message.hasPrefix("Test sent an event that couldn't be read") == true else {
            Issue.record("The answer ended with \(String(describing: failure))")
            return
        }
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

/// A model of a provider named `Test`, sending to a stub.
private func model(_ stub: HTTPStub) -> ChatCompletions.Model<ChatCompletionsTestExchange> {
    .test(url: stub.baseURL, session: stub.session)
}

/// A session's exchange with a stub, for one prompt.
private func answer(_ stub: HTTPStub) async -> ExactExchange {
    await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
        try await session.respond(to: "Hello").usage
    }
}

/// The error a session's one prompt ends in, or `nil` when it's answered.
private func error(of stub: HTTPStub) async -> (any Error)? {
    do {
        _ = try await LanguageModelSession(model: model(stub)).respond(to: "Hello")
        return nil
    } catch {
        return error
    }
}
