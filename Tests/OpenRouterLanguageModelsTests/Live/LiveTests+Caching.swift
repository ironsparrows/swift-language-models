import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite("Caching")
    struct Caching {
        /// Models that cache on their own, or with the marks that automatic caching sends, but don't promise a hit.
        /// Gemini is marked too, which switches it to explicit caching.
        static let bestEffortModels = [
            LiveModel(.openaiGpt4_1Nano),
            LiveModel(.googleGemini2_5FlashLite),
            LiveModel(.googleGemini2_5FlashLite, cacheControl: .always),
            LiveModel(.deepseekDeepseekV4Flash),
            LiveModel(.qwenQwen3_7Flash),
        ]

        /// Automatic caching marks Claude's prompts. Each of Claude's hosts keeps its own cache, so both turns go to
        /// Anthropic's own host.
        @Test func `a marked prompt is written on the first turn and read on the next`() async throws {
            let model = LiveModel(.anthropicClaudeHaiku5_5)
            let routing = OpenRouterRouting(order: ["anthropic"], fallbackProviders: .disallowed)
            let session = LanguageModelSession(
                model: model.languageModel(routing: routing), instructions: longInstructions(tokens: 2_500))

            let first = try await session.respond(to: "Reply with OK.", options: LiveTests.short)
            let second = try await session.respond(to: "Reply with OK again.", options: LiveTests.short)

            record([first.usage, second.usage], named: "usage.txt")
            let providers = [first, second].map { response in
                lastAnswer(in: response.transcriptEntries).flatMap { $0.openRouter.provider?.rawValue }
                    ?? "none"
            }
            record(providers, named: "providers.txt")
            #expect(first.usage.input.cachedTokenCount == 0)
            #expect((first.usage.openRouter.cacheWriteTokenCount ?? 0) > 0)
            #expect(second.usage.input.cachedTokenCount >= 2_000)
            #expect(second.usage.input.cachedTokenCount <= second.usage.input.totalTokenCount)
            let firstCost = try #require(first.usage.openRouter.cost)
            let secondCost = try #require(second.usage.openRouter.cost)
            #expect(secondCost < firstCost)
        }

        @Test(arguments: bestEffortModels)
        func `a later turn reads the cached prompt`(model: LiveModel) async throws {
            let session = LanguageModelSession(model: model.languageModel, instructions: longInstructions(tokens: 4_500))

            var turns: [LanguageModelSession.Response<String>] = []
            for turn in 1...3 {
                turns.append(try await session.respond(to: "Reply with OK for turn \(turn).", options: LiveTests.short))
                if turn > 1, turns[turn - 1].usage.input.cachedTokenCount > 0 { break }
                try await Task.sleep(for: .seconds(2))
            }

            record(turns.map(\.usage), named: "usage.txt")
            for response in turns {
                #expect(response.usage.input.cachedTokenCount <= response.usage.input.totalTokenCount)
            }
            withKnownIssue("This provider caches when it can, not on every request.", isIntermittent: true) {
                #expect(turns.dropFirst().contains { $0.usage.input.cachedTokenCount > 0 })
            }
        }

        /// Instructions of about the given length, starting with a value new to this run, so the first turn writes
        /// the cache instead of reading an earlier run's.
        private func longInstructions(tokens: Int) -> String {
            // Each rule is about 17 tokens.
            let rules = (1...(tokens / 17 + 1)).map { number in
                "Rule \(number): when asked about item \(number), answer with the code \(String(number, radix: 36).uppercased())."
            }
            return (["Run \(UUID().uuidString). Follow these rules."] + rules).joined(separator: "\n")
        }
    }
}
