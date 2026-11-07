import Foundation
import FoundationModels
import LanguageModels
import Testing
import UniformTypeIdentifiers

/// A text segment.
func text(_ content: String) -> Transcript.Segment {
    .text(.init(content: content))
}

/// The keys of an object, in order.
func keys(_ value: JSONValue?) -> [String] {
    if case .object(let object)? = value { object.members.map(\.key) } else { [] }
}

/// A model a request may reach.
struct Reached: ModelDetails {
    /// The id of a model a request may reach.
    struct ID: ProviderVocabulary {
        let rawValue: String
    }

    /// The day its provider stopped listing the model.
    var removedOn: Date?

    /// Confirms each read of ``removalDate``, which is how a request looks for a removed model.
    var reads: Confirmation?

    let id: ID = "vendor/model"
    let displayName = "Model"
    let capabilities = LanguageModelCapabilities([])
    let reasoning = ModelReasoning.unsupported
    let contextSize: Int? = nil
    let reasoningEfforts: [Efforts.Unsupported] = []
    let defaultReasoningEffort: Efforts.Unsupported? = nil
    var removalDate: Date? {
        reads?()
        return removedOn
    }
    let dataAttachmentTypes: Set<UTType> = []
    let dataEntryTypes: Set<UTType> = []
}
