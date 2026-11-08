import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

@Suite("Provider checks", .timeLimit(.minutes(1)))
struct ProviderChecksTests {
    @Test func `OpenRouter's model makes the checks every provider's model makes`() async throws {
        try await checkProvider(
            model: { model($0, fallbacks: [fallback("vendor/first"), fallback("vendor/second")]) },
            reaching: ["vendor/model", "vendor/first", "vendor/second"],
            reach: { try $0.chatCompletions($0.executorConfiguration).reachableModels },
            answering: { events(text($0), done()) })
    }
}
