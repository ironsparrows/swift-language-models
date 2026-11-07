public import FoundationModels

extension ContextOptions.ReasoningLevel {
    /// The effort word the level asks a provider for, such as `high`: `low`, `medium` and `high` for `light`,
    /// `moderate` and `deep`, and a custom level's own word, such as `xhigh` or `none`.
    ///
    /// A typed effort's word is its `rawValue`; this reads the word back from a level in its open form, such as one an
    /// app picked at run time, so the app can show it or store it. `nil` for a level this package doesn't know yet.
    public var effortWord: String? {
        switch self {
        case .light: "low"
        case .moderate: "medium"
        case .deep: "high"
        case .custom(let word): word
        @unknown default: nil
        }
    }
}
