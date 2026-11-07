import CustomDump
import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// The transcripts of the recorded exchanges, as apps have saved them, each beside the bytes its next turn sends. They
/// hold what OpenRouter really reported, and saved transcripts outlive the code that wrote them, so these files never
/// change.
@Suite("Recorded transcripts", .timeLimit(.minutes(1)))
struct RecordedTranscriptTests {
    static let scenarios: [RecordedScenario] = [
        .text, .reasoning, .signedReasoning, .tools, .guided, .options, .serviceTier, .routing, .webSearch, .responseCacheHit, .promptCache,
    ]

    /// The transcripts of every Xcode and system, then the one that needs the newer ones to read its attachments.
    static let allScenarios: [RecordedScenario] = {
        #if canImport(FoundationModels, _version: 2.1.14)
        if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) {
            return scenarios + [.attachments]
        }
        #endif
        return scenarios
    }()

    @Test(arguments: allScenarios)
    func `a recorded transcript sends the same bytes on its next turn, its JPEGs aside`(scenario: RecordedScenario) async throws {
        let saved = try Bundle.module.fixture("Transcripts/recorded-\(scenario.name).next-turn.json")

        let sent = try await Self.nextTurn(after: Self.transcript(scenario), of: scenario)

        expectNoDifference(
            ExactExchange.withoutJPEGs(String(decoding: sent, as: UTF8.self)),
            ExactExchange.withoutJPEGs(String(decoding: saved, as: UTF8.self))
        )
    }

    @Test func `a recorded transcript reads the same through the typed readers`() throws {
        let readings = try Self.scenarios.map { scenario in
            let facts = try Self.transcript(scenario).compactMap { entry -> String? in
                switch entry {
                case .response(let response): "response \(SavedTranscriptTests.facts(response.openRouter))"
                case .toolCalls(let calls): "toolCalls \(SavedTranscriptTests.facts(calls.openRouter))"
                default: nil
                }
            }
            return ([scenario.name] + facts).joined(separator: "\n")
        }

        assertInlineSnapshot(of: readings.joined(separator: "\n\n"), as: .lines) {
            """
            text
            response model: mistralai/mistral-nemo, provider: DekaLLM, responseID: gen-1794001075-yf9TzUNNrW9Wui7QQzsr, finishReason: stop, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00000024, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.00000024, upstreamInferencePromptCost: 0.00000018, upstreamInferenceCompletionCost: 0.00000006, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            reasoning
            response model: openai/gpt-5-nano, provider: OpenAI, responseID: gen-1794001077-6fBZduGtFnS6mmgx2YCK, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.0000657, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.0000657, upstreamInferencePromptCost: 0.0000009, upstreamInferenceCompletionCost: 0.0000648, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            signed-reasoning
            response model: anthropic/claude-haiku-4.5, provider: Amazon Bedrock, responseID: gen-1794001079-rvuRbSJCQNYWZ0LFOBQc, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.001234, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.001234, upstreamInferencePromptCost: 0.000049, upstreamInferenceCompletionCost: 0.001185, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            response model: anthropic/claude-haiku-4.5, provider: Amazon Bedrock, responseID: gen-1794001081-zuazVI6uaD1QJS8mbLFB, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.001709, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.001709, upstreamInferencePromptCost: 0.000154, upstreamInferenceCompletionCost: 0.001555, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            tools
            toolCalls model: openai/gpt-5-nano, provider: OpenAI, responseID: gen-1794001289-cdMEXQLlZCwGe1t3xrGe, finishReason: tool_calls, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00004455, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.00004455, upstreamInferencePromptCost: 0.00000335, upstreamInferenceCompletionCost: 0.0000412, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            response model: openai/gpt-5-nano, provider: OpenAI, responseID: gen-1794001292-LlcHyJ5MLAMAugdNvdT5, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.0000953, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.0000953, upstreamInferencePromptCost: 0.0000093, upstreamInferenceCompletionCost: 0.000086, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            guided
            response model: openai/gpt-5-nano, provider: OpenAI, responseID: gen-1794001086-c5uAMBtz7tuchUdsLPAG, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.0000731, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.0000731, upstreamInferencePromptCost: 0.0000059, upstreamInferenceCompletionCost: 0.0000672, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            options
            response model: openai/gpt-4o-mini, provider: OpenAI, responseID: gen-1794002503-FK3d9nqCDcOIIojtNbnL, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00001575, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.00001575, upstreamInferencePromptCost: 0.00000315, upstreamInferenceCompletionCost: 0.0000126, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            service-tier
            response model: openai/gpt-5-nano, provider: OpenAI, responseID: gen-1794002505-xg5TZ448CsoD2SNZVUzH, finishReason: stop, serviceTier: flex, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.000008725, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.000008725, upstreamInferencePromptCost: 0.000000325, upstreamInferenceCompletionCost: 0.0000084, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            routing
            response model: openai/gpt-5-nano, provider: OpenAI, responseID: gen-1794002510-nWI8pfYxvs55wOoCi8CU, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: fallback, routingAttempt: 1, routingAttempts: [], routingEndpoints: ["OpenAI openai/gpt-5-nano-2025-08-07 true"], routingPipeline: ["guardrail content-filter No PII detected (regex)"], region: IAD, generationTime: 2.314 seconds, cost: 0.00008785, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.00008785, upstreamInferencePromptCost: 0.00000065, upstreamInferenceCompletionCost: 0.0000872, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            web-search
            response model: openai/gpt-5-nano, provider: OpenAI, responseID: gen-1794002513-bqtPHYwdQSw74BsQuOA8, finishReason: stop, serviceTier: default, citations: ["https://www.bbc.co.uk/sport/football/63932622 https://www.bbc.co.uk/sport/football/63932622"], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.0105357, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.0105357, upstreamInferencePromptCost: 0.0004441, upstreamInferenceCompletionCost: 0.0000916, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: 1

            response-cache-hit
            response model: nil, provider: nil, responseID: nil, finishReason: nil, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: nil, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            response model: mistralai/mistral-nemo, provider: DekaLLM, responseID: gen-1794002551-C6lD5ZoBnHGYsT3mUeWV, finishReason: stop, serviceTier: nil, citations: [], responseCacheStatus: HIT, responseCacheAge: 1.0 seconds, responseCacheSourceID: gen-1794002549-Xq7RkT2mZpLw9VbN4sYc, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0, upstreamInferencePromptCost: 0, upstreamInferenceCompletionCost: 0, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            prompt-cache
            response model: anthropic/claude-haiku-4.5, provider: Amazon Bedrock, responseID: gen-1794002553-GZvepZJaxcjyYnGZ0VyR, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.0067905, cacheWriteTokenCount: 5402, isBYOK: false, upstreamInferenceCost: 0.0067905, upstreamInferencePromptCost: 0.0067655, upstreamInferenceCompletionCost: 0.000025, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            response model: anthropic/claude-haiku-4.5, provider: Amazon Bedrock, responseID: gen-1794002554-EIpApoqCaq6nMIpL32xu, finishReason: stop, serviceTier: default, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.0005922, cacheWriteTokenCount: 0, isBYOK: false, upstreamInferenceCost: 0.0005922, upstreamInferencePromptCost: 0.0005672, upstreamInferenceCompletionCost: 0.000025, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            """
        }
    }

    private static func transcript(_ scenario: RecordedScenario) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: Bundle.module.fixture("Transcripts/recorded-\(scenario.name).json"))
    }

    /// The bytes a session sends for one more prompt after a transcript, on the scenario's model.
    static func nextTurn(after transcript: Transcript, of scenario: RecordedScenario) async throws -> Data {
        let stub = HTTPStub(events(text("Noted."), done()))
        _ = try await LanguageModelSession(model: scenario.languageModel(stub), tools: scenario.tools, transcript: transcript).respond(
            to: "And next?")
        return try #require(stub.requests.first).body
    }
}
