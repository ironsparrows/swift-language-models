// MARK: - Renderer

/// Turns catalog snapshots into the package's generated Swift sources.
enum CatalogRenderer {
    /// The generated files for the given snapshots.
    ///
    /// An effort word that every snapshot marks removed keeps its member, marked deprecated.
    ///
    /// - Parameter snapshots: Every snapshot in the package.
    /// - Returns: The files, in a fixed order.
    /// - Throws: ``GeneratorError/invalidCatalog(_:)`` when the snapshots can't become code.
    static func files(for snapshots: [CatalogSnapshot]) throws(GeneratorError) -> [GeneratedFile] {
        let sources = snapshots.map(\.source)
        let models = snapshots.flatMap { $0.models + $0.removed.map(\.model) }
        let ranking = try EffortRanking(
            bases: snapshots.map { $0.efforts.map(\.word) },
            lists: models.map(\.reasoningEfforts)
        )
        try SwiftIdentifier.check(
            ranking.words.map { (SwiftIdentifier.effortMember(for: $0), $0) },
            reserved: ReasoningLevelTemplate.reservedNames.union(ModelEffortsTemplate.reservedNames),
            kind: "effort words"
        )
        let removedWords = removals(in: snapshots) { snapshot in snapshot.efforts.map { ($0.word, $0.removedOn != nil) } }

        var files = [ReasoningLevelTemplate.render(ranking: ranking, removed: removedWords, sources: sources)]
        for snapshot in snapshots {
            files += try snapshot.source.vocabularies.map { (vocabulary) throws(GeneratorError) in
                try VocabularyTemplate.render(vocabulary, of: snapshot)
            }
            files.append(try ModelsTemplate.render(snapshot, ranking: ranking))
            files.append(try ModelEffortsTemplate.render(snapshot, ranking: ranking))
            files.append(ModelRemovalsTemplate.render(snapshot))
        }
        return files
    }

    /// The values that every snapshot tracking them marks removed, each with the first source that removed it.
    private static func removals<Value: Hashable>(
        in snapshots: [CatalogSnapshot],
        _ tracked: (CatalogSnapshot) -> [(value: Value, isRemoved: Bool)]
    ) -> [Value: CatalogSource] {
        var removals: [Value: CatalogSource] = [:]
        var current: Set<Value> = []
        for snapshot in snapshots {
            for (value, isRemoved) in tracked(snapshot) {
                if !isRemoved {
                    current.insert(value)
                } else if removals[value] == nil {
                    removals[value] = snapshot.source
                }
            }
        }
        return removals.filter { !current.contains($0.key) }
    }
}

// MARK: - Generated files

/// A file the generator writes, such as a Swift source or a catalog, at a path relative to the package root.
struct GeneratedFile: Equatable, Sendable {
    let path: String
    let contents: String
}

// MARK: - Snapshots

extension CatalogSnapshot {
    /// Each model, listed or removed, with its member name, sorted by id. The model's type name is the same name,
    /// capitalized.
    ///
    /// Models whose ids give the same name take turns by release, earliest first, then by id, whether they're listed
    /// or removed. The first keeps the name, and each next one gets the lowest numbered suffix from `_2` that no model
    /// before it took, such as `xM1_5_2`. The names depend only on the snapshot, and removing a model doesn't change
    /// its release, so a removal renames nothing, and neither does a new model, which the source lists last.
    var namedModels: [(model: CatalogModel, name: SwiftIdentifier)] {
        let inTurn = (models + removed.map(\.model)).sorted { lhs, rhs in
            lhs.releasedAt != rhs.releasedAt ? lhs.releasedAt < rhs.releasedAt : lhs.id < rhs.id
        }
        var taken: Set<SwiftIdentifier> = []
        let named = inTurn.map { model in
            let base = SwiftIdentifier.member(for: model.id)
            var name = base
            // An empty name stays empty, so the check reports it.
            var number = 2
            while !base.name.isEmpty, taken.contains(name) {
                name = base.appending("_\(number)")
                number += 1
            }
            taken.insert(name)
            return (model: model, name: name)
        }
        return named.sorted { $0.model.id < $1.model.id }
    }
}

// MARK: - Sources

