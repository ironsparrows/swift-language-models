import FoundationModels
import LanguageModelsCore
import Testing

@Suite("Provider effort")
struct ProviderEffortTests {
    private static let ranking = ["max", "xhigh", "high", "medium", "low", "minimal", "none"]

    @Test(arguments: [
        (ContextOptions.ReasoningLevel.light, "low"),
        (.moderate, "medium"),
        (.deep, "high"),
        (.custom("max"), "max"),
    ])
    func `a level becomes the provider's word`(level: ContextOptions.ReasoningLevel, word: String) {
        let supported: [ContextOptions.ReasoningLevel] = [.custom("max"), .custom("high"), .custom("medium"), .custom("low")]

        #expect(level.providerEffort(supporting: supported, ranking: Self.ranking) == word)
    }

    @Test(
        arguments: [
            (ContextOptions.ReasoningLevel.moderate, ["high", "medium"], "medium", nil),
            (.moderate, ["high", "low"], "low", MovedEffort(requested: "medium", sent: "low")),
            (.custom("turbo"), ["high"], nil, MovedEffort(requested: "turbo", sent: nil)),
        ] as [(ContextOptions.ReasoningLevel, [String], String?, MovedEffort?)])
    func `the effort sent names the level it moved from, when it moved`(
        level: ContextOptions.ReasoningLevel, supported: [String], effort: String?, moved: MovedEffort?
    ) {
        let sent = level.sentEffort(supporting: supported.map(ContextOptions.ReasoningLevel.custom))

        #expect(sent.effort == effort)
        #expect(sent.moved == moved)
    }

    @Test(arguments: [
        (ContextOptions.ReasoningLevel.custom("xhigh"), ["max", "xhigh", "high"], "xhigh"),
        (.custom("max"), ["xhigh", "high", "medium", "low", "none"], "xhigh"),
        (.custom("xhigh"), ["max", "high", "medium", "low", "none"], "high"),
        (.deep, ["max", "xhigh"], "xhigh"),
        (.light, ["high"], "high"),
        (.custom("none"), ["medium", "low"], "low"),
        (.light, ["xhigh", "high", "none"], "high"),
        (.custom("minimal"), ["high", "none"], "high"),
    ])
    func `a level moves to the nearest level the model accepts`(
        level: ContextOptions.ReasoningLevel,
        supported: [String],
        word: String
    ) {
        let supported = supported.map(ContextOptions.ReasoningLevel.custom)

        #expect(level.providerEffort(supporting: supported, ranking: Self.ranking) == word)
    }

    @Test(arguments: [
        ("low", ["xhigh", "high", "none"], "high"),
        ("minimal", ["high", "none"], "high"),
        ("low", ["high", "minimal", "none"], "minimal"),
        ("none", ["high", "low", "none"], "none"),
        ("none", ["high", "low"], "low"),
    ])
    func `the nearest word is never none unless none is asked for`(word: String, supported: [String], nearest: String) {
        #expect(ContextOptions.ReasoningLevel.nearest(to: word, among: supported, ranking: Self.ranking) == nearest)
    }

    @Test func `a model that only turns reasoning off is sent no word for a level that reasons`() {
        #expect(ContextOptions.ReasoningLevel.nearest(to: "high", among: ["none"], ranking: Self.ranking) == nil)
    }

    @Test(arguments: [ContextOptions.ReasoningLevel.light, .moderate, .deep, .minimal])
    func `a level that reasons keeps reasoning on a model that can turn it off`(level: ContextOptions.ReasoningLevel) {
        #expect(level.providerEffort(supporting: XhighHighOff.allCases) == "high")
        #expect(level.providerEffort(supporting: HighOff.allCases) == "high")
    }

    @Test func `off turns reasoning off on a model that can turn it off`() {
        #expect(ContextOptions.ReasoningLevel.off.providerEffort(supporting: XhighHighOff.allCases) == "none")
        #expect(ContextOptions.ReasoningLevel.off.providerEffort(supporting: HighOff.allCases) == "none")
    }

    @Test func `a word new to the ranking takes its place in it`() {
        let supported: [ContextOptions.ReasoningLevel] = [.custom("max"), .custom("high")]

        #expect(
            ContextOptions.ReasoningLevel.custom("ultra").providerEffort(supporting: supported, ranking: ["ultra"] + Self.ranking)
                == "max"
        )
    }

    @Test func `a word missing from the ranking is left out for a model that lists its levels`() {
        let supported: [ContextOptions.ReasoningLevel] = [.custom("high"), .custom("low")]

        #expect(ContextOptions.ReasoningLevel.custom("ultra").providerEffort(supporting: supported, ranking: Self.ranking) == nil)
    }

    @Test(arguments: [
        (ContextOptions.ReasoningLevel.light, "low"),
        (.moderate, "medium"),
        (.deep, "high"),
        (.off, "none"),
        (.custom("ultra"), "ultra"),
    ])
    func `a level asks for its own effort word`(level: ContextOptions.ReasoningLevel, word: String) {
        #expect(level.effortWord == word)
    }

    @Test(arguments: [ContextOptions.ReasoningLevel.deep, .custom("high"), .custom("ultra")])
    func `no word is sent to a model that lists no levels`(level: ContextOptions.ReasoningLevel) {
        let supported: [ContextOptions.ReasoningLevel] = []

        #expect(level.providerEffort(supporting: supported, ranking: Self.ranking) == nil)
    }
}

/// The efforts of a test model that accepts `xhigh`, `high` and `none`.
private enum XhighHighOff: String, ModelEffort, CaseIterable {
    case xhigh
    case high
    case off = "none"
}

/// The efforts of a test model that accepts `high` and `none`.
private enum HighOff: String, ModelEffort, CaseIterable {
    case high
    case off = "none"
}
