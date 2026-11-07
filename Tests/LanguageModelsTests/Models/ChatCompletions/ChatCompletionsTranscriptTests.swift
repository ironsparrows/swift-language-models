import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

@Suite("Chat Completions transcript")
struct ChatCompletionsTranscriptTests {
    @Test func `instructions, prompts, answers and tool outputs become system, user, assistant and tool messages`() throws {
        let call = Transcript.ToolCall(id: "call_1", toolName: "lookUp", arguments: GeneratedContent(properties: ["word": "egg"]))
        let entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [text("Be brief.")], toolDefinitions: [])),
            prompt(text("Define egg.")),
            .response(Transcript.Response(assetIDs: [], segments: [text("Looking it up.")])),
            .toolCalls(Transcript.ToolCalls([call])),
            .toolOutput(Transcript.ToolOutput(id: "call_1", toolName: "lookUp", segments: [text("egg:"), text("an oval")])),
        ]

        let sent = messages(try ChatCompletionsSentRequest(generationRequest(entries)).body)

        #expect(
            sent == [
                ["role": "system", "content": "Be brief."],
                ["role": "user", "content": "Define egg."],
                [
                    "role": "assistant", "content": "Looking it up.",
                    "tool_calls": [["id": "call_1", "type": "function", "function": ["name": "lookUp", "arguments": #"{"word":"egg"}"#]]],
                ],
                ["role": "tool", "tool_call_id": "call_1", "content": "egg:\nan oval"],
            ])
    }

    @Test func `the provider's own reasoning goes back after the content, and another provider's doesn't`() throws {
        var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
        model.exchange.reasoningMember = "reasoning"
        let own = Transcript.Reasoning(metadata: [ReasoningOrigin.metadataKey: "test"], segments: [text("Think.")])
        let other = Transcript.Reasoning(metadata: [ReasoningOrigin.metadataKey: "other"], segments: [text("Other.")])
        let entries: [Transcript.Entry] = [
            prompt(text("Hi")), .reasoning(other), .reasoning(own),
            .response(Transcript.Response(assetIDs: [], segments: [text("Hello.")])),
        ]

        let assistant = messages(try ChatCompletionsSentRequest(generationRequest(entries), model: model).body).last

        #expect(keys(assistant) == ["role", "content", "reasoning"])
        #expect(assistant?["reasoning"] == "Think.")
    }

    @Test func `a block the model wrote in its answer's text goes back at the start of that text`() throws {
        let reasoning = Transcript.Reasoning(
            metadata: [ReasoningOrigin.metadataKey: "test", TaggedReasoning.metadataKey: "<think>Count.</think>\n"],
            segments: [text("Count.")])
        let entries: [Transcript.Entry] = [
            prompt(text("Hi")), .reasoning(reasoning), .response(Transcript.Response(assetIDs: [], segments: [text("Seven.")])),
        ]

        let assistant = messages(try ChatCompletionsSentRequest(generationRequest(entries)).body).last

        #expect(assistant?["content"] == "<think>Count.</think>\nSeven.")
    }

    @Test func `an answer with nothing to send back has no message`() throws {
        let entries: [Transcript.Entry] = [prompt(text("Hi")), .response(Transcript.Response(assetIDs: [], segments: []))]

        let sent = messages(try ChatCompletionsSentRequest(generationRequest(entries)).body)

        #expect(sent.count == 1)
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a PDF goes as a named file part and WAV audio as input_audio, after their labels`() throws {
        let pdf = Transcript.DataAttachment(contentType: .pdf, content: Data("%PDF-1.4".utf8))
        let audio = Transcript.DataAttachment(contentType: .wav, content: Data("RIFF".utf8))
        let entry = prompt(.attachment(.init(content: .data(pdf), label: "Menu")), .attachment(.init(content: .data(audio))))

        let parts = messages(try ChatCompletionsSentRequest(generationRequest([entry])).body).first?["content"]

        #expect(
            parts == [
                ["type": "text", "text": "Menu"],
                ["type": "file", "file": ["filename": "Menu.pdf", "file_data": "data:application/pdf;base64,JVBERi0xLjQ="]],
                ["type": "input_audio", "input_audio": ["data": "UklGRg==", "format": "wav"]],
            ])
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `data of a kind neither the format nor the provider has a part for throws`() {
        let movie = Transcript.DataAttachment(contentType: .mpeg4Movie, content: Data([1, 2]))

        #expect(throws: LanguageModelError.self) {
            try ChatCompletionsSentRequest(generationRequest([prompt(.attachment(.init(content: .data(movie))))]))
        }
    }
    #endif

    @Test func `instructions take only text`() {
        let image = Transcript.ImageAttachment(imageURL: URL(fileURLWithPath: "/dev/null"))
        let entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(segments: [.attachment(.init(content: .image(image)))], toolDefinitions: []))
        ]

        #expect(throws: LanguageModelError.self) {
            try ChatCompletionsSentRequest(generationRequest(entries))
        }
    }
}
