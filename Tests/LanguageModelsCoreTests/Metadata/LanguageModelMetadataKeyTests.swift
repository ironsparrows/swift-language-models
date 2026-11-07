import LanguageModelsCore
import Testing

@Suite("Metadata keys")
struct LanguageModelMetadataKeyTests {
    @Test(arguments: [
        (LanguageModelMetadataKey.model, "model"),
        (LanguageModelMetadataKey.provider, "provider"),
        (LanguageModelMetadataKey.responseID, "responseID"),
        (LanguageModelMetadataKey.finishReason, "finishReason"),
        (LanguageModelMetadataKey.serviceTier, "serviceTier"),
        (LanguageModelMetadataKey.citations, "citations"),
        (LanguageModelMetadataKey.cost, "cost"),
        (LanguageModelMetadataKey.cacheWriteTokenCount, "cacheWriteTokenCount"),
        (LanguageModelMetadataKey.status, "status"),
        (LanguageModelMetadataKey.webSearchCount, "webSearchCount"),
        (LanguageModelMetadataKey.errorCode, "errorCode"),
    ])
    func `each key keeps the spelling that saved transcripts keep`(key: String, spelling: String) {
        #expect(key == spelling)
    }
}
