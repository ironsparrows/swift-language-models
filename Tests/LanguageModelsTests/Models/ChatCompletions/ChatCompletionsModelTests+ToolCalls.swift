import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Tool calls")
    struct ToolCalls {
        @Test func `tools go as functions, with the tool choice the options ask for`() throws {
            let request = generationRequest(
                [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())],
                options: GenerationOptions(toolCallingMode: .required))

            let body = try ChatCompletionsSentRequest(request).body

            #expect(body["tools"]?[0]?["type"] == "function")
            #expect(body["tools"]?[0]?["function"]?["name"] == "lookUp")
            #expect(body["tool_choice"] == "required")
        }

        @Test func `the fragments of a tool call form one call, whose answer goes back in the next round`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    [
                        "choices": [
                            [
                                "delta": [
                                    "tool_calls": [["index": 0, "id": "call_1", "function": ["name": "lookUp", "arguments": "{\"wo"]]]
                                ]
                            ]
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
            #expect(
                messages(try #require(bodies.last)).dropFirst().first?["tool_calls"]?[0]?["function"]?["arguments"] == #"{"word":"egg"}"#)
        }
    }
}
