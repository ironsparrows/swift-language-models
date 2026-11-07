import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels
@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Answers")
    struct Answers {
        @Test func `a fact that a chunk reports replaces the earlier one, and one it leaves out keeps its value`() throws {
            var exchange = try exchange()

            _ = exchange.read(try chunk(["id": "gen-1", "model": "vendor/model", "provider": "Vendor", "service_tier": "flex"]))
            _ = exchange.read(
                try chunk([
                    "model": "vendor/model-2026-10-01",
                    "choices": [["delta": [:], "finish_reason": "length"]],
                    "usage": ["prompt_tokens": 12, "completion_tokens": 5, "cost": 0.000_1],
                ]))
            _ = exchange.read(try chunk(["choices": [["delta": [:]]]]))
            let facts = exchange.additions(header: { _ in nil })

            #expect(facts.host == "Vendor")
            #expect(metadataNumber(facts.usageMetadata.mapValues(\.generatedContent), LanguageModelMetadataKey.cost) == 0.000_1)
        }

        @Test func `the metadata names the host, with the response cache's status and the router's report`() throws {
            var exchange = try exchange(options: OpenRouterOptions(includesRouterMetadata: true))

            _ = exchange.read(
                try chunk([
                    "id": "gen-1", "model": "vendor/model", "provider": "Vendor", "service_tier": "priority",
                    "choices": [["delta": [:], "finish_reason": "stop"]],
                    "openrouter_metadata": ["strategy": "price", "generation_time": 1_500],
                ]))
            let additions = exchange.additions(header: { $0 == "X-OpenRouter-Cache-Status" ? "MISS" : nil })
            let metadata = additions.metadata.mapValues(\.generatedContent)

            #expect(metadataString(metadata, LanguageModelMetadataKey.provider) == "Vendor")
            #expect(metadataString(metadata, OpenRouterMetadataKey.responseCacheStatus) == "MISS")
            #expect(metadataString(metadata, OpenRouterMetadataKey.routingStrategy) == "price")
            #expect(metadataNumber(metadata, OpenRouterMetadataKey.generationTime) == 1.5)
        }

        @Test func `facts that no chunk reported are left out of the metadata`() throws {
            let facts = try exchange().additions(header: { _ in nil })

            #expect(facts.metadata.isEmpty)
            #expect(facts.usageMetadata.isEmpty)
        }

        @Test func `a model that doesn't take tools gets none of the session's, nor a tool choice`() throws {
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(HTTPStub(), parameters: chatParameters.subtracting([.tools]))
            let request = LanguageModelExecutorGenerationRequest(
                id: UUID(), transcript: Transcript(entries: [.prompt(Transcript.Prompt(segments: [.text(.init(content: "Hi"))]))]),
                enabledTools: [Transcript.ToolDefinition(tool: FoodTool())],
                generationOptions: GenerationOptions(toolCallingMode: .required),
                contextOptions: ContextOptions(), metadata: [:])

            let body = try requestBody(request, model: model)

            #expect(body["tools"] == nil)
            #expect(body["tool_choice"] == nil)
        }

        @Test(arguments: [
            (StreamProblem.toolCallWithoutName, OpenRouterProviderName?.some("Vendor")),
            (.incompleteToolArguments(toolName: "order"), "Vendor"),
            (.cutOff, "Vendor"),
            (.unreadableEvent("bad JSON"), nil),
        ])
        func `a response the format can't use throws an invalid response, naming the host unless an event couldn't be read`(
            problem: StreamProblem,
            host: OpenRouterProviderName?
        ) throws {
            var exchange = try exchange()
            _ = exchange.read(try chunk(["provider": "Vendor"]))

            let failure = RequestFailure<OpenRouterErrorResponse>(
                problem, provider: "OpenRouter", headers: ResponseHeaders(nil), imageEntries: [])
            let error = try #require(exchange.error(for: failure) as? OpenRouterError)

            #expect(error.code == .invalidResponse)
            #expect(error.providerName == host)
            #expect(error.message == problem.message(provider: "OpenRouter"))
        }
    }
}

/// OpenRouter's exchange, for a stub model.
private func exchange(options: OpenRouterOptions = OpenRouterOptions()) throws -> OpenRouterExchange {
    let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(HTTPStub(), options: options)
    return try model.chatCompletions(model.executorConfiguration).exchange
}

/// OpenRouter's members of a chunk with the given members.
private func chunk(_ members: JSONValue) throws -> OpenRouterChunkExtras {
    try HTTPClient.decoder.decode(OpenRouterChunkExtras.self, from: members.data)
}
