import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

@Suite("Provider checks", .timeLimit(.minutes(1)))
struct ProviderChecksTests {
    @Test func `OpenAI's model makes the checks every provider's model makes`() async throws {
        try await checkProvider(
            model: { reasoningModel($0) },
            reaching: ["gpt-test"],
            reach: { try $0.responses($0.executorConfiguration).reachableModels },
            answering: { events(textDelta($0), lifecycle("response.completed")) })
    }
}
