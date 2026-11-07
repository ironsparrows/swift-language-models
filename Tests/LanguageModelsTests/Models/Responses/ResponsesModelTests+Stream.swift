import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Stream")
    struct Stream {
        @Test func `a request goes to responses, and its answer streams back`() async throws {
            let stub = HTTPStub(events(textDelta("Hi"), lifecycle("response.completed")))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hello")

            #expect(response.content == "Hi")
            let sent = try #require(stub.requests.first)
            #expect(sent.request.url?.path == "/responses")
            #expect(
                String(decoding: sent.body, as: UTF8.self)
                    == #"{"model":"vendor/model","input":[{"role":"user","content":"Hello"}],"stream":true}"#)
        }

        @Test func `a plain model answers in a session with no provider`() async throws {
            let stub = HTTPStub(events(textDelta("Hi"), lifecycle("response.completed")))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")

            #expect(response.content == "Hi")
            #expect(stub.requests.first?.request.url?.path == "/responses")
        }

        @Test func `an event of a kind the format doesn't read is passed over, whatever its shape`() async throws {
            let shell: JSONValue = ["type": "response.shell_call_output_content.delta", "output_index": 0, "delta": ["stdout": "ok"]]
            let stub = HTTPStub(events(shell, textDelta("Hi"), lifecycle("response.completed")))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hello")

            #expect(response.content == "Hi")
        }

        @Test func `reasoning summaries, the reasoning item, text, citations, usage and the finish reason end up in the transcript`() async
        {
            let reasoningItem: JSONValue = [
                "type": "reasoning", "id": "rs_1", "encrypted_content": "blob",
                "summary": [["type": "summary_text", "text": "Count."], ["type": "summary_text", "text": "Seven."]],
            ]
            let summary = { (index: Int, delta: String) -> JSONValue in
                [
                    "type": "response.reasoning_summary_text.delta", "output_index": 0, "summary_index": .integer(index),
                    "delta": .string(delta),
                ]
            }
            let citation: JSONValue = [
                "type": "response.output_text.annotation.added", "output_index": 1, "content_index": 0, "annotation_index": 0,
                "annotation": [
                    "type": "url_citation", "url": "https://example.com/week", "title": "Week", "start_index": 0, "end_index": 5,
                ],
            ]
            let usage: JSONValue = [
                "input_tokens": 12, "input_tokens_details": ["cached_tokens": 4, "cache_write_tokens": 2], "output_tokens": 9,
                "output_tokens_details": ["reasoning_tokens": 3], "total_tokens": 21,
            ]
            let stub = HTTPStub(
                events(
                    lifecycle("response.created", ["id": "resp_1", "model": "vendor/model-2026-10-01", "service_tier": "default"]),
                    item("response.output_item.added", at: 0, ["type": "reasoning", "id": "rs_1", "summary": []]),
                    summary(0, "Count."), summary(1, "Seven."),
                    item("response.output_item.done", at: 0, reasoningItem),
                    item("response.output_item.added", at: 1, ["type": "message", "id": "msg_1", "role": "assistant", "content": []]),
                    textDelta("Seven ", at: 1), textDelta("days.", at: 1), citation,
                    item("response.output_item.done", at: 1, ["type": "message", "id": "msg_1", "phase": "final_answer"]),
                    lifecycle("response.completed", ["id": "resp_1", "model": "vendor/model-2026-10-01", "usage": usage])))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "How many days in a week?").usage
            }

            #expect(exchange.error == nil)
            #expect(
                exchange.transcript == [
                    #"prompt ["How many days in a week?"] metadata: {}"#,
                    #"reasoning ["Count.\n\nSeven."] metadata: {"model":"vendor/model-2026-10-01","reasoningOrigin":"test-responses"} signature: "[{\"encrypted_content\":\"blob\",\"id\":\"rs_1\",\"summary\":[{\"text\":\"Count.\",\"type\":\"summary_text\"},{\"text\":\"Seven.\",\"type\":\"summary_text\"}],\"type\":\"reasoning\"}]""#,
                    #"response ["Seven days."] metadata: {"cacheWriteTokenCount":2,"citations":[{"endOffset":5,"excerpt":null,"startOffset":0,"title":"Week","url":"https://example.com/week"}],"finishReason":"stop","model":"vendor/model-2026-10-01","responseID":"resp_1","serviceTier":"default","test.phases":[{"length":11,"phase":"final_answer"}]}"#,
                ])
            #expect(exchange.usage == #"input 12 cached 4, output 9 reasoning 3, metadata: {"cacheWriteTokenCount":2}"#)
        }

        @Test func `a commentary and a final answer keep their own phases, and reasoning text shows as reasoning`() async {
            let reasoningText: JSONValue = [
                "type": "response.reasoning_text.delta", "output_index": 0, "content_index": 0, "delta": "Think.",
            ]
            let stub = HTTPStub(
                events(
                    item("response.output_item.added", at: 0, ["type": "reasoning", "id": "rs_1", "summary": []]), reasoningText,
                    item(
                        "response.output_item.done", at: 0, ["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "blob"]),
                    item("response.output_item.added", at: 1, ["type": "message", "id": "msg_1", "phase": "commentary"]),
                    textDelta("Checking. ", at: 1),
                    item("response.output_item.done", at: 1, ["type": "message", "id": "msg_1", "phase": "commentary"]),
                    item("response.output_item.added", at: 2, ["type": "message", "id": "msg_2"]), textDelta("Seven.", at: 2),
                    item("response.output_item.done", at: 2, ["type": "message", "id": "msg_2", "phase": "final_answer"]),
                    lifecycle("response.completed")))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "How many days in a week?").usage
            }

            #expect(exchange.error == nil)
            #expect(exchange.transcript[1].hasPrefix(#"reasoning ["Think."]"#))
            #expect(
                exchange.transcript.last
                    == #"response ["Checking. Seven."] metadata: {"finishReason":"stop","test.phases":[{"length":10,"phase":"commentary"},{"length":6,"phase":"final_answer"}]}"#
            )
        }

        @Test func `a character split across deltas counts once, so the message's length matches its text`() async {
            let stub = HTTPStub(
                events(
                    item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1", "phase": "final_answer"]),
                    textDelta("Cafe", at: 0), textDelta("\u{301}.", at: 0), lifecycle("response.completed")))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "Where?").usage
            }

            #expect(exchange.error == nil)
            #expect(exchange.transcript.last?.contains(#""test.phases":[{"length":5,"phase":"final_answer"}]"#) == true)
        }

        @Test func `an answer that reaches its token limit keeps its text, with length as its finish reason`() async {
            let stub = HTTPStub(
                events(textDelta("Seven"), lifecycle("response.incomplete", ["incomplete_details": ["reason": "max_output_tokens"]])))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "How many days in a week?").usage
            }

            #expect(exchange.error == nil)
            #expect(exchange.transcript.last == #"response ["Seven"] metadata: {"finishReason":"length"}"#)
        }

        @Test(
            arguments: [
                (["incomplete_details": ["reason": "max_tool_calls"]], "max_tool_calls"), (["incomplete_details": [:]], "incomplete"),
                ([:], "incomplete"),
            ] as [(JSONValue, String)])
        func `an incomplete response ends with the host's reason, or incomplete when it gives none`(
            response: JSONValue, finishReason: String
        ) async {
            let stub = HTTPStub(events(textDelta("Seven"), lifecycle("response.incomplete", response)))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "How many days in a week?").usage
            }

            #expect(exchange.error == nil)
            #expect(exchange.transcript.last == #"response ["Seven"] metadata: {"finishReason":"\#(finishReason)"}"#)
        }

        @Test(
            arguments: [
                ("Checking. ", false, 10, 15), ("Café. ", false, nil, nil), ("Checking. ", true, nil, nil),
            ] as [(String, Bool, Int?, Int?)])
        func `a citation's offsets count from the start of the answer's text, when that's known`(
            commentary: String, isGuided: Bool, start: Int?, end: Int?
        ) async {
            let citation: JSONValue = [
                "type": "response.output_text.annotation.added", "output_index": 1, "content_index": 0, "annotation_index": 0,
                "annotation": [
                    "type": "url_citation", "url": "https://example.com/week", "title": "Week", "start_index": 0, "end_index": 5,
                ],
            ]
            let answer = isGuided ? #"{"stars":4}"# : "Seven days."
            let stub = HTTPStub(
                events(
                    item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1", "phase": "commentary"]),
                    textDelta(commentary, at: 0),
                    item("response.output_item.added", at: 1, ["type": "message", "id": "msg_2", "phase": "final_answer"]),
                    textDelta(answer, at: 1), citation, lifecycle("response.completed")))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                isGuided
                    ? try await session.respond(to: "Rate it.", generating: Rating.self).usage
                    : try await session.respond(to: "How many days?").usage
            }

            // A guided answer's commentary is held out of its text, so the citation's message starts the text.
            let offsets = isGuided ? (0, 5) : (start, end)
            #expect(exchange.error == nil)
            #expect(
                exchange.transcript.last?.contains(
                    #""citations":[{"endOffset":\#(offsets.1.map(String.init) ?? "null"),"excerpt":null,"startOffset":\#(offsets.0.map(String.init) ?? "null"),"title":"Week","url":"https://example.com/week"}]"#
                )
                    == true)
        }
    }
}
