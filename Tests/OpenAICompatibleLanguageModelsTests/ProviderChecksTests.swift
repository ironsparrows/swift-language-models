import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

@Suite("Provider checks", .timeLimit(.minutes(1)))
struct ProviderChecksTests {
    @Test func `a model on a provider that speaks Chat Completions makes the checks every provider's model makes`() async throws {
        try await checkProvider(
            model: { model($0) },
            reaching: ["test-model"],
            reach: { $0.chatCompletions($0.executorConfiguration).reachableModels },
            answering: { chunks(text($0), finish()) })
    }

    @Test func `a model on a provider that speaks Responses makes the checks every provider's model makes`() async throws {
        try await checkProvider(
            model: { model($0, format: .responses) },
            reaching: ["test-model"],
            reach: { $0.responses($0.executorConfiguration).reachableModels },
            answering: { events(textDelta($0), completed()) })
    }
}
