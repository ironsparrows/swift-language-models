import LanguageModelsCore

extension AnswerReport {
    /// Takes the facts that a chunk reports.
    mutating func update(with chunk: ChatCompletionChunk) {
        responseID = chunk.id ?? responseID
        model = chunk.model ?? model
        serviceTier = chunk.serviceTier ?? serviceTier
        if let usage = chunk.usage {
            self.usage = AnswerUsage(usage)
        }
        finishReason = chunk.choices?.first?.finishReason ?? finishReason
    }
}

extension AnswerUsage {
    /// The usage a chunk reported.
    init(_ usage: ChatCompletionChunk.Usage) {
        self.init(
            inputTokens: usage.promptTokens ?? 0,
            cachedTokens: usage.promptTokensDetails?.cachedTokens ?? 0,
            cacheWriteTokens: usage.promptTokensDetails?.cacheWriteTokens,
            outputTokens: usage.completionTokens ?? 0,
            reasoningTokens: usage.completionTokensDetails?.reasoningTokens ?? 0
        )
    }
}
