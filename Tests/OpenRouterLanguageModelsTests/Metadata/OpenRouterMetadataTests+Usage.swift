import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterMetadataTests {
    @Suite("Usage")
    struct Usage {
        @Test func `every part of the cost and every count reaches the usage as typed values`() async throws {
            let usage: JSONValue = [
                "prompt_tokens": 12, "completion_tokens": 5, "total_tokens": 17, "cost": 0.000_1, "is_byok": true,
                "prompt_tokens_details": ["cached_tokens": 0, "cache_write_tokens": 176],
                "cost_details": [
                    "upstream_inference_cost": 0.002, "upstream_inference_prompt_cost": 0.000_5,
                    "upstream_inference_completions_cost": 0.001_5, "server_tool_cost": 0.01,
                ],
                "server_tool_use_details": ["tool_calls_requested": 3, "tool_calls_executed": 2, "web_search_requests": 1],
            ]
            let stub = HTTPStub(events(text("Hi"), chunk([:], finishReason: "stop", usage: usage)))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            let metadata = response.usage.openRouter
            #expect(metadata.cost == Decimal(string: "0.0001"))
            #expect(metadata.cacheWriteTokenCount == 176)
            #expect(metadata.isBYOK == true)
            #expect(metadata.upstreamInferenceCost == Decimal(string: "0.002"))
            #expect(metadata.upstreamInferencePromptCost == Decimal(string: "0.0005"))
            #expect(metadata.upstreamInferenceCompletionCost == Decimal(string: "0.0015"))
            #expect(metadata.serverToolCost == Decimal(string: "0.01"))
            #expect(metadata.requestedServerToolCallCount == 3)
            #expect(metadata.executedServerToolCallCount == 2)
            #expect(metadata.webSearchCount == 1)
        }

        @Test func `a response whose tool calls ran has the last request's facts, and the session's usage has none`() async throws {
            let first: JSONValue = ["prompt_tokens": 10, "completion_tokens": 2, "cost": 0.001, "is_byok": true]
            let last: JSONValue = ["prompt_tokens": 20, "completion_tokens": 3, "cost": 0.002]
            let stub = HTTPStub(
                events(
                    toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    chunk([:], finishReason: "tool_calls", usage: first)),
                events(text("100 kcal."), chunk([:], finishReason: "stop", usage: last))
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            let response = try await session.respond(to: "Calories in an egg?")

            #expect(response.usage.openRouter.cost == Decimal(string: "0.002"))
            #expect(response.usage.openRouter.isBYOK == nil)
            #expect(session.usage.openRouter.cost == nil)
        }

        @Test func `each request's facts are on the entry that ends it, so a response's costs add up`() async throws {
            let first: JSONValue = ["prompt_tokens": 10, "completion_tokens": 2, "cost": 0.001, "is_byok": true]
            let last: JSONValue = ["prompt_tokens": 20, "completion_tokens": 3, "cost": 0.002]
            let stub = HTTPStub(
                events(
                    toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    chunk([:], finishReason: "tool_calls", usage: first)),
                events(text("100 kcal."), chunk([:], finishReason: "stop", usage: last))
            )

            let response = try await LanguageModelSession(model: model(stub), tools: [FoodTool()]).respond(to: "Calories in an egg?")

            var costs: [Decimal?] = []
            for entry in response.transcriptEntries {
                switch entry {
                case .toolCalls(let calls):
                    #expect(calls.openRouter.usage.isBYOK == true)
                    costs.append(calls.openRouter.usage.cost)
                case .response(let answer):
                    costs.append(answer.openRouter.usage.cost)
                default:
                    break
                }
            }
            #expect(costs == [Decimal(string: "0.001"), Decimal(string: "0.002")])
        }

        @Test(arguments: [
            (0.000_012_345, "0.000012345"),
            (0.000_25, "0.00025"),
            (0.000_000_15, "0.00000015"),
            (0.1, "0.1"),
            (123_456_789.123, "123456789.123"),
            (0, "0"),
        ])
        func `a cost reads as the decimal OpenRouter sent, without binary noise`(dollars: Double, expected: String) {
            let usage = usage(metadata: [LanguageModelMetadataKey.cost: dollars])

            #expect(usage.openRouter.cost == Decimal(string: expected))
        }

        @Test func `a usage without OpenRouter's facts reads each as unknown`() {
            let metadata = usage(metadata: [:]).openRouter

            let amounts = [
                metadata.cost, metadata.upstreamInferenceCost, metadata.upstreamInferencePromptCost,
                metadata.upstreamInferenceCompletionCost, metadata.serverToolCost,
            ]
            let counts = [
                metadata.cacheWriteTokenCount, metadata.requestedServerToolCallCount, metadata.executedServerToolCallCount,
                metadata.webSearchCount,
            ]
            #expect(amounts.allSatisfy { $0 == nil })
            #expect(counts.allSatisfy { $0 == nil })
            #expect(metadata.isBYOK == nil)
        }

        @Test func `a value of another kind, a count that isn't whole or an amount that isn't finite reads as unknown`() {
            let metadata = usage(metadata: [
                LanguageModelMetadataKey.cost: "0.0001",
                OpenRouterMetadataKey.isBYOK: 1,
                LanguageModelMetadataKey.webSearchCount: 1.5,
                OpenRouterMetadataKey.serverToolCost: GeneratedContent(kind: .number(.infinity)),
            ]).openRouter

            #expect(metadata.cost == nil)
            #expect(metadata.isBYOK == nil)
            #expect(metadata.webSearchCount == nil)
            #expect(metadata.serverToolCost == nil)
        }

        /// A usage with no tokens and the given metadata.
        private func usage(metadata: [String: any ConvertibleToGeneratedContent]) -> LanguageModelSession.Usage {
            LanguageModelSession.Usage(
                input: .init(totalTokenCount: 0, cachedTokenCount: 0), output: .init(totalTokenCount: 0, reasoningTokenCount: 0),
                metadata: metadata)
        }
    }
}
