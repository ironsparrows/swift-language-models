package import FoundationModels
package import LanguageModelsCore

extension GenerationOptions.ToolCallingMode {
    /// Whether the model may or must call the session's tools, as OpenAI's formats spell it in `tool_choice`, or `nil`
    /// for a kind the formats have no word for.
    package var toolChoice: JSONValue? {
        let choice: ToolChoice? =
            switch kind {
            case .allowed: .auto
            case .required: .required
            case .disallowed: ToolChoice.none
            @unknown default: nil
            }
        return choice?.json
    }
}

/// Whether the model may or must call the session's tools, as `tool_choice` spells it.
private struct ToolChoice: ProviderVocabulary {
    static let auto: Self = "auto"
    static let required: Self = "required"
    static let none: Self = "none"

    let rawValue: String
}
