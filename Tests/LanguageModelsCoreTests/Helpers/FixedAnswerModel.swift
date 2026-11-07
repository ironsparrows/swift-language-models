import Foundation
import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

/// A model that answers every request with the same text.
struct FixedAnswerModel: DetailedLanguageModel {
    struct Details: ModelDetails {
        let id: TestModelID = "fixed"
        let displayName = "Fixed"
        let capabilities = LanguageModelCapabilities([.guidedGeneration])
        let reasoning = ModelReasoning.unsupported
        let contextSize: Int? = 1_000
        let reasoningEfforts: [Efforts.Unsupported] = []
        let defaultReasoningEffort: Efforts.Unsupported? = nil
        let removalDate: Date? = nil
        let dataAttachmentTypes: Set<UTType> = []
        let dataEntryTypes: Set<UTType> = []
    }

    struct Executor: LanguageModelExecutor {
        struct Configuration: Hashable, Sendable {
            let answer: String
        }

        let configuration: Configuration

        func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: FixedAnswerModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            model.reportRemovedModels(for: request)
            await channel.send(.response(action: .appendText(configuration.answer, tokenCount: 1)))
            try model.checkGuides(ofResponseText: configuration.answer, for: request)
        }
    }

    let answer: String
    let details = Details()
    let fallbacks: [Details] = []

    var executorConfiguration: Executor.Configuration { .init(answer: answer) }
}
