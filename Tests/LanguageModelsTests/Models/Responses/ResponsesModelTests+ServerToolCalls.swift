import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Server tool calls")
    struct ServerToolCalls {
        @Test func `kept calls go back between the reasoning items, in the places they came`() async throws {
            let stub = HTTPStub(
                events(
                    done(0, reasoning("rs_1")), done(1, search("ws_1")), done(2, reasoning("rs_2")), done(3, search("ws_2")),
                    done(4, reasoning("rs_3")), textDelta("Found.", at: 5), lifecycle("response.completed")),
                events(textDelta("Done."), lifecycle("response.completed")))
            let exchange = await ExactExchange(
                stub, LanguageModelSession(model: modelKeeping(stub: stub, [.webSearch])), recordingHeaders: /^X-/
            ) {
                session, _ in
                try await session.respond(to: "Search twice.")
                return try await session.respond(to: "Again.").usage
            }

            #expect(exchange.error == nil)
            #expect(
                reasoningLine(exchange).hasSuffix(
                    #"signature: "[{\"encrypted_content\":\"blob\",\"id\":\"rs_1\",\"summary\":[],\"type\":\"reasoning\"},{\"type\":\"web_search_call\"},{\"encrypted_content\":\"blob\",\"id\":\"rs_2\",\"summary\":[],\"type\":\"reasoning\"},{\"type\":\"web_search_call\"},{\"encrypted_content\":\"blob\",\"id\":\"rs_3\",\"summary\":[],\"type\":\"reasoning\"},{\"type\":\"message\"}]""#
                ))
            let sent = try input(JSONValue(json: Data(#require(exchange.bodies.last).utf8)))
            #expect(
                sent == [
                    ["role": "user", "content": "Search twice."], reasoning("rs_1"), search("ws_1"), reasoning("rs_2"), search("ws_2"),
                    reasoning("rs_3"), ["role": "assistant", "content": "Found."], ["role": "user", "content": "Again."],
                ])
        }

        @Test func `an image's call keeps its place after reasoning that came first`() async throws {
            // Without an image, so the test model, which takes no data entries, can answer.
            let call: JSONValue = ["type": "image_generation_call", "id": "ig_1", "status": "completed", "result": JSONValue.null]
            let stub = HTTPStub(
                events(done(0, reasoning("rs_1")), done(1, call), textDelta("No image.", at: 2), lifecycle("response.completed")),
                events(textDelta("Done."), lifecycle("response.completed")))
            let exchange = await ExactExchange(
                stub, LanguageModelSession(model: modelKeeping(stub: stub, [.imageGeneration])), recordingHeaders: /^X-/
            ) { session, _ in
                try await session.respond(to: "Draw.")
                return try await session.respond(to: "Again.").usage
            }

            #expect(exchange.error == nil)
            #expect(reasoningLine(exchange).hasSuffix(#"{\"type\":\"image_generation_call\"},{\"type\":\"message\"}]""#))
            let sent = try input(JSONValue(json: Data(#require(exchange.bodies.last).utf8)))
            #expect(Array(sent[1...2]) == [reasoning("rs_1"), call])
        }

        @Test func `the call of a kind the request doesn't keep is passed over`() async throws {
            let stub = HTTPStub(
                events(done(0, reasoning("rs_1")), done(1, search("ws_1")), textDelta("Found.", at: 2), lifecycle("response.completed")))
            let exchange = await ExactExchange(
                stub, LanguageModelSession(model: modelKeeping(stub: stub, [.fileSearch])), recordingHeaders: /^X-/
            ) {
                session, _ in
                try await session.respond(to: "Search.").usage
            }

            #expect(exchange.error == nil)
            #expect(reasoningLine(exchange).hasSuffix(#"\"type\":\"reasoning\"}]""#))
            #expect(exchange.transcript.last?.contains("test.serverTools") == false)
        }

        @Test func `kept calls go in the metadata in the order of their places, whatever order they ended in`() async throws {
            let stub = HTTPStub(
                events(
                    done(0, reasoning("rs_1")), done(3, search("ws_2")), done(1, search("ws_1")), done(2, reasoning("rs_2")),
                    textDelta("Found.", at: 4), lifecycle("response.completed")))
            let exchange = await ExactExchange(
                stub, LanguageModelSession(model: modelKeeping(stub: stub, [.webSearch])), recordingHeaders: /^X-/
            ) {
                session, _ in
                try await session.respond(to: "Search twice.").usage
            }

            let response = try #require(exchange.transcript.first { $0.hasPrefix("response ") })
            let first = try #require(response.range(of: #"\"id\":\"ws_1\""#))
            let second = try #require(response.range(of: #"\"id\":\"ws_2\""#))
            #expect(first.lowerBound < second.lowerBound)
        }

        @Test func `a cited file keeps its place in the answer's text, once, only while the request keeps file searches`() async throws {
            func respond(keeping calls: Set<Responses.ServerToolCall>) async -> ExactExchange {
                let stub = HTTPStub(
                    events(
                        textDelta("Plan: ", at: 0), textDelta("see the menu.", at: 1),
                        annotation(at: 1, ["type": "file_citation", "file_id": "file_1", "filename": "menu.pdf", "index": 13]),
                        annotation(at: 1, ["type": "file_citation", "file_id": "file_1", "filename": "menu.pdf", "index": 13]),
                        lifecycle("response.completed")))
                return await ExactExchange(stub, LanguageModelSession(model: modelKeeping(stub: stub, calls)), recordingHeaders: /^X-/) {
                    session, _ in
                    try await session.respond(to: "What's for dinner?").usage
                }
            }

            let kept = await respond(keeping: [.fileSearch])
            let passedOver = await respond(keeping: [])

            #expect(
                kept.transcript.last?.contains(
                    #""test.serverTools":{"fileCitations":[{"fileID":"file_1","filename":"menu.pdf","offset":19}]}"#) == true)
            #expect(passedOver.transcript.last?.contains("test.serverTools") == false)
        }

        @Test(arguments: [(2, #""webSearchCount":2"#), (0, nil)] as [(Int, String?)])
        func `the web searches a response reports fill the usage's count, and none add nothing`(
            searches: Int, count: String?
        ) async throws {
            let usage: JSONValue = ["input_tokens": 9, "output_tokens": 3]
            let stub = HTTPStub(
                events(
                    textDelta("Found."),
                    lifecycle(
                        "response.completed",
                        [
                            "usage": usage,
                            "tool_usage": ["web_search": ["num_requests": .integer(searches)], "image_gen": ["input_tokens": 0]],
                        ])))
            let exchange = await ExactExchange(stub, LanguageModelSession(model: modelKeeping(stub: stub, [])), recordingHeaders: /^X-/) {
                session, _ in
                try await session.respond(to: "Search.").usage
            }

            let usageLine = try #require(exchange.usage)
            #expect(usageLine.contains("webSearchCount") == (count != nil))
            if let count { #expect(usageLine.contains(count)) }
        }

        @Test func `a tool usage, a storage or a cited file's member of another shape leaves the answer readable`() async throws {
            let stub = HTTPStub(
                events(
                    textDelta("Found."), annotation(at: 0, ["type": "file_citation", "file_id": 7, "index": "start"]),
                    lifecycle(
                        "response.completed", ["usage": ["input_tokens": 9, "output_tokens": 3], "tool_usage": "none", "store": "yes"])))
            let exchange = await ExactExchange(
                stub, LanguageModelSession(model: modelKeeping(stub: stub, [.fileSearch])), recordingHeaders: /^X-/
            ) { session, _ in
                try await session.respond(to: "Search.").usage
            }

            #expect(exchange.error == nil)
            #expect(exchange.transcript.last?.hasPrefix(#"response ["Found."]"#) == true)
            #expect(exchange.transcript.last?.contains("test.serverTools") == false)
        }

        @Test func `without reasoning, an answer's calls go back before its messages`() throws {
            let entries: [Transcript.Entry] = [
                prompt(text("Search.")),
                .response(Transcript.Response(metadata: kept(search("ws_1")), segments: [text("Found.")])),
            ]

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: modelKeeping([.webSearch])).body)

            #expect(sent == [["role": "user", "content": "Search."], search("ws_1"), ["role": "assistant", "content": "Found."]])
        }

        @Test func `reasoning that doesn't go back takes the calls it placed with it`() throws {
            let other = Transcript.Reasoning(
                metadata: ["reasoningOrigin": "another-responses"], segments: [],
                signature: JSONValue.array([reasoning("rs_1"), ["type": "web_search_call"]]).data)
            let entries: [Transcript.Entry] = [
                prompt(text("Search.")), .reasoning(other),
                .response(Transcript.Response(metadata: kept(search("ws_1")), segments: [text("Found.")])),
            ]

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: modelKeeping([.webSearch])).body)

            #expect(sent == [["role": "user", "content": "Search."], ["role": "assistant", "content": "Found."]])
        }

        @Test func `an answer that is only a call still sends its reasoning back, since the call follows it`() throws {
            let call: JSONValue = ["type": "image_generation_call", "id": "ig_1", "status": "completed", "result": JSONValue.null]
            let entries: [Transcript.Entry] = [
                prompt(text("Draw.")), reasoningEntry(reasoning("rs_1"), ["type": "image_generation_call"]),
                .response(Transcript.Response(metadata: kept(call), segments: [])), prompt(text("Again.")),
            ]

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: modelKeeping([.imageGeneration])).body)

            #expect(sent == [["role": "user", "content": "Draw."], reasoning("rs_1"), call, ["role": "user", "content": "Again."]])
        }

        @Test func `reasoning after the call of an answer that is only an image stays out, since nothing follows it`() throws {
            let call: JSONValue = ["type": "image_generation_call", "id": "ig_1", "status": "completed", "result": JSONValue.null]
            let entries: [Transcript.Entry] = [
                prompt(text("Draw.")), reasoningEntry(["type": "image_generation_call"], reasoning("rs_1"), ["type": "message"]),
                .response(Transcript.Response(metadata: kept(call), segments: [])), prompt(text("Again.")),
            ]

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: modelKeeping([.imageGeneration])).body)

            #expect(sent == [["role": "user", "content": "Draw."], call, ["role": "user", "content": "Again."]])
        }

        @Test func `an answer that ends in tool calls keeps its server tools' calls on its first call`() throws {
            let toolCall = Transcript.ToolCall(
                id: "call_1", metadata: kept(search("ws_1")), toolName: "lookUp", arguments: GeneratedContent(properties: ["word": "egg"]))
            let entries: [Transcript.Entry] = [prompt(text("Define egg.")), .toolCalls(Transcript.ToolCalls([toolCall]))]

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: modelKeeping([.webSearch])).body)

            #expect(sent[1] == search("ws_1"))
            #expect(sent[2]["type"] == "function_call")
        }

        @Test(arguments: [
            Replayed(calls: [.webSearch, .imageGeneration], storage: .automatic, ids: ["rs_1", "ws_1", "rs_2", "ig_1", "rs_3"]),
            Replayed(calls: [.webSearch, .imageGeneration], storage: .notStored, ids: ["rs_1", "ws_1", "rs_3"]),
            Replayed(calls: [.imageGeneration], storage: .automatic, ids: ["rs_2", "ig_1", "rs_3"]),
            Replayed(calls: [], storage: .stored, ids: ["rs_3"]),
        ])
        func `a call goes back while the request keeps its kind, an image's only when stored, and with the reasoning before it`(
            replayed: Replayed
        ) throws {
            let image: JSONValue = ["type": "image_generation_call", "id": "ig_1", "status": "completed", "result": JSONValue.null]
            let entries: [Transcript.Entry] = [
                prompt(text("Search, then draw.")),
                reasoningEntry(
                    reasoning("rs_1"), ["type": "web_search_call"], reasoning("rs_2"), ["type": "image_generation_call"], reasoning("rs_3"),
                    ["type": "message"]),
                .response(Transcript.Response(metadata: kept(search("ws_1"), image), segments: [text("Here.")])),
            ]
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { request in
                request.serverToolCalls = replayed.calls
                request.storage = replayed.storage
            }

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: model).body)

            #expect(sent.compactMap { $0["id"]?.stringValue } == replayed.ids)
            #expect(sent.last == ["role": "assistant", "content": "Here."])
        }

        @Test func `a call that didn't complete stays out, and so does the reasoning before it`() throws {
            let failed: JSONValue = ["type": "web_search_call", "id": "ws_1", "status": "failed", "action": ["type": "search"]]
            // A call that names no status counts as completed.
            let unnamed: JSONValue = ["type": "web_search_call", "id": "ws_3", "action": ["type": "search"]]
            let entries: [Transcript.Entry] = [
                prompt(text("Search three times.")),
                reasoningEntry(
                    reasoning("rs_1"), ["type": "web_search_call"], reasoning("rs_2"), ["type": "web_search_call"], reasoning("rs_3"),
                    ["type": "web_search_call"], ["type": "message"]),
                .response(Transcript.Response(metadata: kept(failed, search("ws_2"), unnamed), segments: [text("Found.")])),
            ]

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: modelKeeping([.webSearch])).body)

            #expect(sent.compactMap { $0["id"]?.stringValue } == ["rs_2", "ws_2", "rs_3", "ws_3"])
        }

        @Test func `an image's call from a response the provider didn't keep stays out, and a search's goes back`() throws {
            let image: JSONValue = ["type": "image_generation_call", "id": "ig_1", "status": "completed", "result": JSONValue.null]
            let unstored = GeneratedContent(properties: ["calls": [search("ws_1").text, image.text], "unstored": true])
            let entries: [Transcript.Entry] = [
                prompt(text("Search, then draw.")),
                reasoningEntry(
                    reasoning("rs_1"), ["type": "web_search_call"], reasoning("rs_2"), ["type": "image_generation_call"],
                    ["type": "message"]),
                .response(Transcript.Response(metadata: ["test.serverTools": unstored], segments: [text("Here.")])),
            ]
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { request in
                request.serverToolCalls = [.webSearch, .imageGeneration]
                request.storage = .stored
            }

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: model).body)

            #expect(sent.compactMap { $0["id"]?.stringValue } == ["rs_1", "ws_1"])
        }

        @Test func `to a provider that doesn't keep the response, a call goes back only with all the reasoning before it`() throws {
            let entries: [Transcript.Entry] = [
                prompt(text("Search twice.")),
                reasoningEntry(
                    reasoning("rs_1", encrypted: nil), ["type": "web_search_call"], reasoning("rs_2"), ["type": "web_search_call"],
                    ["type": "message"]),
                .response(Transcript.Response(metadata: kept(search("ws_1"), search("ws_2")), segments: [text("Found.")])),
            ]
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { request in
                request.serverToolCalls = [.webSearch]
                request.storage = .notStored
            }

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: model).body)

            #expect(sent.compactMap { $0["id"]?.stringValue } == ["rs_2", "ws_2"])
        }
    }
}

