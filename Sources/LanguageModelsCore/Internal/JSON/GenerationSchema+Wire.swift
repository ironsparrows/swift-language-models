package import FoundationModels

extension GenerationSchema {
    /// The schema's name as APIs that name a response schema take it: letters, digits, `_` and `-`, up to 64
    /// characters, with `response` for a name that keeps none.
    package var wireName: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let name = String(name.map { allowed.contains($0) ? $0 : "_" }.prefix(64))
        return name.isEmpty ? "response" : name
    }

    /// The text that asks for JSON matching the schema, for a prompt.
    ///
    /// - Throws: `LanguageModelError.unsupportedGenerationGuide` when a guide has a value JSON can't hold.
    package func promptInstructions() throws(LanguageModelError) -> String {
        "Respond with JSON that matches this JSON Schema:\n\(try JSONValue(self, strict: false).text)"
    }
}
