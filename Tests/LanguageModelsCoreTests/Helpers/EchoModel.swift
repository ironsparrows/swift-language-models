import Foundation
import FoundationModels
import LanguageModelsCore
import Testing
import UniformTypeIdentifiers

/// A model that answers every request with the reasoning level it received.
struct EchoModel<Effort: ModelEffort>: DetailedLanguageModel {
    struct Details: ModelDetails {
        var id: TestModelID = "echo"
        let displayName = "Echo"
        var capabilities = LanguageModelCapabilities([.toolCalling, .reasoning])
        let reasoning = ModelReasoning.offByDefault
        let contextSize: Int? = 1_000
        let reasoningEfforts: [Effort]
        var defaultReasoningEffort: Effort? { reasoningEfforts.first }
        var removedOn: Date?
        /// Confirms each read of ``removalDate``, which is how a request looks for a removed model.
        var reads: Confirmation?
        var removalDate: Date? {
            reads?()
            return removedOn
        }
        var dataAttachmentTypes: Set<UTType> = [.image]
        var dataEntryTypes: Set<UTType> = []
    }

    struct Executor: LanguageModelExecutor {
        struct Configuration: Hashable, Sendable {}

        init(configuration: Configuration) {}

        func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: EchoModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            model.reportRemovedModels(for: request)
            let level =
                switch request.contextOptions.reasoningLevel {
                case .custom(let value)?: value
                case .light?: "light"
                case .moderate?: "moderate"
                case .deep?: "deep"
                case nil: "default"
                @unknown default: "unknown"
                }
            await channel.send(.response(action: .appendText(level, tokenCount: 1)))
            try model.checkGuides(ofResponseText: level, for: request)
        }
    }

    var details: Details
    var fallbacks: [Details]

    var executorConfiguration: Executor.Configuration { .init() }

    init(efforts: [Effort], removedOn: Date? = nil, fallbacks: [Details] = []) {
        details = Details(reasoningEfforts: efforts, removedOn: removedOn)
        self.fallbacks = fallbacks
    }
}

/// The efforts of a model that accepts only `high` and `low`.
enum HighLowEffort: String, ModelEffort {
    case high
    case low
}
