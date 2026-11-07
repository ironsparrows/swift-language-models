package import FoundationModels
import LanguageModelsCore

/// The provider and API format that wrote a reasoning entry, as the entry's metadata names it.
///
/// Each provider tags the reasoning entries it writes, and sends back only reasoning with its own tag: a session can
/// switch models, and reasoning that another provider wrote, in its own format, means nothing to this one. A provider
/// that answers through more than one API format, such as Chat Completions and Responses, gives each format its own
/// value, since each sends reasoning back in another shape. Saved transcripts keep the tag, so its key and each
/// value never change.
package struct ReasoningOrigin: RawRepresentable, Hashable, Sendable {
    /// The metadata key under which a reasoning entry names the provider that wrote it.
    package static let metadataKey = "reasoningOrigin"

    /// The provider's name, as the metadata spells it.
    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The provider that wrote a reasoning entry, or `nil` when the entry names none, such as one from a model outside
    /// this package.
    ///
    /// - Parameter reasoning: The entry whose metadata is read.
    package init?(of reasoning: Transcript.Reasoning) {
        guard case .string(let name)? = reasoning.metadata[Self.metadataKey]?.kind else { return nil }
        self.init(rawValue: name)
    }
}

extension Transcript.Reasoning {
    /// The model that wrote the entry, as its answer named it, or `nil` when the entry doesn't say.
    package var writer: String? {
        MetadataValues(metadata).string(LanguageModelMetadataKey.model)
    }
}
