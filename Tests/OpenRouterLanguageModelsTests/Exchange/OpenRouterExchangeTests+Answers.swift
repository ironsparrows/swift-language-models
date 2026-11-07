import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Answers")
    struct Answers {
        @Test func `a fact that a chunk reports replaces the earlier one, and one it leaves out keeps its value`() async throws {
            let stub = HTTPStub(
                events(
                    [
                        "id": "gen-1", "model": "vendor/model", "provider": "Vendor", "service_tier": "flex",
                        "choices": [["delta": ["content": "Hi"]]],
                    ],
                    [
                        "model": "vendor/model-2026-10-01",
                        "choices": [["delta": [:], "finish_reason": "length"]],
                        "usage": ["prompt_tokens": 12, "completion_tokens": 5, "cost": 0.000_1],
                    ],
                    ["choices": [["delta": [:]]]]))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            let facts = try lastResponse(of: response).openRouter
            #expect(facts.provider == "Vendor")
            #expect(facts.model == "vendor/model-2026-10-01")
            #expect(facts.serviceTier == .flex)
            #expect(facts.responseID == "gen-1")
            #expect(metadataNumber(response.usage.metadata, LanguageModelMetadataKey.cost) == 0.000_1)
        }

        @Test func `the metadata names the host, with the response cache's status and the router's report`() async throws {
            let stub = HTTPStub(
                events(
                    headers: ["X-OpenRouter-Cache-Status": "MISS"],
                    [
                        "id": "gen-1", "model": "vendor/model", "provider": "Vendor", "service_tier": "priority",
                        "choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]],
                        "openrouter_metadata": ["strategy": "price", "generation_time": 1_500],
                    ]))
            let model = model(stub, options: OpenRouterOptions(includesRouterMetadata: true))

            let response = try await LanguageModelSession(model: model).respond(to: "Hi")

            let metadata = try lastResponse(of: response).metadata
            #expect(metadataString(metadata, LanguageModelMetadataKey.provider) == "Vendor")
            #expect(metadataString(metadata, OpenRouterMetadataKey.responseCacheStatus) == "MISS")
            #expect(metadataString(metadata, OpenRouterMetadataKey.routingStrategy) == "price")
            #expect(metadataNumber(metadata, OpenRouterMetadataKey.generationTime) == 1.5)
        }

        @Test func `facts that no chunk reported are left out of the metadata`() async throws {
            let stub = HTTPStub(events(["choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]]]))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            let facts = try lastResponse(of: response).openRouter
            #expect(facts.provider == nil)
            #expect(facts.responseID == nil)
            #expect(facts.serviceTier == nil)
            #expect(response.usage.metadata[LanguageModelMetadataKey.cost] == nil)
        }

        @Test func `a model that doesn't take tools gets none of the session's, nor a tool choice`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, parameters: chatParameters.subtracting([.tools]))
            let request = generationRequest(
                [.prompt(Transcript.Prompt(segments: [.text(.init(content: "Hi"))]))], tools: [Transcript.ToolDefinition(tool: FoodTool())],
                options: GenerationOptions(toolCallingMode: .required))

            let body = try await requestBody(request, model: model, stub: stub)

            #expect(body["tools"] == nil)
            #expect(body["tool_choice"] == nil)
        }

        @Test(
            arguments: [
                (events(toolCall(0, id: "call_1", arguments: "{}"), done("tool_calls")), "Vendor"),
                (events(toolCall(0, id: "call_1", name: "lookUpFood", arguments: "{"), done("tool_calls")), "Vendor"),
                (unfinishedEvents(text("Hi")), "Vendor"),
                (.eventStream(Data("data: \(text("Hi").text)\n\ndata: not JSON\n\n".utf8)), nil),
            ] as [(StubResponse, OpenRouterProviderName?)])
        func `a response the format can't use throws an invalid response, naming the host unless an event couldn't be read`(
            response: StubResponse,
            host: OpenRouterProviderName?
        ) async throws {
            let stub = HTTPStub(response)
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            let error = try await #require(throws: OpenRouterError.self) { try await session.respond(to: "Hi") }

            #expect(error.code == .invalidResponse)
            #expect(error.providerName == host)
            #expect(stub.requests.count == 1)
        }
    }
}
