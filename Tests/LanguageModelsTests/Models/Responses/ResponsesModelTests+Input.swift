import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Input")
    struct Input {
        @Test func `instructions, prompts, answers and tool outputs become messages, function calls and their outputs`() throws {
            let call = Transcript.ToolCall(id: "call_1", toolName: "lookUp", arguments: GeneratedContent(properties: ["word": "egg"]))
            let entries: [Transcript.Entry] = [
                .instructions(Transcript.Instructions(segments: [text("Be brief.")], toolDefinitions: [])),
                prompt(text("Define egg.")),
                .response(Transcript.Response(assetIDs: [], segments: [text("Looking it up.")])),
                .toolCalls(Transcript.ToolCalls([call])),
                .toolOutput(Transcript.ToolOutput(id: "call_1", toolName: "lookUp", segments: [text("egg:"), text("an oval")])),
            ]

            let items = input(try ResponsesSentRequest(generationRequest(entries)).body)

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

            let items = input(try ResponsesSentRequest(generationRequest(entries), model: model).body)

            #expect(items.first == ["role": "system", "content": "Be brief."])
        }
    }
}
