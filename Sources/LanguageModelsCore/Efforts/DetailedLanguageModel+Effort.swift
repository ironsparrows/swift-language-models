public import FoundationModels

extension DetailedLanguageModel {
    /// The reasoning level for one of this model's own efforts, for a request's `ContextOptions`.
    ///
    /// The effort's type comes from the model, so it takes only the levels the model accepts:
    ///
    /// ```swift
    /// let response = try await session.respond(
    ///     to: "Plan a trip.",
    ///     contextOptions: ContextOptions(reasoningLevel: model.reasoningLevel(.high))
    /// )
    /// ```
    ///
    /// ``ModelDetails/reasoningEfforts`` lists the levels the model accepts. A model whose levels are known only at
    /// runtime takes any level, and its provider module sends the nearest one the model accepts.
    ///
    /// - Parameter effort: One of the levels the model accepts.
    /// - Returns: The reasoning level to put in a request's `ContextOptions`.
    public func reasoningLevel(_ effort: Details.Effort) -> ContextOptions.ReasoningLevel {
        effort.reasoningLevel
    }
}
