import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Replay")
    struct Replay {
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
                        "response.output_item.added", at: 3,
                        ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": ""]),
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

        @Test func `the provider's own reasoning items go back before each message, with its phase, and another's don't`() throws {
            let reasoningItem: JSONValue = [
                "type": "reasoning", "id": "rs_1", "summary": [["type": "summary_text", "text": "Think."]], "encrypted_content": "blob",
            ]
            let own = Transcript.Reasoning(
                metadata: ["reasoningOrigin": "test-responses"], segments: [text("Think.")],
                signature: JSONValue.array([reasoningItem]).data)
            let other = Transcript.Reasoning(
                metadata: ["reasoningOrigin": "openrouter"], segments: [text("Other.")],
                signature: JSONValue.array([["type": "reasoning", "id": "rs_0"]]).data)
            let entries: [Transcript.Entry] = [
                prompt(text("Hi")), .reasoning(other), .reasoning(own),
                .response(
                    Transcript.Response(
                        metadata: ["test.phases": phases(("commentary", 6), ("final_answer", 6))], segments: [text("Hm.   Hello.")])),
            ]

            let items = input(try ResponsesSentRequest(generationRequest(entries)).body)

            #expect(
                Array(items.dropFirst()) == [
                    reasoningItem, ["role": "assistant", "content": "Hm.   ", "phase": "commentary"],
                    ["role": "assistant", "content": "Hello.", "phase": "final_answer"],
                ])
        }

        @Test func `messages whose lengths don't add up to the text go back as one, with the last phase`() throws {
            let entries: [Transcript.Entry] = [
                prompt(text("Hi")),
                .response(
                    Transcript.Response(
                        metadata: ["test.phases": phases(("commentary", 4), ("final_answer", 4))], segments: [text("Hello.")])),
            ]

            let items = input(try ResponsesSentRequest(generationRequest(entries)).body)

            #expect(items.last == ["role": "assistant", "content": "Hello.", "phase": "final_answer"])
        }

        @Test func `a message held out of the answer's text goes back in its place, with its phase`() throws {
            let commentary = GeneratedContent(properties: ["phase": "commentary", "length": 0, "heldText": "Here it is."])
            let final = GeneratedContent(properties: ["phase": "final_answer", "length": 11])
            let entries: [Transcript.Entry] = [
                prompt(text("Rate it.")),
                .response(Transcript.Response(metadata: ["test.phases": [commentary, final]], segments: [text(#"{"stars":4}"#)])),
            ]

            let items = input(try ResponsesSentRequest(generationRequest(entries)).body)

            #expect(
                Array(items.dropFirst()) == [
                    ["role": "assistant", "content": "Here it is.", "phase": "commentary"],
                    ["role": "assistant", "content": #"{"stars":4}"#, "phase": "final_answer"],
                ])
        }

        @Test func `an answer with neither text nor tool calls sends no reasoning back, since nothing follows it`() throws {
            let reasoning = Transcript.Reasoning(
                metadata: ["reasoningOrigin": "test-responses"], segments: [],
                signature: JSONValue.array([["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "blob"]]).data)
            let entries: [Transcript.Entry] = [
                prompt(text("Hi")), .reasoning(reasoning), .response(Transcript.Response(assetIDs: [], segments: [])),
                prompt(text("Again.")),
            ]

            let items = input(try ResponsesSentRequest(generationRequest(entries)).body)

            #expect(items == [["role": "user", "content": "Hi"], ["role": "user", "content": "Again."]])
        }

        @Test(
            arguments: [
                (.notStored, nil, ["rs_1"]), (.automatic, nil, ["rs_1", "rs_2"]), (.automatic, false, ["rs_1"]),
                (.notStored, true, ["rs_1", "rs_2"]), (.notStored, .null, ["rs_1", "rs_2"]),
            ] as [(Responses.Request.Storage, JSONValue?, [JSONValue])])
        func `a request the provider doesn't store, by the exchange's storage or the app's store, sends back only encrypted reasoning`(
            storage: Responses.Request.Storage, store: JSONValue?, ids: [JSONValue]
        ) throws {
            let encrypted: JSONValue = ["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "blob"]
            let stored: JSONValue = ["type": "reasoning", "id": "rs_2", "summary": []]
            let reasoning = Transcript.Reasoning(
                metadata: ["reasoningOrigin": "test-responses"], segments: [],
                signature: JSONValue.array([encrypted, stored]).data)
            let entries: [Transcript.Entry] = [
                prompt(text("Hi")), .reasoning(reasoning), .response(Transcript.Response(assetIDs: [], segments: [text("Hello.")])),
                prompt(text("Again.")),
            ]
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { request in
                request.storage = storage
                request.overridingMembers = ["store": store]
            }

            let sent = input(try ResponsesSentRequest(generationRequest(entries), model: model).body)

            #expect(sent.filter { $0["type"] == "reasoning" }.compactMap { $0["id"] } == ids)
        }

        @Test func `an answer that ends in tool calls keeps its messages' phases on its first call`() throws {
            let call = Transcript.ToolCall(
                id: "call_1", metadata: ["test.phases": phases(("commentary", 14))], toolName: "lookUp",
                arguments: GeneratedContent(properties: ["word": "egg"]))
            let entries: [Transcript.Entry] = [
                prompt(text("Define egg.")), .response(Transcript.Response(assetIDs: [], segments: [text("Looking it up.")])),
                .toolCalls(Transcript.ToolCalls([call])),
            ]

            let items = input(try ResponsesSentRequest(generationRequest(entries)).body)

            #expect(items[1] == ["role": "assistant", "content": "Looking it up.", "phase": "commentary"])
        }
    }
}

/// The phases of an answer's messages, as its response entry's metadata keeps them.
private func phases(_ messages: (phase: String, length: Int)...) -> [GeneratedContent] {
    messages.map { GeneratedContent(properties: ["phase": $0.phase, "length": $0.length]) }
}
