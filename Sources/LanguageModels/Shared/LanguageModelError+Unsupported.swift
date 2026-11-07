package import FoundationModels
import LanguageModelsCore

extension LanguageModelError {
    /// The error for transcript content a provider can't take.
    package static func unsupported(_ entry: Transcript.Entry, _ description: String) -> LanguageModelError {
        .unsupportedTranscriptContent(.init(unsupportedContent: [entry], debugDescription: description))
    }

    /// The error for a capability a model doesn't have, such as tool calling.
    package static func unsupported(_ capability: LanguageModelCapabilities.Capability, _ description: String) -> LanguageModelError {
        .unsupportedCapability(.init(capability: capability, debugDescription: description))
    }
}
