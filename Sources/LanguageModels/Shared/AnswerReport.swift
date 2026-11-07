package import FoundationModels
package import LanguageModelsCore

/// What an answer's stream reports about it in a format's own members: the model that answered, the response id, the
/// service tier, the usage and why the answer ended.
///
/// Each format fills it from its own events. A fact that an event reports replaces the earlier one, and one it leaves
/// out keeps its earlier value.
package struct AnswerReport {
    /// The model that answered, as the answer names it.
    package var model: String?

    /// The answer's id.
    package var responseID: String?

    /// The processing tier that served the answer, in the host's word for it.
    package var serviceTier: String?

    /// The usage as Foundation Models' running totals.
    package var usage: AnswerUsage?

    /// Why the answer ended, once an event says so. A stream that ends without one was cut off.
    package var finishReason: FinishReason?

    package init() {}

    /// The facts as metadata of the entry that ends the answer; the usage goes with the entry's usage instead.
    package var metadata: [String: any ConvertibleToGeneratedContent] {
        var metadata: [String: any ConvertibleToGeneratedContent] = [:]
        metadata[LanguageModelMetadataKey.model] = model
        metadata[LanguageModelMetadataKey.responseID] = responseID
        metadata[LanguageModelMetadataKey.finishReason] = finishReason?.rawValue
        metadata[LanguageModelMetadataKey.serviceTier] = serviceTier
        return metadata
    }
}
