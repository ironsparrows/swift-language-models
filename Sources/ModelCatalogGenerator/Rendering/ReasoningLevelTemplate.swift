/// Renders the named reasoning levels and the effort ranking, as an extension of Apple's `ReasoningLevel`.
enum ReasoningLevelTemplate {
    static let path = "Sources/LanguageModelsCore/Generated/ReasoningLevel+Efforts.swift"

    /// The names that `ContextOptions.ReasoningLevel` already has, which no effort word's member can take.
    static let reservedNames: Set<String> = ["light", "moderate", "deep", "custom", "effortRanking"]

    /// Global functions that a static member with the same name hides inside the type's extensions.
    private static let globalFunctionNames: Set<String> = ["max", "min"]

    /// The doc summary of an effort word's member.
    static func summary(of word: String) -> String {
        word == EffortRanking.offWord ? "The `\(word)` effort, which turns reasoning off." : "The `\(word)` effort."
    }

    /// The file of named levels, with the removed words marked deprecated.
    ///
    /// - Parameters:
    ///   - ranking: Every effort word, highest first.
    ///   - removed: The words that no source uses any more, each with a source it left.
    ///   - sources: The sources of the catalogs.
    /// - Returns: The generated file.
    static func render(ranking: EffortRanking, removed: [String: CatalogSource], sources: [CatalogSource]) -> GeneratedFile {
        var lines = SourceText.header(from: sources)
        lines += ["public import FoundationModels", "", "extension ContextOptions.ReasoningLevel {"]
        for word in ranking.words {
            let name = SwiftIdentifier.effortMember(for: word)
            lines += SourceText.documentation(summary(of: word), indent: "    ")
            if Self.globalFunctionNames.contains(name.name) {
                lines += [
                    "    ///",
                    "    /// Inside an extension of `ContextOptions.ReasoningLevel`, this hides the global `\(name)(_:_:)`; call that one",
                    "    /// as `Swift.\(name)`.",
                ]
            }
            if let source = removed[word] { lines += ["    \(source.removedAttribute(on: nil))"] }
            lines += ["    public static var \(name): Self { .custom(\(SwiftLiteral.string(word))) }", ""]
        }
        lines += ["    /// Every effort word in the catalogs, highest first, including the words that providers no longer use."]
        lines += SwiftExpression.array(ranking.words.map { .atom(SwiftLiteral.string($0)) })
            .lines(indent: "    ", prefix: "package static let effortRanking = ")
        lines += ["}"]
        return GeneratedFile(path: path, contents: SourceText.file(lines))
    }
}
