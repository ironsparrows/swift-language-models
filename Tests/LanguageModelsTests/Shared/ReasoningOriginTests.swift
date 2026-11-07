import FoundationModels
import Testing

@testable import LanguageModels

@Suite("Reasoning origin", .timeLimit(.minutes(1)))
struct ReasoningOriginTests {
    @Test func `saved transcripts keep a reasoning entry's facts under keys that never change`() {
        let metadata = ReasoningOrigin(rawValue: "vendor").metadata(model: "vendor/model", taggedBlock: "<think>Hm.</think>")

        #expect(Set(metadata.keys) == ["reasoningOrigin", "model", "taggedReasoning"])
    }

    @Test func `an entry tagged with an origin names it`() {
        let origin = ReasoningOrigin(rawValue: "vendor")
        let reasoning = Transcript.Reasoning(metadata: origin.metadata(model: nil, taggedBlock: nil), segments: [])

        #expect(ReasoningOrigin(of: reasoning) == origin)
    }

    @Test func `the tag survives other metadata on the entry`() {
        var metadata = ReasoningOrigin(rawValue: "vendor").metadata(model: nil, taggedBlock: nil)
        metadata["model"] = "vendor/model"
        let reasoning = Transcript.Reasoning(metadata: metadata, segments: [])

        #expect(ReasoningOrigin(of: reasoning) == ReasoningOrigin(rawValue: "vendor"))
    }

    @Test func `an entry without a tag has no origin`() {
        let reasoning = Transcript.Reasoning(metadata: ["LanguageModels.provider": "vendor"], segments: [])

        #expect(ReasoningOrigin(of: reasoning) == nil)
    }

    @Test func `a tag that isn't text names no origin`() {
        let reasoning = Transcript.Reasoning(metadata: ["reasoningOrigin": 1], segments: [])

        #expect(ReasoningOrigin(of: reasoning) == nil)
    }
}
