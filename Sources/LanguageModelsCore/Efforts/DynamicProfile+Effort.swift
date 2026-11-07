public import FoundationModels

extension LanguageModelSession.DynamicProfile {
    /// Uses a model for requests from this profile, at a reasoning level the model supports.
    ///
    /// The effort's type comes from the model, so it takes only the levels the model accepts. The effort sets the
    /// profile's reasoning level: a request's `ContextOptions` replaces it for that request, and a `reasoningLevel(_:)`
    /// applied around this profile doesn't.
    ///
    /// - Parameters:
    ///   - model: The model to use.
    ///   - effort: The reasoning level, from the levels `model` accepts.
    /// - Returns: A profile that uses `model` at `effort`.
    public func model<Model: DetailedLanguageModel>(
        _ model: Model,
        effort: Model.Details.Effort
    ) -> some LanguageModelSession.DynamicProfile {
        self.model(model).reasoningLevel(effort.reasoningLevel)
    }
}
