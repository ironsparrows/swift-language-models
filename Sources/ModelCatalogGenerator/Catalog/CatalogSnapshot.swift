import Foundation

// MARK: - Snapshot

/// A source's models as `Catalogs/<source>.json` stores them, sorted so the file's diff reads as a changelog.
struct CatalogSnapshot: Codable, Equatable, Sendable {
    let source: CatalogSource
    let models: [CatalogModel]
    let removed: [RemovedModel]
    /// Every word of each vocabulary, sorted, including the words the source no longer uses.
    let vocabularies: [CatalogVocabulary: [CatalogWord]]
    /// Every effort word, highest first, including the words the source no longer uses.
    let efforts: [CatalogWord]

    /// The largest share of the earlier snapshot's models that one fetch can lose. Losing more at once more likely
    /// means an outage than real removals. Models lost on or after their expiration date don't count, since the source
    /// said when they'd go.
    private static let maximumLossFraction = 0.2

    /// The snapshot after a fetch: new and changed models replace old ones, and missing models move to `removed`.
    ///
    /// Each of the source's vocabularies, and the efforts, hold the words the source lists and the words its models
    /// use. A word that's in neither any more stays, marked removed. A model keeps each effort it accepted before and
    /// no longer does, marked removed. The source's own order of efforts decides the order of its words; the models'
    /// lists place the others.
    ///
    /// - Parameters:
    ///   - source: The source the models came from.
    ///   - fetched: The models and words the source returned.
    ///   - previous: The snapshot in the package, if any.
    ///   - today: The day of the fetch, in UTC.
    /// - Returns: The updated snapshot.
    /// - Throws: ``GeneratorError/brokenSource(_:)`` when the source returned no models, listed a model twice or a
    ///   model that doesn't output text, left out a listed model whose entry doesn't decode, or lost more than
    ///   ``maximumLossFraction`` of its models at once, other than models past their expiration date.
    ///   ``GeneratorError/invalidCatalog(_:)`` when the efforts can't be put in one order.
    static func updated(
        source: CatalogSource,
        fetched: FetchedCatalog,
        previous: CatalogSnapshot?,
        today: CatalogDay
    ) throws(GeneratorError) -> CatalogSnapshot {
        try validate(fetched, from: source, previous: previous, today: today)
        let listed = withRemovedEfforts(fetched.models, previous: previous, today: today)
        let removed = removedModels(fetched: fetched, previous: previous, today: today)
        let ranking = try EffortRanking(
            bases: [fetched.efforts],
            lists: (listed + removed.map(\.model)).map(\.reasoningEfforts) + [(previous?.efforts ?? []).map(\.word)]
        )
        return CatalogSnapshot(
            source: source,
            models: listed.sorted { $0.id < $1.id },
            removed: removed,
            vocabularies: vocabularies(of: source, fetched: fetched, previous: previous, today: today),
            efforts: efforts(of: source, fetched: fetched, ranking: ranking, previous: previous, today: today)
        )
    }

