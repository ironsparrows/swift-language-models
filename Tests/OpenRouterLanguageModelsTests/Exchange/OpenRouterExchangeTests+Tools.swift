import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Tools")
    struct Tools {
        @Test func `a request with tools asks for hosts that take all it sends`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            _ = try await LanguageModelSession(model: model(stub), tools: [FoodTool()]).respond(to: "Hi")

            #expect(try body(stub)["provider"]?["require_parameters"] == true)
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
    }
}
