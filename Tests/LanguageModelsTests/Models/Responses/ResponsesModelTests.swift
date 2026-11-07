import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

@Suite("Responses model")
struct ResponsesModelTests {
    @Test func `a request goes to responses, and its answer streams back`() async throws {
        let stub = HTTPStub(events(textDelta("Hi"), lifecycle("response.completed")))

        let (answer, failure) = await respond(stub, to: [prompt(text("Hello"))])

        if let failure { Issue.record("The answer failed: \(failure)") }
        #expect(answer?.responseText == "Hi")
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

    @Test func `a plain model throws a failure as it is`() async {
        let stub = HTTPStub(.json(#"{"error":{"message":"Bad key."}}"#, status: 401))

        await #expect(throws: RequestFailure<APIErrorBody>.self) {
            _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")
        }
    }

    @Test func `a plain model holds an answer to its schema's guides`() async {
        let stub = HTTPStub(events(textDelta(#"{"stars":9}"#), lifecycle("response.completed")))

        await #expect(throws: GeneratedContent.ParsingError.self) {
            _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)
        }
    }

    @Test func `a model keeps a report of each model a request may reach that its provider stopped listing`() {
        let model = Responses.Model(
            name: "vendor/model", url: URL(fileURLWithPath: "/"), connection: Responses.Model<ResponsesTestExchange>.test().connection,
            providerName: "Test", capabilities: LanguageModelCapabilities([]),
            reaching: [Reached(removalDate: nil), Reached(removalDate: .distantPast)], exchange: ResponsesTestExchange())

        #expect(model.removedModels.count == 1)
    }

    @Test func `a stream that ends before the response completes is cut off, even after a done`() async {
        let stub = HTTPStub(.eventStream(Data("data: \(textDelta("Hi").text)\n\ndata: [DONE]\n\n".utf8)))

        let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

        guard case .unusableAnswer? = failure?.kind, failure?.message == "The response ended before it was complete." else {
            Issue.record("The answer ended with \(String(describing: failure))")
            return
        }
    }

    @Test(
        arguments: [
            ["type": "error", "code": "server_error", "message": "Overloaded.", "param": nil, "sequence_number": 2],
            ["type": "error", "sequence_number": 2, "error": ["type": "server_error", "code": "server_error", "message": "Overloaded."]],
        ] as [JSONValue])
    func `an error event mid-stream fails the answer with its error, flat or nested`(event: JSONValue) async {
        let stub = HTTPStub(events(textDelta("Hi"), event))

        let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

        guard case .errorEvent? = failure?.kind, let error = failure?.body else {
            Issue.record("The answer ended with \(String(describing: failure))")
            return
        }
        #expect(error.message == "Overloaded.")
        #expect(error.code == "server_error")
    }

    @Test func `a failed response fails the answer with the response's error`() async {
        let stub = HTTPStub(
            events(textDelta("Hi"), lifecycle("response.failed", ["error": ["code": "rate_limit_exceeded", "message": "Slow down."]])))

        let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

        guard case .failedAnswer? = failure?.kind else {
            Issue.record("The answer ended with \(String(describing: failure))")
            return
        }
        let error = failure?.body
        #expect(error?.message == "Slow down.")
        #expect(error?.code == "rate_limit_exceeded")
    }

    @Test func `a failed response's error object names what went wrong`() async {
        let stub = HTTPStub(
            .json(#"{"error":{"message":"Bad key.","type":"invalid_request_error","code":"invalid_api_key"}}"#, status: 401))

        let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

        guard case .rejected? = failure?.kind, let rejection = failure else {
            Issue.record("The answer ended with \(String(describing: failure))")
            return
        }
        #expect(rejection.status == 401)
        #expect(rejection.body?.message == "Bad key.")
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

    @Test func `a refusal fails the answer as Foundation Models' refusal`() async {
        let refusal: JSONValue = ["type": "response.refusal.delta", "output_index": 0, "content_index": 0, "delta": "I can't."]
        let stub = HTTPStub(events(refusal, lifecycle("response.completed")))

        let (_, error) = await respondThrowing(stub, to: [prompt(text("Hello"))])

        guard case .refusal? = error as? LanguageModelError else {
            Issue.record("The answer ended with \(String(describing: error))")
            return
        }
    }

    @Test func `an answer a content filter stopped fails as a guardrail violation`() async {
        let stub = HTTPStub(events(textDelta("Hi"), lifecycle("response.incomplete", ["incomplete_details": ["reason": "content_filter"]])))

        let (_, error) = await respondThrowing(stub, to: [prompt(text("Hello"))])

        guard case .guardrailViolation? = error as? LanguageModelError else {
            Issue.record("The answer ended with \(String(describing: error))")
            return
        }
    }

    @Test func `an answer whose token limit cuts off a function call fails`() async {
        let stub = HTTPStub(
            events(
                item(
                    "response.output_item.added", at: 0, ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": ""]),
                ["type": "response.function_call_arguments.delta", "output_index": 0, "delta": #"{"word""#],
                lifecycle("response.incomplete", ["incomplete_details": ["reason": "max_output_tokens"]])))

        let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

        guard case .unusableAnswer? = failure?.kind, failure?.message == "The answer reached its token limit inside a tool call." else {
            Issue.record("The answer ended with \(String(describing: failure))")
            return
        }
    }

    @Test func `a failed response without an error object fails the answer all the same`() async {
        let stub = HTTPStub(events(textDelta("Hi"), lifecycle("response.failed", ["status": "failed"])))

        let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

        guard case .failedAnswer? = failure?.kind, failure?.body == nil else {
            Issue.record("The answer ended with \(String(describing: failure))")
            return
        }
    }

    @Test func `an event of a kind the format doesn't read is passed over, whatever its shape`() async {
        let shell: JSONValue = ["type": "response.shell_call_output_content.delta", "output_index": 0, "delta": ["stdout": "ok"]]
        let stub = HTTPStub(events(shell, textDelta("Hi"), lifecycle("response.completed")))

        let (answer, failure) = await respond(stub, to: [prompt(text("Hello"))])

        if let failure { Issue.record("The answer failed: \(failure)") }
        #expect(answer?.responseText == "Hi")
    }

    @Test func `function call arguments without an output index go to the last call`() async {
        let stub = HTTPStub(
            events(
                item(
                    "response.output_item.added", at: 0, ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": ""]),
                ["type": "response.function_call_arguments.delta", "delta": #"{"word":"egg"}"#],
                [
                    "type": "response.output_item.done",
                    "item": ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": #"{"word":"egg"}"#],
                ],
                lifecycle("response.completed")))

        let (answer, failure) = await respond(stub, to: [prompt(text("Hello"))])

        if let failure { Issue.record("The answer failed: \(failure)") }
        #expect(answer?.responseText == "")
    }
}

@Suite("Responses stream")
struct ResponsesStreamTests {
    @Test func `reasoning summaries, the reasoning item, text, citations, usage and the finish reason end up in the transcript`() async {
        let reasoningItem: JSONValue = [
            "type": "reasoning", "id": "rs_1", "encrypted_content": "blob",
            "summary": [["type": "summary_text", "text": "Count."], ["type": "summary_text", "text": "Seven."]],
        ]
        let summary = { (index: Int, delta: String) -> JSONValue in
            ["type": "response.reasoning_summary_text.delta", "output_index": 0, "summary_index": .integer(index), "delta": .string(delta)]
        }
        let citation: JSONValue = [
            "type": "response.output_text.annotation.added", "output_index": 1, "content_index": 0, "annotation_index": 0,
            "annotation": ["type": "url_citation", "url": "https://example.com/week", "title": "Week", "start_index": 0, "end_index": 5],
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

    @Test func `parallel function calls form one round, with arguments that stream or arrive whole, and go back with their outputs`() async
    {
        let stub = HTTPStub(
            events(
                item(
                    "response.output_item.added", at: 0, ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": ""]),
                ["type": "response.function_call_arguments.delta", "output_index": 0, "delta": #"{"word""#],
                item(
                    "response.output_item.added", at: 1, ["type": "function_call", "call_id": "call_2", "name": "lookUp", "arguments": ""]),
                ["type": "response.function_call_arguments.delta", "output_index": 0, "delta": #":"egg"}"#],
                item(
                    "response.output_item.done", at: 0,
                    ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": #"{"word":"egg"}"#]),
                item(
                    "response.output_item.done", at: 1,
                    ["type": "function_call", "call_id": "call_2", "name": "lookUp", "arguments": #"{"word":"rice"}"#]),
                lifecycle("response.completed")),
            events(textDelta("Both found."), lifecycle("response.completed")))

        let exchange = await ExactExchange(
            stub, LanguageModelSession(model: model(stub), tools: [LookUpTool()]), recordingHeaders: /^X-/
        ) { session, _ in
            try await session.respond(to: "Define egg and rice.").usage
        }

        #expect(exchange.error == nil)
        #expect(
            exchange.transcript.dropFirst(2).first
                == #"toolCalls ["call_1 lookUp {\"word\":\"egg\"} metadata: {\"finishReason\":\"tool_calls\"}", "call_2 lookUp {\"word\":\"rice\"} metadata: {}"]"#
        )
        #expect(exchange.bodies.count == 2)
        #expect(
            exchange.bodies.last?.contains(
                #"{"type":"function_call","call_id":"call_1","name":"lookUp","arguments":"{\"word\":\"egg\"}"},{"type":"function_call","call_id":"call_2","name":"lookUp","arguments":"{\"word\":\"rice\"}"},{"type":"function_call_output","call_id":"call_1","output":"egg"},{"type":"function_call_output","call_id":"call_2","output":"rice"}"#
            ) == true)
    }

    @Test func `a commentary and a final answer keep their own phases, and reasoning text shows as reasoning`() async {
        let reasoningText: JSONValue = [
            "type": "response.reasoning_text.delta", "output_index": 0, "content_index": 0, "delta": "Think.",
        ]
        let stub = HTTPStub(
            events(
                item("response.output_item.added", at: 0, ["type": "reasoning", "id": "rs_1", "summary": []]), reasoningText,
                item("response.output_item.done", at: 0, ["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "blob"]),
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

    @Test func `reasoning items that came between messages and calls go back in their places`() async {
        let stub = HTTPStub(
            events(
                item("response.output_item.added", at: 0, ["type": "reasoning", "id": "rs_1", "summary": []]),
                item("response.output_item.done", at: 0, ["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "a"]),
                item("response.output_item.added", at: 1, ["type": "message", "id": "msg_1", "phase": "commentary"]),
                textDelta("Checking.", at: 1),
                item("response.output_item.done", at: 1, ["type": "message", "id": "msg_1", "phase": "commentary"]),
                item("response.output_item.added", at: 2, ["type": "reasoning", "id": "rs_2", "summary": []]),
                item("response.output_item.done", at: 2, ["type": "reasoning", "id": "rs_2", "summary": [], "encrypted_content": "b"]),
                item(
                    "response.output_item.added", at: 3, ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": ""]),
                item(
                    "response.output_item.done", at: 3,
                    ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": #"{"word":"egg"}"#]),
                lifecycle("response.completed")),
            events(textDelta("Done."), lifecycle("response.completed")))

        let exchange = await ExactExchange(
            stub, LanguageModelSession(model: model(stub), tools: [LookUpTool()]), recordingHeaders: /^X-/
        ) { session, _ in
            try await session.respond(to: "Define egg.").usage
        }

        #expect(exchange.error == nil)
        #expect(
            exchange.transcript[2].hasSuffix(
                #"signature: "[{\"encrypted_content\":\"a\",\"id\":\"rs_1\",\"summary\":[],\"type\":\"reasoning\"},{\"type\":\"message\"},{\"encrypted_content\":\"b\",\"id\":\"rs_2\",\"summary\":[],\"type\":\"reasoning\"},{\"type\":\"function_call\"}]""#
            ))
        #expect(
            exchange.bodies.last?.contains(
                #"{"role":"user","content":"Define egg."},{"encrypted_content":"a","id":"rs_1","summary":[],"type":"reasoning"},{"role":"assistant","content":"Checking.","phase":"commentary"},{"encrypted_content":"b","id":"rs_2","summary":[],"type":"reasoning"},{"type":"function_call","call_id":"call_1","name":"lookUp","arguments":"{\"word\":\"egg\"}"},{"type":"function_call_output","call_id":"call_1","output":"egg"}"#
            ) == true)
    }

    @Test func `text in reasoning tags stays the answer's text, since the format has reasoning of its own`() async {
        let stub = HTTPStub(
            events(
                item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1", "phase": "final_answer"]),
                textDelta("<think>Tags.</think>", at: 0), textDelta("Answer.", at: 0), lifecycle("response.completed")))

        let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
            try await session.respond(to: "Start with the tag.").usage
        }

        #expect(exchange.error == nil)
        #expect(
            exchange.transcript.last
                == #"response ["<think>Tags.</think>Answer."] metadata: {"finishReason":"stop","test.phases":[{"length":27,"phase":"final_answer"}]}"#
        )
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
            "annotation": ["type": "url_citation", "url": "https://example.com/week", "title": "Week", "start_index": 0, "end_index": 5],
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
}

/// The test model, sending to a stub.
private func model(_ stub: HTTPStub) -> Responses.Model<ResponsesTestExchange> {
    .test(url: stub.baseURL, session: stub.session)
}

/// A model a request may reach.
private struct Reached: ModelDetails {
    let id: ResponsesTestModelID = "vendor/model"
    let displayName = "Model"
    let capabilities = LanguageModelCapabilities([])
    let reasoning = ModelReasoning.unsupported
    let contextSize: Int? = nil
    let reasoningEfforts: [Efforts.Unsupported] = []
    let defaultReasoningEffort: Efforts.Unsupported? = nil
    let removalDate: Date?
    let dataAttachmentTypes: Set<UTType> = []
    let dataEntryTypes: Set<UTType> = []
}

/// The id of a model a request may reach.
private struct ResponsesTestModelID: ProviderVocabulary {
    let rawValue: String
}

/// A model of the plain format, sending to a stub.
private func plainModel(_ stub: HTTPStub) -> Responses.Model<Responses.PlainExchange> {
    var model = Responses.Model(name: "vendor/model", url: stub.baseURL)
    model.connection = Connection(
        session: stub.session, authentication: .unauthenticated, idleTimeout: nil, retries: .disabled, retrying: { _ in false })
    return model
}

/// Runs one exchange of the test model with a stub, reading the channel's events without looking at them, since a
/// channel waits for its reader.
///
/// - Returns: The answer, or the failure it ended in.
private func respond(
    _ stub: HTTPStub,
    to entries: [Transcript.Entry],
    schema: GenerationSchema? = nil
) async -> (DetailedLanguageModelAnswer?, RequestFailure<APIErrorBody>?) {
    let (answer, error) = await respondThrowing(stub, to: entries, schema: schema)
    guard let error else { return (answer, nil) }
    guard let failure = error as? RequestFailure<APIErrorBody> else {
        Issue.record("The model threw \(error)")
        return (nil, nil)
    }
    return (nil, failure)
}

/// Runs one exchange of the test model with a stub.
///
/// - Returns: The answer, or the error it ended in.
private func respondThrowing(
    _ stub: HTTPStub,
    to entries: [Transcript.Entry],
    schema: GenerationSchema? = nil
) async -> (DetailedLanguageModelAnswer?, (any Error)?) {
    let channel = LanguageModelExecutorGenerationChannel()
    let reader = Task { for try await _ in channel {} }
    defer { reader.cancel() }
    do {
        let text = try await model(stub).run(generationRequest(entries, schema: schema), streamingInto: channel)
        return (DetailedLanguageModelAnswer(responseText: text), nil)
    } catch {
        return (nil, error)
    }
}