    /// Checks that a fetch looks whole: it has models, lists each once, each outputs text, no model of the earlier
    /// snapshot is missing because its entry doesn't decode, and it lost no more than ``maximumLossFraction`` of the
    /// earlier snapshot's models, other than models whose expiration date came, which the source said it would stop
    /// listing.
    ///
    /// - Throws: ``GeneratorError/brokenSource(_:)`` naming the first problem found.
    private static func validate(
        _ fetched: FetchedCatalog,
        from source: CatalogSource,
        previous: CatalogSnapshot?,
        today: CatalogDay
    ) throws(GeneratorError) {
        guard !fetched.models.isEmpty else { throw .brokenSource("\(source.displayName) returned no models.") }
        let repeated = Dictionary(grouping: fetched.models, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
        guard repeated.isEmpty else {
            throw .brokenSource("\(source.displayName) listed these models more than once: \(repeated.joined(separator: ", ")).")
        }
        let textless = fetched.models.filter { !$0.outputModalities.contains(CatalogModel.textModality) }.map(\.id).sorted()
        guard textless.isEmpty else {
            throw .brokenSource("\(source.displayName) listed models that don't output text: \(textless.joined(separator: ", ")).")
        }
        // Leaving out a listed model whose entry doesn't decode would deprecate a model the source still serves.
        let undescribed = lostModels(fetched, previous: previous).map(\.id).filter(fetched.undescribedModelIDs.contains).sorted()
        guard undescribed.isEmpty else {
            throw .brokenSource(
                "\(source.displayName)'s entries for these listed models don't decode: \(undescribed.joined(separator: ", ")).")
        }
        let lostCount = lostModels(fetched, previous: previous).filter { model in
            model.expirationDate.map { $0.start > today.start } ?? true
        }.count
        let previousCount = previous?.models.count ?? 0
        guard Double(lostCount) <= Double(previousCount) * maximumLossFraction else {
            throw .brokenSource("\(source.displayName) lost \(lostCount) of \(previousCount) models at once; nothing was written.")
        }
    }

    /// The earlier snapshot's models that the fetch no longer lists.
    private static func lostModels(_ fetched: FetchedCatalog, previous: CatalogSnapshot?) -> [CatalogModel] {
        let fetchedIDs = fetched.modelIDs
        return (previous?.models ?? []).filter { !fetchedIDs.contains($0.id) }
    }

    /// The models gone from the source, sorted by id: the earlier snapshot's removed models that didn't come back, and
    /// the models the fetch lost, removed today.
    private static func removedModels(fetched: FetchedCatalog, previous: CatalogSnapshot?, today: CatalogDay) -> [RemovedModel] {
        let fetchedIDs = fetched.modelIDs
        let stillRemoved = (previous?.removed ?? []).filter { !fetchedIDs.contains($0.model.id) }
        let newlyRemoved = lostModels(fetched, previous: previous).map { RemovedModel(model: $0, removedOn: today) }
        return (stillRemoved + newlyRemoved).sorted { $0.model.id < $1.model.id }
    }

    /// The words of each of the source's vocabularies, sorted.
    private static func vocabularies(
        of source: CatalogSource,
        fetched: FetchedCatalog,
        previous: CatalogSnapshot?,
        today: CatalogDay
    ) -> [CatalogVocabulary: [CatalogWord]] {
        Dictionary(
            uniqueKeysWithValues: source.vocabularies.map { vocabulary in
                let vocabularyWords = words(
                    listed: fetched.vocabularies[vocabulary] ?? [],
                    used: fetched.models.flatMap(vocabulary.words(of:)),
                    previous: previous?.vocabularies[vocabulary] ?? [],
                    named: source.wordsNamedByModule(in: vocabulary),
                    today: today
                )
                return (vocabulary, vocabularyWords.sorted { $0.word < $1.word })
            }
        )
    }

    /// The effort words, in the ranking's order.
    private static func efforts(
        of source: CatalogSource,
        fetched: FetchedCatalog,
        ranking: EffortRanking,
        previous: CatalogSnapshot?,
        today: CatalogDay
    ) -> [CatalogWord] {
        let efforts = words(
            listed: fetched.efforts.map { CatalogWord($0) },
            used: fetched.models.flatMap(\.reasoningEfforts),
            previous: previous?.efforts ?? [],
            named: source.effortsNamedByModule,
            today: today
        )
        let effortsByWord = Dictionary(efforts.map { ($0.word, $0) }) { first, _ in first }
        return ranking.words.compactMap { effortsByWord[$0] }
    }

    /// The fetched models, each with the efforts it accepted in the earlier snapshot, listed or removed, and no longer
    /// does, marked removed. An effort the model accepts again stops being removed.
    private static func withRemovedEfforts(
        _ models: [CatalogModel],
        previous: CatalogSnapshot?,
        today: CatalogDay
    ) -> [CatalogModel] {
        let previousModels = Dictionary(
            ((previous?.models ?? []) + (previous?.removed ?? []).map(\.model)).map { ($0.id, $0) }
        ) { first, _ in first }
        return models.map { model in
            guard let earlier = previousModels[model.id] else { return model }
            let current = Set(model.reasoningEfforts)
            let stillRemoved = earlier.removedReasoningEfforts.filter { !current.contains($0.word) }
            let removedWords = Set(stillRemoved.map(\.word))
            let newlyRemoved = earlier.reasoningEfforts.filter { !current.contains($0) && !removedWords.contains($0) }
                .map { CatalogWord($0, removedOn: today) }
            var model = model
            model.removedReasoningEfforts = (stillRemoved + newlyRemoved).sorted { $0.word < $1.word }
            return model
        }
    }

    /// The words a source lists, then the other words its models use, then the words of an earlier snapshot that are
    /// in neither any more: kept as they were when the module's code names them, and otherwise marked removed.
    private static func words(
        listed: [CatalogWord],
        used: [String],
        previous: [CatalogWord],
        named: Set<String>,
        today: CatalogDay
    ) -> [CatalogWord] {
        let listedWords = Set(listed.map(\.word))
        let unlisted = Set(used).subtracting(listedWords).sorted().map { CatalogWord($0) }
        let current = listedWords.union(used)
        let gone = previous.filter { !current.contains($0.word) }.map { word in
            named.contains(word.word) ? CatalogWord(word.word, summary: word.summary) : word.removed(on: today)
        }
        return listed + unlisted + gone
    }
}

extension CatalogSnapshot {
    private enum CodingKeys: String, CodingKey {
        case source, models, removed, vocabularies, efforts
    }