extension CatalogSource {
    /// The availability attribute of a generated member whose model or word the provider stopped listing: deprecated
    /// rather than unavailable, so code that names it still compiles, with a warning.
    ///
    /// - Parameter day: The day the provider stopped listing the model or word, or `nil` for an effort word, which
    ///   every provider shares.
    /// - Returns: The attribute.
    func removedAttribute(on day: CatalogDay?) -> String {
        let message = day.map { "Removed from \(displayName) on \($0)" } ?? "Removed from \(displayName)"
        return "@available(*, deprecated, message: \(SwiftLiteral.string(message)))"
    }

    /// The provider's name in Swift, which names its generated files and members, such as `ModelRemovals.openRouter`.
    var swiftName: String {
        switch self {
        case .openrouter: "OpenRouter"
        case .openai: "OpenAI"
        }
    }

    /// The provider's name in Swift as the start of a member's name, such as `openRouter`.
    var memberPrefix: String {
        swiftName.prefix(1).lowercased() + swiftName.dropFirst()
    }

    /// The provider module's type of a model's details, such as `OpenRouterModel`.
    var modelTypeName: String {
        "\(swiftName)Model"
    }

    /// The arguments of the provider module's model initializer that not every provider's takes, such as OpenRouter's
    /// `aliasTarget`. A model whose data needs one that its provider's initializer doesn't take can't become code.
    var optionalModelArguments: Set<String> {
        switch self {
        case .openrouter: ["aliasTarget", "cachesOnlyMarkedPrompts", "outputModalities"]
        case .openai: []
        }
    }

    /// The provider module's type of a model id, such as `OpenRouterModelID`.
    var modelIDTypeName: String {
        "\(swiftName)ModelID"
    }

    /// A model id the generated documentation shows, such as `typesafe/jev-router`.
    var exampleModelID: String {
        switch self {
        case .openrouter: "typesafe/jev-router"
        case .openai: "gpt-6-luna"
        }
    }

    /// The generated namespace that holds a type for each of the provider's models, which names the model's efforts,
    /// such as `OpenRouterCatalog`.
    var modelsNamespace: String {
        "\(swiftName)Catalog"
    }

    /// The generated type of the provider's model with the given member name, such as
    /// `OpenRouterCatalog.AnthropicClaudeHaiku5_5` for `anthropicClaudeHaiku5_5`.
    func modelType(named member: SwiftIdentifier) -> String {
        "\(modelsNamespace).\(member.capitalized)"
    }

    /// The effort type of the provider's model with the given member name, such as
    /// `Efforts.Of<OpenRouterCatalog.AnthropicClaudeHaiku5_5>` for `anthropicClaudeHaiku5_5`.
    func effortType(named member: SwiftIdentifier) -> String {
        "Efforts.Of<\(modelType(named: member))>"
    }

    /// The folder of the provider's generated sources, relative to the package root.
    var generatedDirectory: String {
        "Sources/\(swiftName)LanguageModels/Generated"
    }

    /// The generated type that gives each word of a vocabulary a static member, such as `OpenRouterParameter`.
    func typeName(of vocabulary: CatalogVocabulary) -> String {
        let word =
            switch vocabulary {
            case .inputModalities: "InputModality"
            case .outputModalities: "OutputModality"
            case .parameters: "Parameter"
            case .searchContextSizes: "SearchContextSize"
            case .webFetchEngines: "WebFetchEngine"
            case .webSearchEngines: "WebSearchEngine"
            case .webSearchModes: "WebSearchMode"
            }
        return "\(swiftName)\(word)"
    }
}

// MARK: - Reasoning

extension CatalogReasoning {
    /// The matching `ModelReasoning` member in generated code.
    var swiftLiteral: String {
        switch self {
        case .unsupported: ".unsupported"
        case .optional(enabledByDefault: false): ".offByDefault"
        case .optional(enabledByDefault: true): ".onByDefault"
        case .mandatory: ".mandatory"
        }
    }
}

// MARK: - Vocabularies

extension CatalogVocabulary {
    /// The doc summary of a word that the source doesn't describe.
    func fallbackSummary(for word: String) -> String {
        switch self {
        case .inputModalities: "The `\(word)` input kind."
        case .outputModalities: "The `\(word)` output kind."
        case .parameters: "The `\(word)` parameter."
        case .searchContextSizes: "The `\(word)` search context size."
        case .webFetchEngines: "The `\(word)` web fetch engine."
        case .webSearchEngines: "The `\(word)` web search engine."
        case .webSearchModes: "The `\(word)` search mode."
        }
    }
}
