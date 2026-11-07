import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Tool calls")
    struct ToolCalls {
        @Test func `an answer whose token limit cuts off a function call fails`() async {
            let stub = HTTPStub(
                events(
                    item(
                        "response.output_item.added", at: 0,
                        ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": ""]),
                    ["type": "response.function_call_arguments.delta", "output_index": 0, "delta": #"{"word""#],
                    lifecycle("response.incomplete", ["incomplete_details": ["reason": "max_output_tokens"]])))

            let failure = await respond(stub, to: [prompt(text("Hello"))])

            guard case .unusableAnswer? = failure?.kind, failure?.message == "The answer reached its token limit inside a tool call." else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
        }

        @Test func `function call arguments without an output index go to the last call`() async throws {
            let stub = HTTPStub(
                events(
                    item(
                        "response.output_item.added", at: 0,
                        ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": ""]),
                    ["type": "response.function_call_arguments.delta", "delta": #"{"word":"egg"}"#],
                    ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "call_1", "name": "lookUp"]],
                    lifecycle("response.completed")),
                events(textDelta("Found."), lifecycle("response.completed")))

            let response = try await LanguageModelSession(model: model(stub), tools: [LookUpTool()]).respond(to: "Define egg.")

            #expect(response.content == "Found.")
            #expect(String(decoding: try #require(stub.requests.last).body, as: UTF8.self).contains(#""arguments":"{\"word\":\"egg\"}""#))
        }

        @Test func `parallel function calls form one round, with arguments that stream or arrive whole, and go back with their outputs`()
            async
        {
            let stub = HTTPStub(
                events(
                    item(
                        "response.output_item.added", at: 0,
                        ["type": "function_call", "call_id": "call_1", "name": "lookUp", "arguments": ""]),
                    ["type": "response.function_call_arguments.delta", "output_index": 0, "delta": #"{"word""#],
                    item(
                        "response.output_item.added", at: 1,
                        ["type": "function_call", "call_id": "call_2", "name": "lookUp", "arguments": ""]),
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

        @Test func `the session's tools go as functions whose arguments aren't held to the schema, with the tool choice`() throws {
            let request = generationRequest(
                [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())],
                options: GenerationOptions(toolCallingMode: .required))

            let body = try SentRequest(request).body

            #expect(keys(body) == ["model", "input", "stream", "tools", "tool_choice"])
            #expect(keys(body["tools"]?[0]) == ["type", "name", "description", "parameters", "strict"])
            #expect(body["tools"]?[0]?["name"] == "lookUp")
            #expect(body["tools"]?[0]?["strict"] == false)
            #expect(body["tool_choice"] == "required")
        }

        @Test func `an exchange that leaves the session's tools out sends neither tools nor tool choice`() throws {
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { $0.sendsSessionTools = false }
            let request = generationRequest(
                [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())],
                options: GenerationOptions(toolCallingMode: .required))

            let body = try SentRequest(request, model: model).body

            #expect(body["tools"] == nil)
            #expect(body["tool_choice"] == nil)
        }

        @Test func `server tools go after the session's, and the tool choice only with the session's`() throws {
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { $0.serverTools = [["type": "web_search"]] }
            let options = GenerationOptions(toolCallingMode: .required)
            let withSessionTool = generationRequest(
                [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())], options: options)

            let both = try SentRequest(withSessionTool, model: model).body
            let alone = try SentRequest(generationRequest([prompt(text("Hi"))], options: options), model: model).body

            #expect(both["tools"]?[0]?["name"] == "lookUp")
            #expect(both["tools"]?[1] == ["type": "web_search"])
            #expect(both["tool_choice"] == "required")
            #expect(alone["tools"] == [["type": "web_search"]])
            #expect(alone["tool_choice"] == nil)
        }
    }
}
