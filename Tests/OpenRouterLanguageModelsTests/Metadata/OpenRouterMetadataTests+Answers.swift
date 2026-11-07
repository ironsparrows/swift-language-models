import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterMetadataTests {
    @Suite("Answers")
    struct Answers {
        @Test func `usage without cost details or server-tool counts leaves their keys out`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            let keys = [
                OpenRouterMetadataKey.isBYOK, OpenRouterMetadataKey.upstreamInferenceCost,
                OpenRouterMetadataKey.upstreamInferencePromptCost,
                OpenRouterMetadataKey.upstreamInferenceCompletionCost, OpenRouterMetadataKey.serverToolCost,
                OpenRouterMetadataKey.requestedServerToolCallCount, OpenRouterMetadataKey.executedServerToolCallCount,
                LanguageModelMetadataKey.webSearchCount,
            ]
            #expect(keys.allSatisfy { response.usage.metadata[$0] == nil })
            #expect(metadataNumber(response.usage.metadata, LanguageModelMetadataKey.cost) == 0.000_25)
        }

        @Test func `a null upstream cost and null server-tool counts are left out`() async throws {
            let usage: JSONValue = [
                "prompt_tokens": 12, "completion_tokens": 5, "total_tokens": 17, "is_byok": false,
                "cost_details": [
                    "upstream_inference_cost": .null, "upstream_inference_prompt_cost": 0, "upstream_inference_completions_cost": 0,
                ],
                "server_tool_use_details": .null,
            ]
            let stub = HTTPStub(events(text("Hi"), chunk([:], finishReason: "stop", usage: usage)))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            let metadata = response.usage.metadata
            #expect(try metadataJSON(metadata, OpenRouterMetadataKey.isBYOK) == false)
            #expect(metadata[OpenRouterMetadataKey.upstreamInferenceCost] == nil)
            #expect(try metadataJSON(metadata, OpenRouterMetadataKey.upstreamInferencePromptCost) == 0)
            #expect(metadata[LanguageModelMetadataKey.webSearchCount] == nil)
        }

        @Test func `a tool round's facts reach its first call, and its tool-calls entry reads them`() async throws {
            let stub = HTTPStub(
                events(
                    from: "vendor/round-model",
                    toolCall(0, id: "call_egg", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    toolCall(1, id: "call_rice", name: "lookUpFood", arguments: #"{"food":"rice"}"#),
                    done("tool_calls")
                ),
                events(text("An egg has 100 kcal, and rice 130."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            _ = try await session.respond(to: "Calories in an egg and in rice?")

            let rounds = session.transcript.compactMap { entry -> Transcript.ToolCalls? in
                if case .toolCalls(let calls) = entry { calls } else { nil }
            }
            let calls = try #require(rounds.first)
            #expect(rounds.count == 1)
            #expect(calls.count == 2)
            #expect(calls.openRouter.model == "vendor/round-model")
            #expect(calls.openRouter.provider == "Vendor")
            #expect(calls.openRouter.responseID == "gen-1")
            #expect(calls.openRouter.finishReason == .toolCalls)
            #expect(calls.last?.metadata.isEmpty == true)
        }
    }
}
