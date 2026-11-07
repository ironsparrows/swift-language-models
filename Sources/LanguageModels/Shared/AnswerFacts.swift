package import Foundation
package import FoundationModels

/// What a provider adds to an answer's facts, as the `facts(of:)` hook of each API format's dialect returns them.
package struct AnswerFacts {
    /// The company whose servers ran the model, as `LanguageModelMetadataKey.provider` names it, once known.
    package var host: String?

    /// The facts the provider adds to the metadata of the entry that ends the answer.
    package var metadata: [String: any ConvertibleToGeneratedContent]

    /// The facts the provider adds to the metadata of the answer's usage.
    package var usageMetadata: [String: any ConvertibleToGeneratedContent]

    /// The signature of the answer's reasoning entry, such as reasoning in the provider's form that goes back on later
    /// turns, or `nil` when there's none.
    package var reasoningSignature: Data?

    package init(
        host: String? = nil,
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        usageMetadata: [String: any ConvertibleToGeneratedContent] = [:],
        reasoningSignature: Data? = nil
    ) {
        self.host = host
        self.metadata = metadata
        self.usageMetadata = usageMetadata
        self.reasoningSignature = reasoningSignature
    }
}