/// The kinds of call a request keeps, the storage it asks for, and the ids of the items its input sends.
struct Replayed: Sendable, CustomTestStringConvertible {
    let calls: Set<Responses.ServerToolCall>
    let storage: Responses.Request.Storage
    let ids: [String]

    var testDescription: String {
        "\(calls.count) kinds, \(storage)"
    }
}

/// The test model, keeping the calls of these kinds, sending to a stub when one is given.
private func modelKeeping(stub: HTTPStub? = nil, _ calls: Set<Responses.ServerToolCall>) -> Responses.Model<ResponsesTestExchange> {
    var model = stub.map { ResponsesModelTests.model($0) } ?? .test()
    model.exchange.prepares = { $0.serverToolCalls = calls }
    return model
}

/// The transcript line of an exchange's first reasoning entry.
private func reasoningLine(_ exchange: ExactExchange) -> String {
    exchange.transcript.first { $0.hasPrefix("reasoning ") } ?? ""
}

/// The event that ends an output item.
private func done(_ index: Int, _ value: JSONValue) -> JSONValue {
    item("response.output_item.done", at: index, value)
}

/// An annotation of the message at an output index.
private func annotation(at index: Int, _ annotation: JSONValue) -> JSONValue {
    ["type": "response.output_text.annotation.added", "output_index": .integer(index), "annotation": annotation]
}

/// A `reasoning` item, with its reasoning encrypted unless it's `nil`.
private func reasoning(_ id: String, encrypted: String? = "blob") -> JSONValue {
    ["type": "reasoning", "id": .string(id), "summary": [], "encrypted_content": encrypted.map(JSONValue.string)]
}

/// A web search's call, as the stream carries it.
private func search(_ id: String) -> JSONValue {
    ["type": "web_search_call", "id": .string(id), "status": "completed", "action": ["type": "search", "query": "swift"]]
}

/// A reasoning entry of the test provider whose signature holds these items.
private func reasoningEntry(_ items: JSONValue...) -> Transcript.Entry {
    .reasoning(Transcript.Reasoning(metadata: ["reasoningOrigin": "test-responses"], segments: [], signature: JSONValue.array(items).data))
}

/// The metadata of an entry that ends an answer, keeping these server tools' calls.
private func kept(_ calls: JSONValue...) -> [String: any ConvertibleToGeneratedContent] {
    ["test.serverTools": GeneratedContent(properties: ["calls": calls.map(\.text)])]
}
