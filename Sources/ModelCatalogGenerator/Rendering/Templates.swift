// MARK: - Model efforts

/// Renders a namespace with an empty type for each of a source's models, such as `OpenRouterCatalog`, and each model's
/// effort levels as static members of `Efforts.Of` that type.
///
/// Each model has an effort type of its own, so the type stays the same when the model's levels change. A level the
/// model stopped accepting stays, marked deprecated.
enum ModelEffortsTemplate {
    /// The names that `Efforts.Of` already has, which no effort word's member can take.
    static let reservedNames: Set<String> = ["allCases", "rawValue", "reasoningLevel", "hashValue"]

    /// The names that a nested type can't take, since Swift reads them as its own keywords.
    private static let reservedTypeNames: Set<String> = ["Protocol", "Self", "Type"]

    /// Where the source's generated file goes.
    static func path(for source: CatalogSource) -> String {
        "\(source.generatedDirectory)/\(source.modelsNamespace)+Efforts.swift"
    }

    static func render(_ snapshot: CatalogSnapshot, ranking: EffortRanking) throws(GeneratorError) -> GeneratedFile {
        let source = snapshot.source
        let namespace = source.modelsNamespace
        let models = snapshot.namedModels
        try SwiftIdentifier.check(
            models.map { ($0.name.capitalized, $0.model.id) },
            reserved: reservedTypeNames,
            kind: "\(source.displayName) model types"
        )

        var lines = SourceText.header(from: [source])
        lines.insert("// swift-format-ignore-file: AlwaysUseLowerCamelCase", at: 0)
        lines += ["public import LanguageModels", ""]
        lines += SourceText.documentation(
            "A type for each model in \(source.displayName)'s catalog, whose effort type is "
                + "`Efforts.Of<\(namespace).ModelName>`.",
            indent: ""
        )
        lines += ["public enum \(namespace) {"]
        for (index, (model, name)) in models.enumerated() {
            if index > 0 { lines += [""] }
            lines += SourceText.documentation(model.displayName, indent: "    ")
            lines += ["    public enum \(name.capitalized): Efforts.List {"]
            lines += wordsLines("efforts", ranking.sorted(model.reasoningEfforts), "The levels the model accepts, highest first.")
            let removed = ranking.sorted(model.removedReasoningEfforts.map(\.word))
            if !removed.isEmpty { lines += wordsLines("removedEfforts", removed, "The levels the model accepted before.") }
            lines += ["    }"]
        }
        lines += ["}"]
        for (model, name) in models {
            lines += effortLines(of: model, named: name, source: source, ranking: ranking)
        }
        return GeneratedFile(path: path(for: source), contents: SourceText.file(lines))
    }

    /// A model type's list of effort words.
    private static func wordsLines(_ name: String, _ words: [String], _ documentation: String) -> [String] {
        SourceText.documentation(documentation, indent: "        ")
            + SwiftExpression.array(words.map { .atom(SwiftLiteral.string($0)) })
            .lines(indent: "        ", prefix: "public static var \(name): [String] { ", suffix: " }")
    }

    /// The static members of a model's effort type: one for each level it accepts, and a deprecated one for each level
    /// it stopped accepting, highest first.
    private static func effortLines(
        of model: CatalogModel,
        named name: SwiftIdentifier,
        source: CatalogSource,
        ranking: EffortRanking
    ) -> [String] {
        let removedOn = Dictionary(model.removedReasoningEfforts.map { ($0.word, $0.removedOn) }) { first, _ in first }
        let words = ranking.sorted(model.reasoningEfforts + removedOn.keys)
        guard !words.isEmpty else { return [] }
        var lines = ["", "extension Efforts.Of where Tag == \(source.modelType(named: name)) {"]
        for (index, word) in words.enumerated() {
            if index > 0 { lines += [""] }
            lines += SourceText.documentation(ReasoningLevelTemplate.summary(of: word), indent: "    ")
            if let day = removedOn[word] {
                let message = "\(source.displayName) stopped accepting this level for this model" + (day.map { " on \($0)" } ?? "")
                lines += ["    @available(*, deprecated, message: \(SwiftLiteral.string(message)))"]
            }
            let name = SwiftIdentifier.effortMember(for: word)
            lines += ["    public static var \(name): Self { Self(listed: \(SwiftLiteral.string(word))) }"]
        }
        lines += ["}"]
        return lines
    }
}

