import FoundationModels
import Testing

@testable import LanguageModelsCore

@Suite("Provider error metadata")
struct ProviderErrorMetadataTests {
    @Test func `an error without the provider's facts reads as none`() {
        let facts = LanguageModelError.timeout(.init(debugDescription: "Timed out.")).providerMetadata

        #expect(facts == ProviderErrorMetadata([:]))
        #expect(facts.status == nil)
        #expect(facts.requestID == nil)
    }

    @Test func `facts written as an error's metadata and read back are unchanged`() {
        let facts = ProviderErrorMetadata(status: 429, code: "rate_limit_exceeded", host: "Vendor", requestID: "req_1")

        let error = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "Slow down.", metadata: facts.contextMetadata))

        #expect(error.providerMetadata == facts)
    }

    @Test func `a fact that's nil has no key`() {
        #expect(ProviderErrorMetadata(status: 429).contextMetadata.keys.sorted() == ["status"])
    }
}