    /// Decodes a snapshot, refusing one that has an id more than once across its listed and removed models, since
    /// each id names one model.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(CatalogSource.self, forKey: .source)
        models = try container.decode([CatalogModel].self, forKey: .models)
        removed = try container.decode([RemovedModel].self, forKey: .removed)
        vocabularies = try container.decode([CatalogVocabulary: [CatalogWord]].self, forKey: .vocabularies)
        efforts = try container.decode([CatalogWord].self, forKey: .efforts)
        let ids = models.map(\.id) + removed.map(\.model.id)
        let repeated = Dictionary(grouping: ids) { $0 }.filter { $0.value.count > 1 }.keys.sorted()
        guard repeated.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .models,
                in: container,
                debugDescription: "These model ids appear more than once: \(repeated.joined(separator: ", "))."
            )
        }
    }
}

// MARK: - Fetched catalog

/// What a source's documents say, in catalog form, before it joins the snapshot in the package.
struct FetchedCatalog: Sendable {
    let models: [CatalogModel]
    /// The words that the source's API description lists for each vocabulary, with their summaries.
    let vocabularies: [CatalogVocabulary: [CatalogWord]]
    /// Every effort word that the source's API description lists, highest first.
    let efforts: [String]
    /// The ids of the model list's entries that don't decode, which the fetch skipped, sorted.
    var skippedEntryIDs: [String] = []
    /// The ids of the models the source serves that the fetch left out because their entries don't decode, so it
    /// can't tell whether the catalog lists them.
    var undescribedModelIDs: Set<String> = []

    /// The ids of the models.
    var modelIDs: Set<String> {
        Set(models.map(\.id))
    }
}

// MARK: - Vocabularies

/// An open vocabulary of a source's API whose words each get a static member, such as the request parameter names or
/// the web search engines.
///
/// Each source lists the vocabularies its API has in ``CatalogSource/vocabularies``.
enum CatalogVocabulary: String, Codable, CodingKeyRepresentable, Sendable {
    case inputModalities
    case outputModalities
    case parameters
    case searchContextSizes
    case webFetchEngines
    case webSearchEngines
    case webSearchModes

    /// The vocabulary's words that a model uses, which are none for a vocabulary of request settings.
    func words(of model: CatalogModel) -> [String] {
        switch self {
        case .inputModalities: model.inputModalities
        case .outputModalities: model.outputModalities
        case .parameters: model.supportedParameters
        case .searchContextSizes, .webFetchEngines, .webSearchEngines, .webSearchModes: []
        }
    }
}

// MARK: - Days

/// A day in UTC, such as a model's knowledge cutoff or the day a word was removed, which catalogs write as
/// `yyyy-MM-dd`.
struct CatalogDay: Hashable, Sendable, CustomStringConvertible {
    private static let format = Date.ISO8601FormatStyle().year().month().day()

    /// The day as `yyyy-MM-dd`.
    let description: String

    /// Midnight UTC at the start of the day.
    let start: Date

    /// The day a text names, or `nil` unless the text is a real day written as `yyyy-MM-dd`.
    ///
    /// The ISO 8601 parser alone also takes text such as `2026-02-30`, which it rolls over into March, or `2026-2-3`,
    /// and ignores whatever follows the day, so the text must also be how the parsed day is written.
    init?(_ text: String) {
        guard let start = try? Self.format.parse(text), start.formatted(Self.format) == text else { return nil }
        self.description = text
        self.start = start
    }

    /// The day in UTC that a moment falls on.
    init(containing date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        start = calendar.startOfDay(for: date)
        description = start.formatted(Self.format)
    }
}

extension CatalogDay: Codable {
    /// Decodes a day from its text.
    ///
    /// - Throws: `DecodingError.dataCorrupted` when the text isn't a real day written as `yyyy-MM-dd`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = CatalogDay(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(text)' isn't a day written as yyyy-MM-dd.")
        }
        self = day
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
