import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAILanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite("Reasoning")
    struct Reasoning {
        @Test(
            arguments: [
                (LiveModel.luna, ContextOptions.ReasoningLevel.off), (.luna, .light), (.nano, .minimal), (.nano, .off),
            ] as [(LiveModel, ContextOptions.ReasoningLevel)])
        func `each reasoning level goes as an effort the model takes`(model: LiveModel, level: ContextOptions.ReasoningLevel) async throws {
            let session = LanguageModelSession(model: try model.languageModel())

            let response = try await session.respond(
                to: "What is 17 × 23? Reply with the number only.", options: GenerationOptions(maximumResponseTokens: 2_000),
                contextOptions: ContextOptions(reasoningLevel: level))

            #expect(response.content.contains("391"))
            if level == .off, model.quickLevel == .off { #expect(response.usage.output.reasoningTokenCount == 0) }
        }

        /// The catalog records GPT-5.4 mini as reasoning by default, which its own default effort, `none`, contradicts.
        @Test func `GPT-5.4 mini doesn't reason when a request sets no level`() async throws {
            let session = LanguageModelSession(model: try LiveModel.gpt54Mini.languageModel())

            let response = try await session.respond(
                to: "What is 17 × 23? Reply with the number only.", options: GenerationOptions(maximumResponseTokens: 2_000))

            #expect(response.content.contains("391"))
            #expect(response.usage.output.reasoningTokenCount == 0)
        }

        @Test(arguments: [LiveModel.nano, .gpt54Mini, .luna])
        func `a temperature with no reasoning level goes only to a model that can stop reasoning, and each answers`(
            model: LiveModel
        ) async throws {
            let session = LanguageModelSession(model: try model.languageModel())

            let response = try await session.respond(
                to: "What is 17 × 23? Reply with the number only.",
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 2_000))

            #expect(response.content.contains("391"))
        }

        @Test(arguments: [OpenAIOptions.ReasoningSummary.auto, nil] as [OpenAIOptions.ReasoningSummary?])
        func `a reasoning summary shows as the reasoning entry's text, and the entry carries its reasoning without one`(
            summary: OpenAIOptions.ReasoningSummary?
        ) async throws {
            let session = LanguageModelSession(model: try LiveModel.luna.languageModel(options: OpenAIOptions(reasoningSummary: summary)))

            let response = try await session.respond(
                to:
                    "A train leaves at 9:47 and arrives at 13:18, with a 23-minute stop on the way. How many minutes is it moving? Reply with the number only.",
                options: GenerationOptions(maximumResponseTokens: 4_000), contextOptions: ContextOptions(reasoningLevel: .deep))

            #expect(response.content.contains("188"))
            let reasoning = try #require(reasoningEntries(in: response.transcriptEntries).first)
            #expect(reasoning.signature != nil)
            let text = reasoning.segments.compactMap { segment in if case .text(let text) = segment { text.content } else { nil } }.joined()
            record(text, named: "summary.txt")
            if summary == nil {
                #expect(text.isEmpty)
            } else {
                // A model that reasons only briefly may send an empty summary, as OpenAI does for a short answer.
                withKnownIssue("OpenAI may send no summary for brief reasoning.", isIntermittent: true) { #expect(!text.isEmpty) }
            }
        }
    }
}
