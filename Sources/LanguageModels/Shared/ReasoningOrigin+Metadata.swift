package import FoundationModels
import LanguageModelsCore

extension ReasoningOrigin {
    /// The metadata of a reasoning entry this provider writes: its origin, the model that wrote it once known, and
    /// the block that opened the answer's text once the answer ended.
    ///
    /// - Parameters:
    ///   - model: The model that wrote the reasoning, as its answer named it, which `Transcript.Reasoning.writer`
    ///     reads back.
    ///   - taggedBlock: The block that opened the answer's text, such as `<think>…</think>`, which goes back there.
    /// - Returns: The metadata.
    package func metadata(model: String?, taggedBlock: String?) -> [String: any ConvertibleToGeneratedContent] {
        var metadata: [String: any ConvertibleToGeneratedContent] = [Self.metadataKey: rawValue]
        metadata[LanguageModelMetadataKey.model] = model
        metadata[TaggedReasoning.metadataKey] = taggedBlock
        return metadata
    }
}
