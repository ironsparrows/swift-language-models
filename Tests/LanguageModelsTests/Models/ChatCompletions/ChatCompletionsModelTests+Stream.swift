import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

/// A `url_citation` annotation as a chunk carries it.
private func citation(
    _ url: String?,
    title: String? = nil,
    content: String? = nil,
    start: Int? = nil,
    end: Int? = nil
) -> JSONValue {
    let fields: JSONValue = [
        "url": url.map(JSONValue.string), "title": title.map(JSONValue.string), "content": content.map(JSONValue.string),
        "start_index": start.map(JSONValue.integer), "end_index": end.map(JSONValue.integer),
    ]
    return ["type": "url_citation", "url_citation": fields]
}

/// A chunk of annotations.
private func annotations(_ annotations: JSONValue...) -> JSONValue {
    ["choices": [["delta": ["annotations": .array(annotations)]]]]
}

/// The citations of each response entry in a transcript.
private func citations(_ entries: some Sequence<Transcript.Entry>) -> [[Citation]] {
    entries.compactMap { entry in
        guard case .response(let response) = entry else { return nil }
        return response.providerMetadata.citations
    }
}

extension ChatCompletionsModelTests {
    @Suite("Stream")
    struct Stream {
        @Test func `a request goes to chat/completions with the provider's headers, and its answer streams back`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(["choices": [["delta": ["content": "Hi"]]]], ["choices": [["delta": [:], "finish_reason": "stop"]]]))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hello")

