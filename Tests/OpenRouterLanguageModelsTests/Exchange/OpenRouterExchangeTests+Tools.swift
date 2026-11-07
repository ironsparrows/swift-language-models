import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Tools")
    struct Tools {
        @Test func `a tool call runs the tool and sends its output back`() async throws {
            let stub = HTTPStub(
                events(
                    toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"fo"#),
                    toolCall(0, arguments: #"od":"egg"}"#),
                    done("tool_calls")
                ),
                events(text("An egg has 100 kcal."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()], instructions: "Answer with tools.")

            let response = try await session.respond(to: "Calories in an egg?")

            #expect(response.content == "An egg has 100 kcal.")
            #expect(stub.requests.count == 2)
            let first = try body(stub, 0)
            let definitions = elements(first["tools"])
            try #require(definitions.count == 1)
            #expect(definitions[0]["function"]?["name"] == "lookUpFood")
            #expect(definitions[0]["function"]?["parameters"]?["properties"]?["food"]?["type"] == "string")
            #expect(first["provider"]?["require_parameters"] == true)

            let second = messages(try body(stub, 1))
            try #require(second.count == 4)
            #expect(second[2]["role"] == "assistant")
            #expect(
                second[2]["tool_calls"] == [
                    ["function": ["arguments": #"{"food":"egg"}"#, "name": "lookUpFood"], "id": "call_1", "type": "function"]
                ])
            #expect(second[3] == ["content": "egg: 100 kcal", "role": "tool", "tool_call_id": "call_1"])
        }

        @Test(arguments: [
            (OpenRouterOptions.ParallelToolCalls.automatic, JSONValue?.none), (.allowed, true), (.disallowed, false),
        ])
        func `parallel calls are asked for only when the options choose them`(
            choice: OpenRouterOptions.ParallelToolCalls,
            sent: JSONValue?
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let options = OpenRouterOptions(parallelToolCalls: choice)
            let model = model(stub, parameters: chatParameters.union([.parallelToolCalls]), options: options)

            _ = try await LanguageModelSession(model: model, tools: [FoodTool()]).respond(to: "Hi")

            #expect(try body(stub)["parallel_tool_calls"] == sent)
        }

        @Test func `parallel calls aren't asked for from a model that doesn't list them`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, options: OpenRouterOptions(parallelToolCalls: .allowed))

            _ = try await LanguageModelSession(model: model, tools: [FoodTool()]).respond(to: "Hi")

            #expect(try body(stub)["parallel_tool_calls"] == nil)
        }

        @Test func `parallel calls in one answer make one round and one follow-up request`() async throws {
            let stub = HTTPStub(
                events(
                    toolCall(0, id: "call_egg", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    toolCall(1, id: "call_rice", name: "lookUpFood", arguments: #"{"food":"rice"}"#),
                    done("tool_calls")
                ),
                events(text("Egg and rice: 200 kcal."), done())
            )
            let session = LanguageModelSession(
                model: model(stub, parameters: chatParameters.union([.parallelToolCalls])), tools: [FoodTool()])

            let response = try await session.respond(to: "Calories in an egg and rice?")

            #expect(response.content == "Egg and rice: 200 kcal.")
            #expect(stub.requests.count == 2)
            #expect(try body(stub, 0)["parallel_tool_calls"] == nil)
            let second = messages(try body(stub, 1))
            let assistant = second.filter { $0["role"] == "assistant" }
            try #require(assistant.count == 1)
            #expect(elements(assistant[0]["tool_calls"]).map { $0["id"] } == ["call_egg", "call_rice"])
            let outputs = second.filter { $0["role"] == "tool" }
            #expect(outputs.map { $0["tool_call_id"] } == ["call_egg", "call_rice"])
            #expect(outputs.map { $0["content"] } == ["egg: 100 kcal", "rice: 100 kcal"])
        }

        @Test(arguments: [(GenerationOptions.ToolCallingMode.allowed, JSONValue.string("auto")), (.required, "required")])
        func `a tool-calling mode becomes the tool choice of every round`(mode: GenerationOptions.ToolCallingMode, choice: JSONValue)
            async throws
        {
            let stub = HTTPStub(
                events(toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#), done("tool_calls")),
                events(text("An egg has 100 kcal."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            let response = try await session.respond(to: "Calories in an egg?", options: GenerationOptions(toolCallingMode: mode))

            #expect(response.content == "An egg has 100 kcal.")
            #expect(try body(stub, 0)["tool_choice"] == choice)
            #expect(try body(stub, 1)["tool_choice"] == choice)
            let output = messages(try body(stub, 1)).first { $0["role"] == "tool" }
            #expect(output?["content"] == "egg: 100 kcal")
        }

        @Test(arguments: [
            (chatParameters.subtracting([.toolChoice]), chatParameters),
            (chatParameters, chatParameters.subtracting([.toolChoice])),
        ])
        func `required tool calls are refused before any request when the model or a fallback doesn't take a tool choice`(
            parameters: Set<OpenRouterParameter>,
            fallbackParameters: Set<OpenRouterParameter>
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, parameters: parameters, fallbacks: [fallback(parameters: fallbackParameters)])
            let session = LanguageModelSession(model: model, tools: [FoodTool()])

            let error = try await #require(throws: LanguageModelError.self) {
                try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: .required))
            }

            guard case .unsupportedCapability(let unsupported) = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(unsupported.capability == .toolCalling)
            #expect(unsupported.debugDescription.contains("tool_choice"))
            #expect(stub.requests.isEmpty)
        }

        @Test(arguments: [GenerationOptions.ToolCallingMode?.none, .allowed])
        func `without a tool choice, other modes still send the tools, with no tool choice`(
            mode: GenerationOptions.ToolCallingMode?
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(
                model: model(stub, parameters: chatParameters.subtracting([.toolChoice])), tools: [FoodTool()])

            _ = try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: mode))

            let body = try body(stub)
            #expect(elements(body["tools"]).map { $0["function"]?["name"] } == ["lookUpFood"])
            #expect(body["tool_choice"] == nil)
        }

        @Test func `required tool calls without the session's tools aren't refused, since no tool choice goes out`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, parameters: chatParameters.subtracting([.toolChoice]), serverTools: [.datetime()])

            let response = try await LanguageModelSession(model: model).respond(
                to: "Hi", options: GenerationOptions(toolCallingMode: .required))

            #expect(response.content == "Hi")
            #expect(try body(stub)["tool_choice"] == nil)
        }

        @Test func `when tools are disallowed, Foundation Models sends none, so no tool choice goes out`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            _ = try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: .disallowed))

            let body = try body(stub)
            #expect(body["tools"] == nil)
            #expect(body["tool_choice"] == nil)
        }

        @Test func `a tool output of several texts goes back as one string, a line per text`() async throws {
            let stub = HTTPStub(
                events(toolCall(0, id: "call_1", name: "readNotes", arguments: "{}"), done("tool_calls")),
                events(text("Two lines."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [NotesTool()])

            _ = try await session.respond(to: "Read my notes.")

            let tool = messages(try body(stub, 1)).last
            #expect(tool?["content"] == "Line one.\nLine two.")
        }

        @Test func `a call whose arguments stop partway throws before the tool runs`() async throws {
            let stub = HTTPStub(
                events(toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"eg"#), done("tool_calls")),
                events(text("Done."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            let error = await #expect(throws: OpenRouterError.self) { try await session.respond(to: "What's in an egg?") }

            #expect(error?.code == .invalidResponse)
            #expect(stub.requests.count == 1)
        }

        @Test func `a call without arguments gets an empty object`() async throws {
            let stub = HTTPStub(
                events(toolCall(0, id: "call_1", name: "readClock"), done("tool_calls")),
                events(text("Done."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [ClockTool()])

            _ = try await session.respond(to: "What time is it?")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["tool_calls"]?[0]?["function"]?["arguments"] == "{}")
        }

        @Test func `argument text that arrives before the call's name joins the call`() async throws {
            let stub = HTTPStub(
                events(
                    toolCall(0, arguments: #"{"fo"#),
                    toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"od":"#),
                    toolCall(0, arguments: #""egg"}"#),
                    done("tool_calls")
                ),
                events(text("Done."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            _ = try await session.respond(to: "Calories in an egg?")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["tool_calls"]?[0]?["function"]?["arguments"] == #"{"food":"egg"}"#)
            #expect(messages(try body(stub, 1)).last == ["content": "egg: 100 kcal", "role": "tool", "tool_call_id": "call_1"])
        }

        @Test func `a call without an id gets one, and its output answers that id`() async throws {
            let stub = HTTPStub(
                events(toolCall(0, name: "lookUpFood", arguments: #"{"food":"egg"}"#), done("tool_calls")),
                events(text("Done."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            _ = try await session.respond(to: "Calories in an egg?")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            let id = try #require(assistant["tool_calls"]?[0]?["id"]?.stringValue)
            #expect(id.hasPrefix("call_"))
            let output = messages(try body(stub, 1)).first { $0["role"] == "tool" }
            #expect(output?["tool_call_id"]?.stringValue == id)
        }

        @Test func `a call that never gets a name throws`() async throws {
            let stub = HTTPStub(events(toolCall(0, id: "call_1", arguments: #"{"food":"egg"}"#), done("tool_calls")))
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            let error = try await #require(throws: OpenRouterError.self) {
                try await session.respond(to: "Calories in an egg?")
            }

            #expect(error.code == .invalidResponse)
            #expect(stub.requests.count == 1)
        }

        @Test func `a call cut off at the token limit throws instead of reaching the tool`() async throws {
            let stub = HTTPStub(events(toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"eg"#), done("length")))
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            let error = try await #require(throws: OpenRouterError.self) {
                try await session.respond(to: "Calories in an egg?")
            }

            let message = "The answer reached its token limit inside a tool call."
            #expect(error == OpenRouterError(message: message, code: .invalidResponse, providerName: "Vendor"))
            #expect(stub.requests.count == 1)
        }
    }
}

/// A tool whose output is two pieces of text.
private struct NotesTool: Tool {
    let name = "readNotes"
    let description = "Reads the notes."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> Prompt {
        Prompt {
            "Line one."
            "Line two."
        }
    }
}

/// A tool without arguments.
private struct ClockTool: Tool {
    let name = "readClock"
    let description = "Reads the time."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        "09:00"
    }
}
