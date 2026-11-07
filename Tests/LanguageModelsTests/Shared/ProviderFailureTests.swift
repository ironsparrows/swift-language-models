import FoundationModels
import LanguageModels
import Testing

@Suite("Provider failure", .timeLimit(.minutes(1)))
struct ProviderFailureTests {
    @Test(arguments: [
        LanguageModelError.ProviderFailure.contextSizeExceeded(contextSize: 8, tokenCount: 9), .rateLimited(resetDate: nil),
        .guardrailViolation,
        .refusal, .timeout, .unsupportedContent([]),
    ])
    func `every kind of failure reads the provider's facts from its metadata`(failure: LanguageModelError.ProviderFailure) {
        var metadata = LanguageModelError.failureMetadata(status: 429, code: "rate_limit_exceeded", provider: "Vendor")
        metadata[LanguageModelMetadataKey.requestID] = "req_1"

        let facts = LanguageModelError(failure, message: "Failed.", metadata: metadata).providerMetadata

        #expect(facts.status == 429)
        #expect(facts.errorCode == "rate_limit_exceeded")
        #expect(facts.provider == "Vendor")
        #expect(facts.requestID == "req_1")
    }

    @Test(
        arguments: [
            ("This model's maximum context length is 128000 tokens. However, your messages resulted in 130000 tokens.", 128_000, 130_000),
            ("maximum context length is 200000 tokens. However, you requested about 250000 tokens", 200_000, 250_000),
            ("Your input exceeds the context window of 400000 tokens.", 400_000, nil),
            ("Your input exceeds the context window of this model.", nil, nil),
        ] as [(String, Int?, Int?)])
    func `an oversized prompt's message names the context size and the tokens it needs, when it does`(
        message: String, limit: Int?, requested: Int?
    ) {
        let sizes = LanguageModelError.ProviderFailure.contextSizes(in: message)

        #expect(sizes.limit == limit)
        #expect(sizes.requested == requested)
    }
}