            #expect(response.content == "Hi")
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
                        "id": "gen-2", "model": "vendor/model-2026-10-01",
                        "choices": [["delta": [:], "finish_reason": "length"]],
                        "usage": ["prompt_tokens": 12, "completion_tokens": 5, "prompt_tokens_details": ["cache_write_tokens": 3]],
                    ],
                    ["choices": [["delta": [:]]]]))

            let exchange = await answer(stub)

            #expect(exchange.error == nil)
            #expect(
                exchange.transcript.last
                    == #"response [""] metadata: {"cacheWriteTokenCount":3,"finishReason":"length","model":"vendor/model-2026-10-01","responseID":"gen-2","serviceTier":"flex"}"#
            )
            #expect(exchange.usage == #"input 12 cached 0, output 5 reasoning 0, metadata: {"cacheWriteTokenCount":3}"#)
        }

        @Test(arguments: [
            (false, 1184, "output 290 reasoning 4"),
            (true, 1184, "output 1169 reasoning 883"),
            (true, 300, "output 290 reasoning 4"),
            (true, nil, "output 290 reasoning 4"),
        ])
        func `a usage's tokens beyond the prompt and the completion count as reasoning only for a model that says so`(
            counts: Bool, totalTokens: Int?, output: String
        ) async {
            let usage: JSONValue = [
                "prompt_tokens": 15, "completion_tokens": 290, "total_tokens": totalTokens.map(JSONValue.integer),
                "completion_tokens_details": ["reasoning_tokens": 4],
            ]
            let stub = HTTPStub(chatCompletionsEvents(textChunk("Hi"), finishChunk(usage: usage)))
            var model = plainModel(stub)
            model.countsUnlistedTokensAsReasoning = counts

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "Hello").usage
            }

            #expect(exchange.error == nil)
            #expect(exchange.usage == "input 15 cached 0, \(output), metadata: {}")
        }

        @Test func `a usage's total that isn't a whole number is passed over`() async {
            let usage: JSONValue = ["prompt_tokens": 15, "completion_tokens": 290, "total_tokens": "1184"]
            let stub = HTTPStub(chatCompletionsEvents(textChunk("Hi"), finishChunk(usage: usage)))

            let exchange = await answer(stub)

            #expect(exchange.error == nil)
            #expect(exchange.usage == "input 15 cached 0, output 290 reasoning 0, metadata: {}")
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

        @Test func `a stream that ends with a finish reason but no [DONE] is complete`() async throws {
            let stub = HTTPStub(.eventStream(Data("data: \(textChunk("Hi", finishReason: "stop").text)\n\n".utf8)))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")

            #expect(response.content == "Hi")
        }

        @Test func `a snapshot arrives while the answer still streams`() async throws {
            // Foundation Models yields no snapshot until a few chunks have arrived, and how many each one holds depends
            // on timing.
            let lines = ["One", " two", " three", " four", " five", " six"].map { "data: \(textChunk($0).text)\n\n" }.joined()
            let stub = HTTPStub(StubResponse.eventStream(Data(lines.utf8)).keepingConnectionOpen())
            let session = LanguageModelSession(model: plainModel(stub))

            try await confirmation { snapshotArrived in
                for try await snapshot in session.streamResponse(to: "Count.") {
                    #expect(snapshot.content.hasPrefix("One"))
                    snapshotArrived()
                    break
                }
            }
        }

        @Test func `a stream's last snapshot is the whole answer`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("One"), textChunk(" two"), textChunk(" three", finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub))

            var last: String?
            for try await snapshot in session.streamResponse(to: "Count.") { last = snapshot.content }

            #expect(last == "One two three")
        }

        @Test func `cited pages reach the response entry once each, and don't go back`() async throws {
            let full = citation(
                "https://swift.org/blog/swift-6.4", title: "Swift 6.4 Released", content: "Swift 6.4 is now available.\n[...]\nMore.",
                start: 0, end: 18)
            let stub = HTTPStub(
                chatCompletionsEvents(
                    textChunk("Swift 6.4 is out. "),
                    annotations(full, ["type": "file", "file": ["hash": "abc", "name": "notes.pdf"]]),
                    textChunk("It ships with Xcode 27.2."),
                    annotations(full, citation("https://developer.apple.com/xcode/"), citation(nil, title: "No address")),
                    finishChunk()),
                chatCompletionsEvents(textChunk("Yes.", finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub))

            let response = try await session.respond(to: "What's new in Swift?")
            _ = try await session.respond(to: "Sure?")

            #expect(
                citations(response.transcriptEntries).last == [
                    Citation(
                        url: try #require(URL(string: "https://swift.org/blog/swift-6.4")), title: "Swift 6.4 Released",
                        excerpt: "Swift 6.4 is now available.\n[...]\nMore.", startOffset: 0, endOffset: 18),
                    Citation(url: try #require(URL(string: "https://developer.apple.com/xcode/"))),
                ]
            )
            let assistant = try #require(try assistantMessages(stub, request: 1).first)
            #expect(assistant == ["content": "Swift 6.4 is out. It ships with Xcode 27.2.", "role": "assistant"])
        }

        @Test func `citations stay on the response entry when the answer ends in tool calls`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    textChunk("Eggs are light, says the USDA. "),
                    annotations(citation("https://fdc.nal.usda.gov/", title: "FoodData Central")),
                    toolCallChunk(0, id: "call_1", name: "lookUp", arguments: #"{"word":"egg"}"#),
                    finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("An egg has 100 kcal.", finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])

            let response = try await session.respond(to: "Calories in an egg?")

            let answers = citations(response.transcriptEntries)
            try #require(answers.count == 2)
            #expect(answers[0].map(\.title) == ["FoodData Central"])
            #expect(answers[1].isEmpty)
        }

        @Test func `content in parts is the answer's text and, inside thinking parts, its reasoning, and other parts are passed over`()
            async throws
        {
            let thinking: JSONValue = [
                "choices": [
                    [
                        "delta": [
                            "content": [
                                [
                                    "type": "thinking",
                                    "thinking": [["type": "text", "text": "Think"], ["type": "reference", "reference_ids": [1]]],
                                ],
                                ["type": "thinking", "thinking": [["type": "text", "text": "ing."]], "signature": "c2ln", "closed": true],
                            ]
                        ]
                    ]
                ]
            ]
            let answer: JSONValue = [
                "choices": [
                    [
                        "delta": [
                            "content": [
                                ["type": "text", "text": "Hi"], ["type": "tool_reference", "tool": "web_search", "title": "Swift"],
                                ["type": "image_url", "image_url": "https://example.com/cat.png"], ["type": "new_kind"],
                                ["text": "Untyped."],
                                "Loose text.",
                            ]
                        ]
                    ]
                ]
            ]
            let stub = HTTPStub(chatCompletionsEvents(thinking, answer, textChunk(" there.", finishReason: "stop")))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")

            #expect(response.content == "Hi there.")
            #expect(reasoningTexts(response.transcriptEntries) == ["Thinking."])
        }

        @Test func `a refusal that isn't text is no refusal`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(["choices": [["delta": ["content": "Hi", "refusal": false], "finish_reason": "stop"]]]))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")

            #expect(response.content == "Hi")
        }

        @Test func `an event named ping is passed over, whatever its data holds`() async throws {
            let lines = [
                "event: ping\ndata: keep-alive", "data: \(textChunk("Hi").text)", "event: ping\ndata: {}", "data: \(finishChunk().text)",
            ]
            let stub = HTTPStub(.eventStream(Data(lines.map { $0 + "\n\n" }.joined().utf8)))

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")

            #expect(response.content == "Hi")
        }
    }
}
