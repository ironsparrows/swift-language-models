import Foundation
import FoundationModels
import Testing

@testable import LanguageModels

@Suite("Logged errors", .timeLimit(.minutes(1)))
struct LoggedErrorTests {
    private struct ProviderError: LoggableError {
        var logFields: (kind: String, status: Int?, code: String?, host: String?) {
            ("ProviderError", 402, "payment_required", "Vendor")
        }
    }

    @Test func `a provider's error logs its own fields`() {
        #expect(LoggedError(ProviderError()) == LoggedError(kind: "ProviderError", status: 402, code: "payment_required", host: "Vendor"))
    }

    @Test func `a language model error logs its case, and the status, code and host in its metadata`() {
        let metadata = ProviderErrorMetadata(status: 429, code: "rate_limit_exceeded", host: "Vendor").contextMetadata
        let error = LanguageModelError(.rateLimited(resetDate: nil), message: "Slow down.", metadata: metadata)

        #expect(
            LoggedError(error)
                == LoggedError(kind: "LanguageModelError.rateLimited", status: 429, code: "rate_limit_exceeded", host: "Vendor"))
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
