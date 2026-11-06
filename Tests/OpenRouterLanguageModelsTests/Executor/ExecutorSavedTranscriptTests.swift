import CustomDump
import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// The transcripts of the exact exchanges, as apps have saved them, each beside the bytes its next turn sends. Saved
/// transcripts outlive the code that wrote them, so these files never change.
@Suite("Executor: saved transcripts")
struct ExecutorSavedTranscriptTests {
    static let names = ["text-alone", "parallel-tools", "portable-schema-retry", "tagged-reasoning", "reasoning-details", "fallbacks"]

    /// The transcripts of every Xcode and system, then the one that needs the newer ones to read its attachments.
    static let allNames: [String] = {
        #if canImport(FoundationModels, _version: 2.1.14)
        if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) {
            return names + ["attachments"]
        }
        #endif
        return names
    }()

    @Test(arguments: allNames)
    func `a saved transcript sends the same bytes on its next turn, its JPEGs aside`(name: String) async throws {
        let saved = try Bundle.module.fixture("Transcripts/\(name).next-turn.json")

        let sent = try await Self.nextTurn(after: name)

        expectNoDifference(
            ExactExchange.withoutJPEGs(String(decoding: sent, as: UTF8.self)),
            ExactExchange.withoutJPEGs(String(decoding: saved, as: UTF8.self))
        )
    }

    @Test func `a saved transcript reads the same through the typed readers`() throws {
        let readings = try Self.names.map { name in
            let facts = try Self.transcript(name).compactMap { entry -> String? in
                switch entry {
                case .response(let response): "response \(Self.facts(response.openRouter))"
                case .toolCalls(let calls): "toolCalls \(Self.facts(calls.openRouter))"
                default: nil
                }
            }
            return ([name] + facts).joined(separator: "\n")
        }

        assertInlineSnapshot(of: readings.joined(separator: "\n\n"), as: .lines) {
            """
            text-alone
            response model: vendor/model, provider: Vendor, responseID: gen-1, finishReason: stop, serviceTier: flex, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00025, cacheWriteTokenCount: 2, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            parallel-tools
            response model: nil, provider: nil, responseID: nil, finishReason: nil, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: nil, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            toolCalls model: vendor/model, provider: Vendor, responseID: gen-1, finishReason: tool_calls, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00025, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            response model: vendor/model, provider: Vendor, responseID: gen-1, finishReason: stop, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00025, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            portable-schema-retry
            response model: vendor/model, provider: Vendor, responseID: gen-1, finishReason: stop, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00025, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            tagged-reasoning
            response model: vendor/model, provider: Vendor, responseID: gen-1, finishReason: stop, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00025, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            reasoning-details
            response model: nil, provider: nil, responseID: nil, finishReason: nil, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: nil, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            response model: vendor/model, provider: Vendor, responseID: gen-1, finishReason: stop, serviceTier: nil, citations: [], responseCacheStatus: nil, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: nil, routingAttempt: nil, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: nil, generationTime: nil, cost: 0.00025, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil

            fallbacks
            response model: vendor/fallback, provider: Vendor, responseID: gen-1, finishReason: stop, serviceTier: nil, citations: [], responseCacheStatus: MISS, responseCacheAge: nil, responseCacheSourceID: nil, routingStrategy: fallback, routingAttempt: 2, routingAttempts: [], routingEndpoints: [], routingPipeline: [], region: iad, generationTime: nil, cost: 0.00025, cacheWriteTokenCount: nil, isBYOK: nil, upstreamInferenceCost: nil, upstreamInferencePromptCost: nil, upstreamInferenceCompletionCost: nil, serverToolCost: nil, requestedServerToolCallCount: nil, executedServerToolCallCount: nil, webSearchCount: nil
            """
        }
    }

    /// A saved transcript.
    static func transcript(_ name: String) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: Bundle.module.fixture("Transcripts/\(name).json"))
    }

    /// The bytes a session sends for one more prompt after a saved transcript, on a model like the one that wrote it.
    static func nextTurn(after name: String) async throws -> Data {
        let transcript = try transcript(name)
        let hasCalls = transcript.contains { if case .toolCalls = $0 { true } else { false } }
        let stub = HTTPStub(events(text("Noted."), done()))
        let reasons = ["tagged-reasoning", "reasoning-details"].contains(name)
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(
            stub, inputs: [.text, .image, .file, .audio], reasoning: reasons ? .onByDefault : .offByDefault)
        let session = LanguageModelSession(model: model, tools: hasCalls ? [FoodTool()] : [], transcript: transcript)
        _ = try await session.respond(to: "And next?")
        return try #require(stub.requests.first).body
    }

    /// Every fact the reader gives.
    static func facts(_ metadata: OpenRouterResponseMetadata) -> String {
        func text(_ value: (some Any)?) -> String { value.map { String(describing: $0) } ?? "nil" }
        let usage = metadata.usage
        let attempts = metadata.routingAttempts.map { "\(text($0.provider?.rawValue)) \(text($0.model?.rawValue)) \(text($0.status))" }
        let endpoints = metadata.routingEndpoints.map {
            "\(text($0.provider?.rawValue)) \(text($0.model?.rawValue)) \(text($0.isSelected))"
        }
        let pipeline = metadata.routingPipeline.map { "\(text($0.kind?.rawValue)) \(text($0.plugin)) \(text($0.summary))" }
        return """
            model: \(text(metadata.model?.rawValue)), provider: \(text(metadata.provider?.rawValue)), responseID: \(text(metadata.responseID)), \
            finishReason: \(text(metadata.finishReason?.rawValue)), serviceTier: \(text(metadata.serviceTier?.rawValue)), \
            citations: \(metadata.citations.map { "\($0.url) \(text($0.title))" }), responseCacheStatus: \(text(metadata.responseCacheStatus)), \
            responseCacheAge: \(text(metadata.responseCacheAge)), responseCacheSourceID: \(text(metadata.responseCacheSourceID)), \
            routingStrategy: \(text(metadata.routingStrategy)), routingAttempt: \(text(metadata.routingAttempt)), \
            routingAttempts: \(attempts), routingEndpoints: \(endpoints), routingPipeline: \(pipeline), region: \(text(metadata.region)), \
            generationTime: \(text(metadata.generationTime)), cost: \(text(usage.cost)), cacheWriteTokenCount: \(text(usage.cacheWriteTokenCount)), \
            isBYOK: \(text(usage.isBYOK)), upstreamInferenceCost: \(text(usage.upstreamInferenceCost)), \
            upstreamInferencePromptCost: \(text(usage.upstreamInferencePromptCost)), \
            upstreamInferenceCompletionCost: \(text(usage.upstreamInferenceCompletionCost)), serverToolCost: \(text(usage.serverToolCost)), \
            requestedServerToolCallCount: \(text(usage.requestedServerToolCallCount)), \
            executedServerToolCallCount: \(text(usage.executedServerToolCallCount)), webSearchCount: \(text(usage.webSearchCount))
            """
    }
}
