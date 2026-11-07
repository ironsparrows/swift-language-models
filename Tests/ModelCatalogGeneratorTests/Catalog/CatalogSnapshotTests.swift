import Foundation
import Testing

@testable import ModelCatalogGenerator

@Suite("Catalog snapshot")
struct CatalogSnapshotTests {
    private static let previous = catalogSnapshot(
        catalogModel("vendor/a"),
        catalogModel("vendor/b"),
        catalogModel("vendor/c"),
        catalogModel("vendor/d"),
        catalogModel("vendor/e"),
        removed: [RemovedModel(model: catalogModel("vendor/old"), removedOn: "2026-10-01")],
        vocabularies: [.parameters: [CatalogWord("best_of"), CatalogWord("legacy", removedOn: "2026-10-01")]]
    )

    @Test func `a missing model moves to removed with the fetch date`() throws {
        let snapshot = try update(with: Self.models("a", "b", "c", "d"))

        #expect(snapshot.models.map(\.id) == ["vendor/a", "vendor/b", "vendor/c", "vendor/d"])
        #expect(snapshot.removed.map(\.model.id) == ["vendor/e", "vendor/old"])
        #expect(snapshot.removed.first?.removedOn == "2026-10-29")
    }

    @Test func `clearing drops the removed models, and the effort levels and words marked removed`() throws {
        let snapshot = catalogSnapshot(
            catalogModel("vendor/a", efforts: ["high"], removedEfforts: [CatalogWord("low", removedOn: "2026-10-31")]),
            removed: [RemovedModel(model: catalogModel("vendor/old"), removedOn: "2026-10-01")],
            vocabularies: [.parameters: [CatalogWord("best_of"), CatalogWord("legacy", removedOn: "2026-10-01")]],
            efforts: [CatalogWord("high"), CatalogWord("max", removedOn: "2026-10-31")]
        )

        let cleared = try snapshot.clearingRemoved()

        #expect(
            cleared
                == catalogSnapshot(
                    catalogModel("vendor/a", efforts: ["high"]), vocabularies: [.parameters: [CatalogWord("best_of")]],
                    efforts: [CatalogWord("high")]))
    }

    @Test func `clearing fails when a listed model would take the name of a removed one`() {
        let older = RemovedModel(model: catalogModel("x/m-1-5", releasedAt: 100), removedOn: "2026-10-01")
        let snapshot = catalogSnapshot(catalogModel("x/m-1.5", releasedAt: 200), removed: [older])

        #expect(throws: GeneratorError.invalidCatalog("Clearing what's removed would rename these models: x/m-1.5.")) {
            try snapshot.clearingRemoved()
        }
    }

    @Test func `a model that comes back leaves removed`() throws {
        #expect(try update(with: Self.models("a", "b", "c", "d", "e", "old")).removed.isEmpty)
    }

    @Test func `a source with no models fails`() {
        #expect(throws: GeneratorError.brokenSource("OpenRouter returned no models.")) {
            try update(with: [])
        }
    }

    @Test func `losing more than a fifth of the models at once fails`() {
        #expect(throws: GeneratorError.brokenSource("OpenRouter lost 2 of 5 models at once; nothing was written.")) {
            try update(with: Self.models("a", "b", "c"))
        }
    }

    @Test func `models lost on or after their expiration date don't count toward the loss, and are kept as removed`() throws {
        let previous = catalogSnapshot(
            catalogModel("vendor/a"), catalogModel("vendor/b", expirationDate: "2026-10-23"),
            catalogModel("vendor/c", expirationDate: "2026-10-29"), catalogModel("vendor/d"), catalogModel("vendor/e"))

        let updated = try CatalogSnapshot.updated(
            source: .openrouter,
            fetched: FetchedCatalog(
                models: [catalogModel("vendor/a"), catalogModel("vendor/d"), catalogModel("vendor/e")], vocabularies: [:], efforts: []),
            previous: previous,
            today: "2026-10-29"
        )

        #expect(updated.removed.map(\.model.id) == ["vendor/b", "vendor/c"])
        #expect(updated.removed.map(\.removedOn) == ["2026-10-29", "2026-10-29"])
    }

    @Test(arguments: [5, 10, 15, 35])
    func `losing exactly a fifth of the models at once passes, and one more fails`(previousCount: Int) throws {
        let previous = CatalogSnapshot(
            source: .openrouter,
            models: (0..<previousCount).map { catalogModel("vendor/\($0)") },
            removed: [],
            vocabularies: [:],
            efforts: []
        )
        let allowedLoss = previousCount / 5
        func update(keeping count: Int) throws(GeneratorError) -> CatalogSnapshot {
            try CatalogSnapshot.updated(
                source: .openrouter,
                fetched: FetchedCatalog(models: Array(previous.models.prefix(count)), vocabularies: [:], efforts: []),
                previous: previous,
                today: "2026-10-29"
            )
        }

        #expect(try update(keeping: previousCount - allowedLoss).removed.count == allowedLoss)
        let message = "OpenRouter lost \(allowedLoss + 1) of \(previousCount) models at once; nothing was written."
        #expect(throws: GeneratorError.brokenSource(message)) {
            try update(keeping: previousCount - allowedLoss - 1)
        }
    }

    @Test func `a later fetch keeps the day each model, word and effort was first removed`() throws {
        let previous = catalogSnapshot(
            catalogModel("vendor/a", efforts: ["high", "low"], parameters: ["best_of", "reasoning"]),
            catalogModel("vendor/b"), catalogModel("vendor/c"), catalogModel("vendor/d"), catalogModel("vendor/e"),
            vocabularies: [.parameters: [CatalogWord("best_of"), CatalogWord("reasoning"), CatalogWord("tools")]],
            efforts: [CatalogWord("max"), CatalogWord("high"), CatalogWord("low")]
        )
        let fetched = FetchedCatalog(
            models: [catalogModel("vendor/a", efforts: ["high"], parameters: ["reasoning"])] + Self.models("b", "c", "d"),
            vocabularies: [:],
            efforts: ["high", "low"]
        )

        let first = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: previous, today: "2026-10-29")
        let second = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: first, today: "2026-10-30")

        #expect(second == first)
        #expect(second.removed == [RemovedModel(model: catalogModel("vendor/e"), removedOn: "2026-10-29")])
        #expect(second.vocabularies[.parameters]?.first { $0.word == "best_of" }?.removedOn == "2026-10-29")
        #expect(second.efforts.first { $0.word == "max" }?.removedOn == "2026-10-29")
        #expect(second.models.first?.removedReasoningEfforts == [CatalogWord("low", removedOn: "2026-10-29")])
    }

    @Test(arguments: [
        catalogSnapshot(catalogModel("vendor/a"), catalogModel("vendor/a")),
        catalogSnapshot(catalogModel("vendor/a"), removed: [RemovedModel(model: catalogModel("vendor/a"), removedOn: "2026-10-01")]),
    ])
    func `a stored snapshot that has a model id twice doesn't decode`(snapshot: CatalogSnapshot) throws {
        let stored = Data(try CatalogJSON.encoded(snapshot).utf8)

        let error = #expect(throws: GeneratorError.self) {
            try CatalogJSON.decode(CatalogSnapshot.self, from: stored, path: "Catalogs/openrouter.json")
        }

        guard case .invalidCatalog(let message) = error else {
            Issue.record("Expected an invalid catalog, got \(String(describing: error)).")
            return
        }
        #expect(message.hasPrefix("Catalogs/openrouter.json doesn't decode:"))
        #expect(message.contains("These model ids appear more than once: vendor/a."))
    }

    @Test(arguments: [CatalogWord("none"), CatalogWord("none", removedOn: "2026-10-01")])
    func `an effort the module's code names stays current when the source stops listing it`(stored: CatalogWord) throws {
        let previous = catalogSnapshot(catalogModel("vendor/a"), efforts: [CatalogWord("high"), stored])
        let fetched = FetchedCatalog(models: [catalogModel("vendor/a")], vocabularies: [:], efforts: ["high"])

        let snapshot = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: previous, today: "2026-10-29")

        #expect(snapshot.efforts == [CatalogWord("high"), CatalogWord("none")])
    }

    @Test func `a model listed twice fails`() {
        #expect(throws: GeneratorError.brokenSource("OpenRouter listed these models more than once: vendor/a.")) {
            try update(with: Self.models("a", "a", "b", "c", "d", "e"))
        }
    }

    @Test func `a model that doesn't output text fails`() {
        let models = Self.models("a", "b", "c", "d") + [catalogModel("vendor/e", outputModalities: ["image"])]

        #expect(throws: GeneratorError.brokenSource("OpenRouter listed models that don't output text: vendor/e.")) {
            try update(with: models)
        }
    }

    @Test func `a vocabulary holds the listed words, the words models use and the words that are gone`() throws {
        let fetched = FetchedCatalog(
            models: Self.models("a", "b", "c", "d", "e"),
            vocabularies: [.parameters: [CatalogWord("top_p", summary: "Nucleus sampling.")]],
            efforts: []
        )

        let words = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: Self.previous, today: "2026-10-29")
            .vocabularies[.parameters]

        #expect(
            words == [
                CatalogWord("best_of", removedOn: "2026-10-29"),
                CatalogWord("legacy", removedOn: "2026-10-01"),
                CatalogWord("tools"),
                CatalogWord("top_p", summary: "Nucleus sampling."),
            ]
        )
    }

    @Test func `a word the module's code names stays current when the source stops listing it`() throws {
        let previous = catalogSnapshot(
            catalogModel("vendor/a"), vocabularies: [.parameters: [CatalogWord("temperature", summary: "Sampling temperature.")]])
        let fetched = FetchedCatalog(models: [catalogModel("vendor/a", parameters: [])], vocabularies: [:], efforts: [])

        let words = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: previous, today: "2026-10-29")
            .vocabularies[.parameters]

        #expect(words == [CatalogWord("temperature", summary: "Sampling temperature.")])
    }

    @Test func `a snapshot without the request vocabularies still decodes, and a fetch adds their words`() throws {
        let stored = try CatalogJSON.encoded(catalogSnapshot(catalogModel("vendor/a"), vocabularies: [.parameters: [CatalogWord("tools")]]))
        let previous = try JSONDecoder().decode(CatalogSnapshot.self, from: Data(stored.utf8))
        let fetched = FetchedCatalog(
            models: [catalogModel("vendor/a")], vocabularies: [.webSearchEngines: [CatalogWord("exa"), CatalogWord("auto")]], efforts: [])

        let snapshot = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: previous, today: "2026-10-29")

        #expect(previous.vocabularies[.webSearchEngines] == nil)
        #expect(snapshot.vocabularies[.webSearchEngines] == [CatalogWord("auto"), CatalogWord("exa")])
        #expect(snapshot.vocabularies[.parameters] == [CatalogWord("tools")])
    }

    @Test func `a model stored with prices and without the cache flag decodes, without them and the flag unset`() throws {
        let stored = #"""
            {"id": "vendor/a", "displayName": "A", "releasedAt": 0, "inputModalities": ["text"], "outputModalities": ["text"],
             "supportedParameters": ["tools"], "reasoningEfforts": [], "reasoning": "unsupported",
             "pricing": {"prompt": "0.000003", "completion": "0.000015", "cacheWrite": "0.00000375"}}
            """#

        let model = try JSONDecoder().decode(CatalogModel.self, from: Data(stored.utf8))

        #expect(model.cachesOnlyMarkedPrompts == false)
        #expect(try CatalogJSON.encoded(model).contains("pricing") == false)
    }

    @Test(arguments: [
        (Self.flags(mandatory: true, byDefault: true) as String?, "reasoning", CatalogReasoning.mandatory),
        (Self.flags(mandatory: false, byDefault: true), "reasoning", .optional(enabledByDefault: true)),
        (Self.flags(mandatory: false, byDefault: false), "reasoning", .optional(enabledByDefault: false)),
        (Self.flags(mandatory: false, byDefault: false), "tools", .unsupported),
        (nil, "reasoning", .optional(enabledByDefault: false)),
    ])
    func `a model stored before reasoning was one value decodes it from the flags and parameters`(
        flags: String?,
        parameter: String,
        reasoning: CatalogReasoning
    ) throws {
        let stored = Self.storedModel(flags: flags, parameter: parameter)

        #expect(try JSONDecoder().decode(CatalogModel.self, from: Data(stored.utf8)).reasoning == reasoning)
    }

    @Test func `a snapshot stored before reasoning was one value still decodes`() throws {
        let mandatory = Self.storedModel(flags: Self.flags(mandatory: true, byDefault: true), parameter: "reasoning")
        let gone = Self.storedModel(id: "vendor/b", flags: Self.flags(mandatory: false, byDefault: true), parameter: "reasoning")
        let json = #"""
            {"source": "openrouter", "models": [\#(mandatory)], "removed": [{"model": \#(gone), "removedOn": "2026-10-01"}],
             "vocabularies": {"parameters": [{"word": "reasoning"}]}, "efforts": [], "effortSets": []}
            """#

        let snapshot = try JSONDecoder().decode(CatalogSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.models.map(\.reasoning) == [.mandatory])
        #expect(snapshot.removed.map(\.model.reasoning) == [.optional(enabledByDefault: true)])
    }

    @Test(arguments: CatalogReasoning.allCases)
    func `a model's reasoning is stored as one word and reads back`(reasoning: CatalogReasoning) throws {
        let stored = try CatalogJSON.encoded(catalogModel("vendor/a", parameters: ["reasoning"], reasoning: reasoning))

        #expect(try JSONDecoder().decode(CatalogModel.self, from: Data(stored.utf8)).reasoning == reasoning)
        #expect(!stored.contains("isReasoningMandatory") && !stored.contains("reasonsByDefault"))
    }

    @Test func `a word that comes back is no longer removed`() throws {
        let fetched = FetchedCatalog(
            models: Self.models("a", "b", "c", "d", "e"), vocabularies: [.parameters: [CatalogWord("legacy")]], efforts: [])

        let words = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: Self.previous, today: "2026-10-29")
            .vocabularies[.parameters]

        #expect(words?.first { $0.word == "legacy" } == CatalogWord("legacy"))
    }

    @Test func `the efforts follow the source's order, keep the words models use and keep the words that are gone`() throws {
        let previous = catalogSnapshot(
            catalogModel("vendor/a"),
            efforts: [CatalogWord("high"), CatalogWord("minimal"), CatalogWord("none")]
        )
        let fetched = FetchedCatalog(
            models: [catalogModel("vendor/a", efforts: ["turbo", "high", "low"], parameters: ["reasoning"])],
            vocabularies: [:],
            efforts: ["high", "low", "none"]
        )

        let snapshot = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: previous, today: "2026-10-29")

        #expect(
            snapshot.efforts == [
                CatalogWord("turbo"),
                CatalogWord("high"),
                CatalogWord("low"),
                CatalogWord("minimal", removedOn: "2026-10-29"),
                CatalogWord("none"),
            ]
        )
    }

    @Test func `an effort a model stops accepting stays with it, marked removed, until the model accepts it again`() throws {
        let previous = catalogSnapshot(
            catalogModel(
                "vendor/a", efforts: ["high", "medium", "low"], parameters: ["reasoning"],
                removedEfforts: [CatalogWord("max", removedOn: "2026-10-01"), CatalogWord("minimal", removedOn: "2026-10-01")]
            ),
            efforts: [CatalogWord("max"), CatalogWord("high"), CatalogWord("medium"), CatalogWord("low"), CatalogWord("minimal")]
        )
        let fetched = FetchedCatalog(
            models: [catalogModel("vendor/a", efforts: ["max", "high", "low"], parameters: ["reasoning"])],
            vocabularies: [:],
            efforts: ["max", "high", "medium", "low", "minimal"]
        )

        let snapshot = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: previous, today: "2026-10-29")

        #expect(
            snapshot.models.first?.removedReasoningEfforts == [
                CatalogWord("medium", removedOn: "2026-10-29"), CatalogWord("minimal", removedOn: "2026-10-01"),
            ]
        )
    }

    @Test func `a model listed again without a level it had when it left keeps that level, marked removed`() throws {
        let model = catalogModel("vendor/a", efforts: ["high", "low"], parameters: ["reasoning"])
        let removed = RemovedModel(model: model, removedOn: "2026-10-01")
        let previous = catalogSnapshot(removed: [removed], efforts: [CatalogWord("high"), CatalogWord("low")])
        let fetched = FetchedCatalog(
            models: [catalogModel("vendor/a", efforts: ["high"], parameters: ["reasoning"])],
            vocabularies: [:],
            efforts: ["high", "low"]
        )

        let snapshot = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: previous, today: "2026-10-29")

        #expect(snapshot.removed.isEmpty)
        #expect(snapshot.models.first?.removedReasoningEfforts == [CatalogWord("low", removedOn: "2026-10-29")])
    }

    @Test func `a model that leaves keeps the efforts it had stopped accepting`() throws {
        let removedEfforts = [CatalogWord("low", removedOn: "2026-10-01")]
        let fetched = FetchedCatalog(models: Self.models("a", "b", "c", "d"), vocabularies: [:], efforts: ["high", "low"])
        let previous = catalogSnapshot(
            catalogModel("vendor/a"),
            catalogModel("vendor/b"),
            catalogModel("vendor/c"),
            catalogModel("vendor/d"),
            catalogModel("vendor/e", efforts: ["high"], parameters: ["reasoning"], removedEfforts: removedEfforts)
        )

        let snapshot = try CatalogSnapshot.updated(source: .openrouter, fetched: fetched, previous: previous, today: "2026-10-29")

        #expect(snapshot.removed.first?.model.removedReasoningEfforts == removedEfforts)
    }

    @Test func `a model's removed efforts are stored only when it has some, and read back`() throws {
        let removedEfforts = [CatalogWord("low", removedOn: "2026-10-01")]
        let plain = try CatalogJSON.encoded(catalogModel("vendor/a", efforts: ["high"], parameters: ["reasoning"]))
        let withRemoved = try CatalogJSON.encoded(
            catalogModel("vendor/a", efforts: ["high"], parameters: ["reasoning"], removedEfforts: removedEfforts))

        #expect(!plain.contains("removedReasoningEfforts"))
        #expect(try JSONDecoder().decode(CatalogModel.self, from: Data(withRemoved.utf8)).removedReasoningEfforts == removedEfforts)
    }

    /// The reasoning flags that snapshots stored before `reasoning`.
    private static func flags(mandatory: Bool, byDefault: Bool) -> String {
        #""isReasoningMandatory": \#(mandatory), "reasonsByDefault": \#(byDefault)"#
    }

    /// A model as a snapshot written before `reasoning` stores it: with the given flags, if any, and one parameter.
    private static func storedModel(id: String = "vendor/a", flags: String?, parameter: String) -> String {
        let fields = [
            #""id": "\#(id)", "displayName": "A", "releasedAt": 0, "inputModalities": ["text"], "outputModalities": ["text"]"#,
            #""supportedParameters": ["\#(parameter)"], "reasoningEfforts": []"#,
            flags,
        ]
        return "{\(fields.compactMap(\.self).joined(separator: ", "))}"
    }

    private static func models(_ names: String...) -> [CatalogModel] {
        names.map { catalogModel("vendor/\($0)") }
    }

    private func update(with fetched: [CatalogModel]) throws -> CatalogSnapshot {
        try CatalogSnapshot.updated(
            source: .openrouter,
            fetched: FetchedCatalog(models: fetched, vocabularies: [:], efforts: []),
            previous: Self.previous,
            today: "2026-10-29"
        )
    }
}
