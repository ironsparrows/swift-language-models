import Foundation
import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing

extension RecordedExchangeTests {
    /// Two turns after the same long instructions, so the second repeats the first's request as its prefix, which each
    /// provider may read from its cache.
    @Suite("Caching")
    struct Caching {
        @Test func `a second turn's usage reads the tokens each provider says it took from its cache`() async throws {
            var usages: [String] = []
            for scenario in RecordedScenario.cached {
                let exchange = try await ExactExchange(replaying: scenario)
                usages.append("\(scenario.name): \(exchange.usage ?? "nil")")
            }

            assertInlineSnapshot(of: usages.joined(separator: "\n"), as: .lines) {
                """
                gemini-cached: input 6030 cached 2033, output 9 reasoning 0, metadata: {}
                groq-cached: input 3115 cached 0, output 17 reasoning 6, metadata: {}
                ollama-cached: input 2060 cached 2020, output 12 reasoning 0, metadata: {}
                """
            }
        }

        @Test(arguments: RecordedScenario.cached)
        func `a second turn sends the first turn's messages as its prefix, byte for byte`(scenario: RecordedScenario) async throws {
            let exchange = try await ExactExchange(replaying: scenario)

            let first = try #require(exchange.bodies.first)
            let second = try #require(exchange.bodies.last)
            let end = try #require(first.range(of: #"],"stream""#))
            #expect(exchange.bodies.count == 2)
            #expect(second.hasPrefix(first[..<end.lowerBound]))
            #expect(second.hasSuffix(first[end.lowerBound...]))
        }
    }
}
