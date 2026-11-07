import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

@Suite("Responses input")
struct ResponsesInputTests {
    @Test func `instructions, prompts, answers and tool outputs become messages, function calls and their outputs`() throws {
        let call = Transcript.ToolCall(id: "call_1", toolName: "lookUp", arguments: GeneratedContent(properties: ["word": "egg"]))
        let entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [text("Be brief.")], toolDefinitions: [])),
            prompt(text("Define egg.")),
            .response(Transcript.Response(assetIDs: [], segments: [text("Looking it up.")])),
            .toolCalls(Transcript.ToolCalls([call])),
            .toolOutput(Transcript.ToolOutput(id: "call_1", toolName: "lookUp", segments: [text("egg:"), text("an oval")])),
        ]

        let items = input(try SentRequest(generationRequest(entries)).body)

        #expect(
            items == [
                ["role": "developer", "content": "Be brief."],
                ["role": "user", "content": "Define egg."],
                ["role": "assistant", "content": "Looking it up."],
                ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": #"{"word":"egg"}"#],
                ["type": "function_call_output", "call_id": "call_1", "output": "egg:\nan oval"],
            ])
    }

    @Test func `the instructions go in the model's role`() throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.instructionsRole = .system
        let entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [text("Be brief.")], toolDefinitions: [])), prompt(text("Hi")),
        ]

        let items = input(try SentRequest(generationRequest(entries), model: model).body)

        #expect(items.first == ["role": "system", "content": "Be brief."])
    }

    @Test func `the provider's own reasoning items go back before each message, with its phase, and another's don't`() throws {
        let reasoningItem: JSONValue = [
            "type": "reasoning", "id": "rs_1", "summary": [["type": "summary_text", "text": "Think."]], "encrypted_content": "blob",
        ]
        let own = Transcript.Reasoning(
            metadata: [ReasoningOrigin.metadataKey: "test-responses"], segments: [text("Think.")],
            signature: JSONValue.array([reasoningItem]).data)
        let other = Transcript.Reasoning(
            metadata: [ReasoningOrigin.metadataKey: "openrouter"], segments: [text("Other.")],
            signature: JSONValue.array([["type": "reasoning", "id": "rs_0"]]).data)
        let entries: [Transcript.Entry] = [
            prompt(text("Hi")), .reasoning(other), .reasoning(own),
            .response(
                Transcript.Response(
                    metadata: ["test.phases": phases(("commentary", 6), ("final_answer", 6))], segments: [text("Hm.   Hello.")])),
        ]

        let items = input(try SentRequest(generationRequest(entries)).body)

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
                Transcript.Response(metadata: ["test.phases": phases(("commentary", 4), ("final_answer", 4))], segments: [text("Hello.")])),
        ]

        let items = input(try SentRequest(generationRequest(entries)).body)

        #expect(items.last == ["role": "assistant", "content": "Hello.", "phase": "final_answer"])
    }

    @Test func `a message held out of the answer's text goes back in its place, with its phase`() throws {
        let commentary = GeneratedContent(properties: ["phase": "commentary", "length": 0, "heldText": "Here it is."])
        let final = GeneratedContent(properties: ["phase": "final_answer", "length": 11])
        let entries: [Transcript.Entry] = [
            prompt(text("Rate it.")),
            .response(Transcript.Response(metadata: ["test.phases": [commentary, final]], segments: [text(#"{"stars":4}"#)])),
        ]

        let items = input(try SentRequest(generationRequest(entries)).body)

        #expect(
            Array(items.dropFirst()) == [
                ["role": "assistant", "content": "Here it is.", "phase": "commentary"],
                ["role": "assistant", "content": #"{"stars":4}"#, "phase": "final_answer"],
            ])
    }

    @Test func `an answer with neither text nor tool calls sends no reasoning back, since nothing follows it`() throws {
        let reasoning = Transcript.Reasoning(
            metadata: [ReasoningOrigin.metadataKey: "test-responses"], segments: [],
            signature: JSONValue.array([["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "blob"]]).data)
        let entries: [Transcript.Entry] = [
            prompt(text("Hi")), .reasoning(reasoning), .response(Transcript.Response(assetIDs: [], segments: [])), prompt(text("Again.")),
        ]

        let items = input(try SentRequest(generationRequest(entries)).body)

        #expect(items == [["role": "user", "content": "Hi"], ["role": "user", "content": "Again."]])
    }

    @Test func `a request the provider doesn't store sends back only reasoning items with their reasoning encrypted`() throws {
        let encrypted: JSONValue = ["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "blob"]
        let stored: JSONValue = ["type": "reasoning", "id": "rs_2", "summary": []]
        let reasoning = Transcript.Reasoning(
            metadata: [ReasoningOrigin.metadataKey: "test-responses"], segments: [],
            signature: JSONValue.array([encrypted, stored]).data)
        let entries: [Transcript.Entry] = [
            prompt(text("Hi")), .reasoning(reasoning), .response(Transcript.Response(assetIDs: [], segments: [text("Hello.")])),
            prompt(text("Again.")),
        ]
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.exchange.prepares = { $0.storage = .notStored }

        let notStored = input(try SentRequest(generationRequest(entries), model: model).body)
        let automatic = input(try SentRequest(generationRequest(entries)).body)

        #expect(notStored.filter { $0["type"] == "reasoning" } == [encrypted])
        #expect(automatic.filter { $0["type"] == "reasoning" } == [encrypted, stored])
    }

    @Test func `an answer that ends in tool calls keeps its messages' phases on its first call`() throws {
        let call = Transcript.ToolCall(
            id: "call_1", metadata: ["test.phases": phases(("commentary", 14))], toolName: "lookUp",
            arguments: GeneratedContent(properties: ["word": "egg"]))
        let entries: [Transcript.Entry] = [
            prompt(text("Define egg.")), .response(Transcript.Response(assetIDs: [], segments: [text("Looking it up.")])),
            .toolCalls(Transcript.ToolCalls([call])),
        ]

        let items = input(try SentRequest(generationRequest(entries)).body)

        #expect(items[1] == ["role": "assistant", "content": "Looking it up.", "phase": "commentary"])
    }

    @Test func `a labeled image goes as its label, then an image the model sees at the detail it picks`() throws {
        let image = Transcript.ImageAttachment(try #require(TestImage.halves(width: 8, height: 4)))
        let entries = [prompt(text("What's this?"), .attachment(.init(content: .image(image), label: "Photo")))]

        let sent = try SentRequest(generationRequest(entries))
        let content = input(sent.body).first?["content"]

        #expect(content?[0] == ["type": "input_text", "text": "What's this?"])
        #expect(content?[1] == ["type": "input_text", "text": "Photo"])
        #expect(keys(content?[2]) == ["type", "image_url", "detail"])
        #expect(content?[2]?["image_url"]?.stringValue?.hasPrefix("data:image/jpeg;base64,") == true)
        #expect(content?[2]?["detail"] == "auto")
        #expect(sent.imageEntries.map(\.id) == entries.map(\.id))
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a kind the format has no part for throws before anything is sent`() {
        let notes = Transcript.DataAttachment(contentType: .rtf, content: Data("{\\rtf1 Soup}".utf8))
        let entries = [prompt(.attachment(.init(content: .data(notes), label: "Notes")))]

        #expect(throws: LanguageModelError.self) { try SentRequest(generationRequest(entries)) }
    }
    #endif
}

/// The phases of an answer's messages, as its response entry's metadata keeps them.
private func phases(_ messages: (phase: String, length: Int)...) -> [GeneratedContent] {
    messages.map { GeneratedContent(properties: ["phase": $0.phase, "length": $0.length]) }
}
