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
}