// MARK: - Model removals

/// Renders the models a source stopped listing, each with the day it left, as a static member of `ModelRemovals`,
/// which the source's details read for their removal date.
enum ModelRemovalsTemplate {
    /// Where the source's generated file goes.
    static func path(for source: CatalogSource) -> String {
        "\(source.generatedDirectory)/ModelRemovals+\(source.swiftName).swift"
    }

    static func render(_ snapshot: CatalogSnapshot) -> GeneratedFile {
        let source = snapshot.source
        let removed = snapshot.removed.sorted { $0.model.id < $1.model.id }
        let member = source.swiftName.prefix(1).lowercased() + source.swiftName.dropFirst()

        var lines = SourceText.header(from: [source])
        lines += [
            "import Foundation", "import LanguageModels", "", "extension ModelRemovals {",
            "    /// The models \(source.displayName) stopped listing, which its catalog keeps as deprecated members.",
        ]
        if removed.isEmpty {
            lines += ["    static let \(member) = ModelRemovals([:])"]
        } else {
            lines += ["    static let \(member) = ModelRemovals(["]
            lines += removed.map { "        \(SwiftLiteral.string($0.model.id)): \(SwiftLiteral.date($0.removedOn))," }
            lines += ["    ])"]
        }
        lines += ["}"]
        return GeneratedFile(path: path(for: source), contents: SourceText.file(lines))
    }
}

// MARK: - Reasoning levels

/// Renders the named reasoning levels and the effort ranking, as an extension of Apple's `ReasoningLevel`.
enum ReasoningLevelTemplate {
    static let path = "Sources/LanguageModelsCore/Generated/ReasoningLevel+Efforts.swift"

    /// The names that `ContextOptions.ReasoningLevel` already has, which no effort word's member can take.
    static let reservedNames: Set<String> = ["light", "moderate", "deep", "custom", "effortRanking"]

    /// Global functions that a static member with the same name hides inside the type's extensions.
    private static let globalFunctionNames: Set<String> = ["max", "min"]

    /// The doc summary of an effort word's member.
    fileprivate static func summary(of word: String) -> String {
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

// MARK: - Vocabularies

/// Renders a static member for each word of a vocabulary, as an extension of the vocabulary's type, sorted by word.
enum VocabularyTemplate {
    /// Where the vocabulary's generated file goes.
    static func path(of vocabulary: CatalogVocabulary, from source: CatalogSource) -> String {
        "\(source.generatedDirectory)/\(source.typeName(of: vocabulary))+Catalog.swift"
    }

    static func render(_ vocabulary: CatalogVocabulary, of snapshot: CatalogSnapshot) throws(GeneratorError) -> GeneratedFile {
        let source = snapshot.source
        let typeName = source.typeName(of: vocabulary)
        let words = (snapshot.vocabularies[vocabulary] ?? []).sorted { $0.word < $1.word }
            .map { (word: $0, name: SwiftIdentifier.member(for: $0.word)) }
        try SwiftIdentifier.check(
            words.map { ($0.name, $0.word.word) },
            reserved: SwiftIdentifier.optionalCaseNames,
            kind: "\(typeName) words"
        )

        var lines = SourceText.header(from: [source])
        lines += ["import LanguageModels", "", "extension \(typeName) {"]
        for (index, (word, name)) in words.enumerated() {
            if index > 0 { lines += [""] }
            lines += SourceText.documentation(word.summary ?? vocabulary.fallbackSummary(for: word.word), indent: "    ")
            if let removedOn = word.removedOn { lines += ["    \(source.removedAttribute(on: removedOn))"] }
            lines += ["    public static let \(name): Self = \(SwiftLiteral.string(word.word))"]
        }
        lines += ["}"]
        return GeneratedFile(path: path(of: vocabulary, from: source), contents: SourceText.file(lines))
    }
}
