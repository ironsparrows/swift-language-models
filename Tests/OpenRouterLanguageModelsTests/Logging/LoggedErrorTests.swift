import Foundation
import FoundationModels
import Testing

@testable import LanguageModels
@testable import OpenRouterLanguageModels

@Suite("Logged errors")
struct LoggedErrorTests {
    @Test func `an OpenRouter error logs its status, code and host`() {
        let error = OpenRouterError(status: 402, message: "No credits for “Plan dinner”.", code: .paymentRequired, providerName: "Vendor")

        #expect(
            LoggedError(error)
                == LoggedError(kind: "OpenRouterError", status: 402, code: "payment_required", host: "Vendor"))
    }

    @Test func `a failure that becomes a language model error logs the case, and the status, code and host it came from`() {
        let body = OpenRouterErrorResponse(message: "Slow down.", metadata: ["provider_name": "Vendor"])
        let error = OpenRouterFailure(status: 429, body: body, retryAfter: nil).error(contextSize: nil)

        #expect(
            LoggedError(error)
                == LoggedError(
                    kind: "LanguageModelError.rateLimited", status: 429, code: "rate_limit_exceeded", host: "Vendor")
        )
    }

    @Test(arguments: [
        (
            LoggedError(kind: "OpenRouterError", status: 402, code: "payment_required", host: "Vendor"),
            "HTTP 402, payment_required, host Vendor"
        ),
        (LoggedError(kind: "OpenRouterError", status: nil, code: "connection_failed", host: nil), "connection_failed"),
        (LoggedError(kind: "LanguageModelError.contextSizeExceeded", status: nil, code: nil, host: nil), ""),
    ])
    func `the origin names only the parts that are known`(error: LoggedError, origin: String) {
        #expect(error.origin == origin)
    }

    @Test func `any other error logs its type`() {
        #expect(LoggedError(CancellationError()).kind == "Swift.CancellationError")
        #expect(LoggedError(URLError(.notConnectedToInternet)).status == nil)
    }
}
