import Foundation
import FoundationModels
import Testing

@testable import LanguageModels

@Suite("Answer facts")
struct AnswerFactsTests {
    @Test func `a fact that a chunk reports replaces the earlier one, and one it leaves out keeps its value`() throws {
        var facts = AnswerReport()

        facts.update(with: try chunk(["id": "gen-1", "model": "vendor/model", "provider": "Vendor", "service_tier": "flex"]))
        facts.update(
            with: try chunk([
                "model": "vendor/model-2026-10-01",
                "choices": [["delta": [:], "finish_reason": "length"]],
                "usage": ["prompt_tokens": 12, "completion_tokens": 5, "prompt_tokens_details": ["cache_write_tokens": 3]],
            ]))
        facts.update(with: try chunk(["choices": [["delta": [:]]]]))

        #expect(facts.responseID == "gen-1")
        #expect(facts.model == "vendor/model-2026-10-01")
        #expect(facts.serviceTier == "flex")
        #expect(facts.finishReason == .length)
        #expect(facts.usage?.input.totalTokenCount == 12)
        #expect(facts.usage?.output.totalTokenCount == 5)
        let usage = try #require(facts.usage).metadata.mapValues(\.generatedContent)
        #expect(usage[LanguageModelMetadataKey.cacheWriteTokenCount] == GeneratedContent(3))
    }

    @Test func `the metadata names the answer's facts`() throws {
        var facts = AnswerReport()

        facts.update(
            with: try chunk([
                "id": "gen-1", "model": "vendor/model", "service_tier": "priority", "choices": [["delta": [:], "finish_reason": "stop"]],
            ]))
        let metadata = facts.metadata.mapValues(\.generatedContent)

        #expect(metadata[LanguageModelMetadataKey.model] == GeneratedContent("vendor/model"))
        #expect(metadata[LanguageModelMetadataKey.responseID] == GeneratedContent("gen-1"))
        #expect(metadata[LanguageModelMetadataKey.finishReason] == GeneratedContent("stop"))
        #expect(metadata[LanguageModelMetadataKey.serviceTier] == GeneratedContent("priority"))
    }

    @Test func `facts that no chunk reported are left out of the metadata`() {
        #expect(AnswerReport().metadata.isEmpty)
    }
}

/// A chunk with the given members.
private func chunk(_ members: JSONValue) throws -> ChatCompletionChunk {
    try JSONDecoder().decode(ChatCompletionChunk.self, from: members.data)
}
