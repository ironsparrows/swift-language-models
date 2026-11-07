package import FoundationModels
import LanguageModelsCore

/// An answer's usage as Foundation Models' running totals, with the prompt tokens written to the host's cache in the
/// metadata.
package struct AnswerUsage {
    package let input: LanguageModelExecutorGenerationChannel.Usage.Input
    package let output: LanguageModelExecutorGenerationChannel.Usage.Output
    package let metadata: [String: any ConvertibleToGeneratedContent]

    /// - Parameters:
    ///   - inputTokens: The prompt's tokens, cached ones included.
    ///   - cachedTokens: The prompt's tokens read from the host's cache.
    ///   - cacheWriteTokens: The prompt's tokens written to the host's cache, when the host reports them.
    ///   - outputTokens: The answer's tokens, reasoning included.
    ///   - reasoningTokens: The answer's reasoning tokens.
    package init(inputTokens: Int, cachedTokens: Int, cacheWriteTokens: Int?, outputTokens: Int, reasoningTokens: Int) {
        input = .init(totalTokenCount: inputTokens, cachedTokenCount: cachedTokens)
        output = .init(totalTokenCount: outputTokens, reasoningTokenCount: reasoningTokens)
        var metadata: [String: any ConvertibleToGeneratedContent] = [:]
        metadata[LanguageModelMetadataKey.cacheWriteTokenCount] = cacheWriteTokens
        self.metadata = metadata
    }
}
