package import LanguageModelsCore

/// The role of the input message the instructions go in, as a dialect's ``ResponsesDialect/instructionsRole`` picks
/// it.
package struct InstructionsRole: ProviderVocabulary {
    /// Instructions from the app's developer, which take priority over the person's messages.
    package static let developer: Self = "developer"

    /// System instructions, for models that don't take the `developer` role.
    package static let system: Self = "system"

    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }
}
