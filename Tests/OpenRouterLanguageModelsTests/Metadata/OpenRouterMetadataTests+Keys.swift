import Foundation
import FoundationModels
import Testing

@testable import OpenRouterLanguageModels

/// A key as saved transcripts keep it, prefixed since only OpenRouter has the fact, a value under it, and whether the
/// reader reads that value as its fact.
private let responseKeys: [(spelling: String, value: GeneratedContent, reads: @Sendable (OpenRouterResponseMetadata) -> Bool)] = [
    ("openRouter.responseCacheStatus", GeneratedContent("HIT"), { $0.responseCacheStatus == .hit }),
    ("openRouter.responseCacheAge", GeneratedContent(kind: .number(12)), { $0.responseCacheAge == .seconds(12) }),
    ("openRouter.responseCacheSourceID", GeneratedContent("gen-1"), { $0.responseCacheSourceID == "gen-1" }),
    ("openRouter.routingStrategy", GeneratedContent("fallback"), { $0.routingStrategy == .fallback }),
    ("openRouter.routingAttempt", GeneratedContent(kind: .number(2)), { $0.routingAttempt == 2 }),
    (
        "openRouter.routingAttempts", GeneratedContent(kind: .array([GeneratedContent(properties: ["provider": "Vendor"])])),
        { $0.routingAttempts.map(\.provider) == ["Vendor"] }
    ),
    (
        "openRouter.routingEndpoints", GeneratedContent(kind: .array([GeneratedContent(properties: ["provider": "Vendor"])])),
        { $0.routingEndpoints.map(\.provider) == ["Vendor"] }
    ),
    (
        "openRouter.routingPipeline", GeneratedContent(kind: .array([GeneratedContent(properties: ["summary": "Blocked."])])),
        { $0.routingPipeline.map(\.summary) == ["Blocked."] }
    ),
    ("openRouter.region", GeneratedContent("iad"), { $0.region == "iad" }),
    ("openRouter.generationTime", GeneratedContent(kind: .number(2)), { $0.generationTime == .seconds(2) }),
    ("openRouter.isBYOK", GeneratedContent(kind: .bool(true)), { $0.usage.isBYOK == true }),
    ("openRouter.upstreamInferenceCost", GeneratedContent(kind: .number(0.5)), { $0.usage.upstreamInferenceCost == 0.5 }),
    ("openRouter.upstreamInferencePromptCost", GeneratedContent(kind: .number(0.5)), { $0.usage.upstreamInferencePromptCost == 0.5 }),
    (
        "openRouter.upstreamInferenceCompletionCost", GeneratedContent(kind: .number(0.5)),
        { $0.usage.upstreamInferenceCompletionCost == 0.5 }
    ),
    ("openRouter.serverToolCost", GeneratedContent(kind: .number(0.5)), { $0.usage.serverToolCost == 0.5 }),
    ("openRouter.requestedServerToolCallCount", GeneratedContent(kind: .number(3)), { $0.usage.requestedServerToolCallCount == 3 }),
    ("openRouter.executedServerToolCallCount", GeneratedContent(kind: .number(2)), { $0.usage.executedServerToolCallCount == 2 }),
]

extension OpenRouterMetadataTests {
    @Suite("Keys")
    struct Keys {
        @Test(arguments: responseKeys)
        func `each fact reads from the key that saved transcripts keep`(
            spelling: String, value: GeneratedContent, reads: @Sendable (OpenRouterResponseMetadata) -> Bool
        ) {
            #expect(reads(OpenRouterResponseMetadata([spelling: value])))
        }

        @Test func `the budget a failure ran into reads from its key`() {
            #expect(OpenRouterErrorMetadata(["openRouter.limitSource": "api_key"]).limitSource == .apiKey)
        }
    }
}
