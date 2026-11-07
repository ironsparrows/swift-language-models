import LanguageModelsCore

extension AnswerReport {
    /// Takes the facts that a lifecycle event's response reports.
    mutating func update(with response: ResponseEvent.Response) {
        responseID = response.id ?? responseID
        model = response.model ?? model
        serviceTier = response.serviceTier ?? serviceTier
        if let usage = response.usage {
            self.usage = AnswerUsage(usage)
        }
    }
}

extension AnswerUsage {
    /// The usage a response reported.
    init(_ usage: ResponseEvent.Usage) {
        self.init(
            inputTokens: usage.inputTokens ?? 0,
            cachedTokens: usage.inputTokensDetails?.cachedTokens ?? 0,
            cacheWriteTokens: usage.inputTokensDetails?.cacheWriteTokens,
            outputTokens: usage.outputTokens ?? 0,
            reasoningTokens: usage.outputTokensDetails?.reasoningTokens ?? 0
        )
    }
}
