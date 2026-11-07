import FoundationModels
import LanguageModels
import Testing

@Suite("Reasoning origin")
struct ReasoningOriginTests {
    @Test func `saved transcripts keep the origin under a key that never changes`() {
        #expect(ReasoningOrigin.metadataKey == "reasoningOrigin")
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
        let reasoning = Transcript.Reasoning(metadata: [ReasoningOrigin.metadataKey: 1], segments: [])

        #expect(ReasoningOrigin(of: reasoning) == nil)
    }
}
