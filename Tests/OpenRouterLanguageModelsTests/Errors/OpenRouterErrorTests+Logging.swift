import Foundation
import FoundationModels
import LanguageModels
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterErrorTests {
    @Suite("Logging")
    struct Logging {
        @Test func `an OpenRouter error logs its status, code and host`() {
            let error = OpenRouterError(
                status: 402, message: "No credits for “Plan dinner”.", code: .paymentRequired, provider: "Vendor")

            let fields = error.logFields

            #expect(fields.kind == "OpenRouterError")
            #expect(fields.status == 402)
            #expect(fields.code == "payment_required")
            #expect(fields.host == "Vendor")
        }

        @Test func `a failure that becomes a language model error keeps the status, code and host the log reads`() throws {
            let body = OpenRouterErrorResponse(message: "Slow down.", metadata: ["provider_name": "Vendor"])
            let failure = OpenRouterFailure(status: 429, body: body, retryAfter: nil)

            let error = try #require(failure.error(contextSize: nil) as? LanguageModelError)

            #expect(error.providerMetadata.status == 429)
            #expect(error.providerMetadata.code == "rate_limit_exceeded")
            #expect(error.providerMetadata.host == "Vendor")
        }
    }
}
