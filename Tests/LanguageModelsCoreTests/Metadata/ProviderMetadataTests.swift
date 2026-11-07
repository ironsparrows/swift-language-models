import Foundation
import FoundationModels
import LanguageModelsCore
import Testing

/// A key as saved transcripts keep it, a value under it, and whether the reader reads that value as its fact.
private let responseKeys: [(spelling: String, value: GeneratedContent, reads: @Sendable (ProviderResponseMetadata) -> Bool)] = [
    ("model", GeneratedContent("vendor/model"), { $0.model == "vendor/model" }),
    ("provider", GeneratedContent("Vendor"), { $0.host == "Vendor" }),
    ("responseID", GeneratedContent("gen-1"), { $0.responseID == "gen-1" }),
    ("requestID", GeneratedContent("req_1"), { $0.requestID == "req_1" }),
    ("finishReason", GeneratedContent("length"), { $0.finishReason == .length }),
    ("serviceTier", GeneratedContent("flex"), { $0.serviceTier == "flex" }),
    (
        "citations", GeneratedContent(kind: .array([GeneratedContent(properties: ["url": "https://swift.org/blog/"])])),
        { $0.citations.map(\.url.absoluteString) == ["https://swift.org/blog/"] }
    ),
    ("cost", GeneratedContent(kind: .number(0.25)), { $0.usage.cost == 0.25 }),
    ("cacheWriteTokenCount", GeneratedContent(kind: .number(176)), { $0.usage.cacheWriteTokenCount == 176 }),
    ("webSearchCount", GeneratedContent(kind: .number(2)), { $0.usage.webSearchCount == 2 }),
]

/// Every fact of an answer.
private let everyFact = ProviderResponseMetadata(
    model: "vendor/model", host: "Vendor", responseID: "gen-1", requestID: "req_1", finishReason: .length, serviceTier: "flex",
    citations: [Citation(url: URL(filePath: "/page"), title: "Page", excerpt: "Text", startOffset: 0, endOffset: 4)],
    usage: ProviderUsageMetadata(cost: Decimal(string: "0.000012345"), cacheWriteTokenCount: 176, webSearchCount: 2))

@Suite("Provider metadata")
struct ProviderMetadataTests {
    @Test(arguments: responseKeys)
    func `each fact reads from the key that saved transcripts keep`(
        spelling: String, value: GeneratedContent, reads: @Sendable (ProviderResponseMetadata) -> Bool
    ) {
        #expect(reads(ProviderResponseMetadata([spelling: value])))
    }

    @Test func `every fact is written under the key that saved transcripts keep`() {
        #expect(Set(everyFact.channelMetadata.keys) == Set(responseKeys.map(\.spelling)))
    }

    @Test func `the keys of an error's facts never change`() {
        let metadata = ProviderErrorMetadata.metadata(status: 429, code: "rate_limit_exceeded", provider: "Vendor", requestID: "req_1")

        #expect(metadata["status"] as? Int == 429)
        #expect(metadata["errorCode"] as? String == "rate_limit_exceeded")
        #expect(metadata["provider"] as? String == "Vendor")
        #expect(metadata["requestID"] as? String == "req_1")
    }

    @Test func `facts written and read back are unchanged`() {
        #expect(ProviderResponseMetadata(everyFact.channelMetadata.mapValues { $0.generatedContent }) == everyFact)
    }

    @Test func `a usage's facts written and read back are unchanged`() {
        let metadata = everyFact.usage.channelMetadata.mapValues { $0.generatedContent }

        #expect(ProviderUsageMetadata(metadata) == everyFact.usage)
    }

    @Test func `facts nobody reported write nothing`() {
        #expect(ProviderResponseMetadata().channelMetadata.isEmpty)
    }

    @Test(arguments: [0, 0.000_012_345, 0.000_25, 0.1, 0.300_000_000_000_000_04, 1e-7, 3, 1_234.567_8])
    func `a cost goes back as the number it was read from`(number: Double) throws {
        let cost = try #require(Decimal(metadataNumber: number))

        let written = try #require(ProviderUsageMetadata(cost: cost).channelMetadata["cost"]?.generatedContent)

        guard case .number(let value) = written.kind else {
            Issue.record("The cost is \(written)")
            return
        }
        #expect(value == number)
    }
}
