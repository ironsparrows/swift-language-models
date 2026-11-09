import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Tool calls")
    struct ToolCalls {
        @Test func `fragments without an index run as two calls when their ids differ`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    toolCallChunk(nil, id: "call_1", name: "lookUp", arguments: #"{"word":"egg"}"#),
                    toolCallChunk(nil, id: "call_2", name: "lookUp", arguments: #"{"word":"rice"}"#),
                    finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("Done.", finishReason: "stop")))

            let response = try await LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()]).respond(to: "Look them up.")

            #expect(response.content == "Done.")
            let calls = try #require(messages(try sentBody(stub, 1)).first { $0["tool_calls"] != nil })["tool_calls"]
            #expect(calls?[0]?["id"] == "call_1")
            #expect(calls?[1]?["id"] == "call_2")
        }

        @Test func `whole calls without an index that end with the finish reason stop run, as Gemini sends them`() async throws {
            // The first round's chunks as Gemini sent them, with the ids and the signature replaced, and the call made one
            // to the test's tool.
            let call =
                #"{"choices":[{"delta":{"role":"assistant","tool_calls":[{"extra_content":{"google":{"thought_signature":"c2lnbmF0dXJl"}},"function":{"arguments":"{\"word\":\"egg\"}","name":"lookUp"},"id":"call_100000000000000001","type":"function"}]},"index":0}],"created":1794203010,"id":"response-1","model":"gemini-3.1-flash-lite","object":"chat.completion.chunk"}"#
            let finish =
                #"{"choices":[{"delta":{"role":"assistant"},"finish_reason":"stop","index":0}],"created":1794203010,"id":"response-1","model":"gemini-3.1-flash-lite","object":"chat.completion.chunk"}"#
            let stub = HTTPStub(
                .eventStream(Data("data: \(call)\n\ndata: \(finish)\n\ndata: [DONE]\n\n".utf8)),
                chatCompletionsEvents(textChunk("Done.", finishReason: "stop")))

            try await confirmation { toolRan in
                let session = LanguageModelSession(model: plainModel(stub), tools: [ConfirmingTool(ran: toolRan)])

                let response = try await session.respond(to: "Define egg.")

                #expect(response.content == "Done.")
            }

            let sent = messages(try sentBody(stub, 1))
            #expect(
                sent.first { $0["tool_calls"] != nil }?["tool_calls"] == [
                    ["id": "call_100000000000000001", "type": "function", "function": ["name": "lookUp", "arguments": #"{"word":"egg"}"#]]
                ])
            #expect(sent.last == ["role": "tool", "tool_call_id": "call_100000000000000001", "content": "egg"])
        }

        @Test func `arguments sent as a JSON object run the call, and go back as their JSON text`() async throws {
            let fragment: JSONValue = ["index": 0, "id": "call_1", "function": ["name": "lookUp", "arguments": ["word": "egg"]]]
            let stub = HTTPStub(
                chatCompletionsEvents(["choices": [["delta": ["tool_calls": [fragment]]]]], finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("Done.", finishReason: "stop")))

            try await confirmation { toolRan in
                let session = LanguageModelSession(model: plainModel(stub), tools: [ConfirmingTool(ran: toolRan)])

                _ = try await session.respond(to: "Define egg.")
            }

            let call = try #require(messages(try sentBody(stub, 1)).first { $0["tool_calls"] != nil })
            #expect(call["tool_calls"]?[0]?["function"]?["arguments"] == #"{"word":"egg"}"#)
        }

        @Test func `tools go as functions, with the tool choice the options ask for`() throws {
            let request = generationRequest(
                [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())],
                options: GenerationOptions(toolCallingMode: .required))

            let body = try ChatCompletionsSentRequest(request).body

            #expect(body["tools"]?[0]?["type"] == "function")
            #expect(body["tools"]?[0]?["function"]?["name"] == "lookUp")
            #expect(body["tool_choice"] == "required")
        }

        @Test func `the fragments of a tool call form one call, which runs once, and its output goes back in the next round`() async throws
        {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    toolCallChunk(0, id: "call_1", name: "lookUp", arguments: #"{"wo"#),
                    toolCallChunk(0, arguments: #"rd":"egg"}"#),
                    finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("Done.", finishReason: "stop")))

            try await confirmation { toolRan in
                let session = LanguageModelSession(model: plainModel(stub), tools: [ConfirmingTool(ran: toolRan)])

                let response = try await session.respond(to: "Define egg.")

                #expect(response.content == "Done.")
            }

            #expect(stub.requests.count == 2)
            let sent = messages(try sentBody(stub, 1))
            try #require(sent.count == 3)
            #expect(
                sent[1]["tool_calls"] == [
                    ["id": "call_1", "type": "function", "function": ["name": "lookUp", "arguments": #"{"word":"egg"}"#]]
                ])
            #expect(sent[2] == ["role": "tool", "tool_call_id": "call_1", "content": "egg"])
        }

        @Test func `parallel calls in one answer each run once, in one round and one follow-up request`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    toolCallChunk(0, id: "call_egg", name: "lookUp", arguments: #"{"word":"egg"}"#),
                    toolCallChunk(1, id: "call_rice", name: "lookUp", arguments: #"{"word":"rice"}"#),
                    finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("Done.", finishReason: "stop")))

            try await confirmation(expectedCount: 2) { toolRan in
                let session = LanguageModelSession(model: plainModel(stub), tools: [ConfirmingTool(ran: toolRan)])

                let response = try await session.respond(to: "Define egg and rice.")

                #expect(response.content == "Done.")
            }

            #expect(stub.requests.count == 2)
            let sent = messages(try sentBody(stub, 1))
            let assistant = sent.filter { $0["role"] == "assistant" }
            try #require(assistant.count == 1)
            #expect(assistant[0]["tool_calls"]?[0]?["id"] == "call_egg")
            #expect(assistant[0]["tool_calls"]?[1]?["id"] == "call_rice")
            let outputs = sent.filter { $0["role"] == "tool" }
            #expect(outputs.map(\.["tool_call_id"]) == ["call_egg", "call_rice"])
            #expect(outputs.map(\.["content"]) == ["egg", "rice"])
        }

        @Test(arguments: [(GenerationOptions.ToolCallingMode.allowed, JSONValue.string("auto")), (.required, "required")])
        func `a tool-calling mode becomes the tool choice of every round`(mode: GenerationOptions.ToolCallingMode, choice: JSONValue)
            async throws
        {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    toolCallChunk(0, id: "call_1", name: "lookUp", arguments: #"{"word":"egg"}"#), finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("Done.", finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])

            _ = try await session.respond(to: "Define egg.", options: GenerationOptions(toolCallingMode: mode))

            #expect(try sentBody(stub, 0)["tool_choice"] == choice)
            #expect(try sentBody(stub, 1)["tool_choice"] == choice)
        }

        @Test func `when tools are disallowed, Foundation Models sends none, so no tool choice goes out`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("Hi", finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])

            _ = try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: .disallowed))

            let body = try sentBody(stub)
            #expect(body["tools"] == nil)
            #expect(body["tool_choice"] == nil)
        }

        @Test func `a call without arguments goes back with an empty object`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(toolCallChunk(0, id: "call_1", name: "readClock"), finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("Done.", finishReason: "stop")))

            _ = try await LanguageModelSession(model: plainModel(stub), tools: [ClockTool()]).respond(to: "What time is it?")

            let call = try #require(messages(try sentBody(stub, 1)).first { $0["tool_calls"] != nil })
            #expect(call["tool_calls"]?[0]?["function"]?["arguments"] == "{}")
        }

        @Test func `a session with tools and no instructions sends no empty system message`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("Hi", finishReason: "stop")))

            _ = try await LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()]).respond(to: "Hi")

            #expect(messages(try sentBody(stub)).map(\.["role"]) == ["user"])
        }

        @Test func `server tools go after the session's, and the tool choice only with the session's`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.serverTools = [["type": "web_search"]] }
            let options = GenerationOptions(toolCallingMode: .required)
            let withSessionTool = generationRequest(
                [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())], options: options)

            let both = try ChatCompletionsSentRequest(withSessionTool, model: model).body
            let alone = try ChatCompletionsSentRequest(generationRequest([prompt(text("Hi"))], options: options), model: model).body

            #expect(both["tools"]?[0]?["function"]?["name"] == "lookUp")
            #expect(both["tools"]?[1] == ["type": "web_search"])
            #expect(both["tool_choice"] == "required")
            #expect(alone["tools"] == [["type": "web_search"]])
            #expect(alone["tool_choice"] == nil)
        }
    }
}

/// A tool that looks up a word and says that it ran, so a test can count its runs.
private struct ConfirmingTool: Tool {
    typealias Arguments = LookUpTool.Arguments

    let name = "lookUp"
    let description = "Looks up a word."
    let ran: Confirmation

    func call(arguments: Arguments) async throws -> String {
        ran()
        return arguments.word
    }
}

/// A tool that takes no arguments.
private struct ClockTool: Tool {
    let name = "readClock"
    let description = "Reads the clock."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        "Noon"
    }
}
