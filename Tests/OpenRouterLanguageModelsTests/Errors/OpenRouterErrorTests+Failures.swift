import Foundation
import FoundationModels
import LanguageModels
import Testing

@testable import OpenRouterLanguageModels

/// A failed response: its status, the `metadata` of its error, the message, and the error it should become.
private let failures: [(status: Int, metadata: JSONValue?, message: String, kind: String)] = [
    (400, ["error_type": "context_length_exceeded"], "Too long.", "LanguageModelError.contextSizeExceeded"),
    (400, ["error_type": "token_limit_exceeded"], "Token budget reached.", "OpenRouterError"),
    (400, nil, "This model's maximum context length is 200000 tokens.", "LanguageModelError.contextSizeExceeded"),
    (400, nil, "Bad request.", "OpenRouterError"),
    (429, nil, "Slow down.", "LanguageModelError.rateLimited"),
    (400, ["error_type": "rate_limit_exceeded"], "Slow down.", "LanguageModelError.rateLimited"),
    (402, ["limit_source": "openrouter_in_flight_budget"], "Too many at once.", "LanguageModelError.rateLimited"),
    (402, nil, "No credits.", "OpenRouterError"),
    (403, ["flagged_input": "…"], "Flagged.", "LanguageModelError.guardrailViolation"),
    (403, nil, "Not allowed.", "OpenRouterError"),
    // Only the router's report shows a content filter's block, not the message.
    (403, ["provider_name": nil], "Request blocked by content filter: [BLOCKED]", "OpenRouterError"),
    (403, ["limit_source": "api_key", "resets_at": "2026-11-03T00:00:00.000Z"], "Budget spent.", "LanguageModelError.rateLimited"),
    (403, ["limit_source": "api_key", "resets_at": nil], "Budget spent.", "OpenRouterError"),
    (400, ["error_type": "content_policy_violation"], "Flagged.", "LanguageModelError.guardrailViolation"),
    (400, ["error_type": "refusal"], "I can't help with that.", "LanguageModelError.refusal"),
    (408, nil, "Timed out.", "LanguageModelError.timeout"),
    (504, nil, "Gateway timed out.", "LanguageModelError.timeout"),
    (524, nil, "Timed out.", "LanguageModelError.timeout"),
    (500, ["error_type": "timeout"], "Timed out.", "LanguageModelError.timeout"),
    (500, nil, "Failed.", "OpenRouterError"),
    (503, nil, "No host.", "OpenRouterError"),
    // An error type that names a case wins over the body's flags, which win over any other error type.
    (402, ["error_type": "refusal", "limit_source": "openrouter_in_flight_budget"], "No.", "LanguageModelError.refusal"),
    (403, ["error_type": "permission_denied", "reasons": ["violence"]], "Flagged.", "LanguageModelError.guardrailViolation"),
]

extension OpenRouterErrorTests {
    @Suite("Failures")
    struct Failures {
        @Test(arguments: failures)
        func `a failure becomes the language model error for its code, or an OpenRouter error`(
            failure: (status: Int, metadata: JSONValue?, message: String, kind: String)
        ) {
            let body = OpenRouterErrorResponse(message: failure.message, metadata: failure.metadata)

            let error = OpenRouterFailure(status: failure.status, body: body, retryAfter: nil).error(contextSize: nil)

            #expect(kind(of: error) == failure.kind)
        }

        @Test func `an oversized prompt's error keeps its status and code in its metadata`() throws {
            let body = OpenRouterErrorResponse(message: "This model's maximum context length is 16384 tokens.", metadata: nil)

            let error = try #require(
                OpenRouterFailure(status: 400, body: body, retryAfter: nil).error(contextSize: nil) as? LanguageModelError)

            guard case .contextSizeExceeded(let info) = error else {
                Issue.record("Expected the context size to be exceeded, got \(error)")
                return
            }
            #expect(info.metadata["status"] as? Int == 400)
            #expect(info.metadata["errorCode"] as? String == "context_length_exceeded")
        }

        @Test func `a budget that resets throws a rate limit with its reset date and limit source`() throws {
            let metadata: JSONValue = ["limit_source": "api_key", "resets_at": "2026-11-03T00:00:00.000Z"]
            let body = OpenRouterErrorResponse(message: "Budget spent.", metadata: metadata)

            let error = try #require(
                OpenRouterFailure(status: 403, body: body, retryAfter: nil).error(contextSize: nil) as? LanguageModelError)

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            #expect(info.resetDate == Date(timeIntervalSince1970: 1_793_664_000))
            #expect(info.metadata["openRouter.limitSource"] as? String == "api_key")
            #expect(info.metadata["errorCode"] as? String == "budget_exceeded")
            #expect(error.openRouter.limitSource == .apiKey)
            #expect(error.openRouter.errorCode == .budgetExceeded)
            #expect(error.openRouter.status == 403)
        }

        @Test func `a lifetime budget throws the budget code`() throws {
            let body = OpenRouterErrorResponse(message: "Budget spent.", metadata: ["limit_source": "api_key"])

            let error = try #require(
                OpenRouterFailure(status: 403, body: body, retryAfter: nil).error(contextSize: nil) as? OpenRouterError)

            #expect(error.code == .budgetExceeded)
            #expect(error.isQuotaExhausted)
        }

        @Test(arguments: [
            (OpenRouterError.Code.paymentRequired, true), (.budgetExceeded, true), (.authentication, false), (.server, false),
        ])
        func `only credits or a spending limit that ran out count as an exhausted quota`(code: OpenRouterError.Code, isExhausted: Bool) {
            #expect(OpenRouterError(message: "Failed.", code: code).isQuotaExhausted == isExhausted)
        }

        @Test func `a rate limit's reset date is the wait after the moment of the failure`() throws {
            let now = Date(timeIntervalSince1970: 1_793_000_000)
            let failure = OpenRouterFailure(status: 429, body: nil, retryAfter: .seconds(30))

            let error = try #require(failure.error(contextSize: nil, now: now) as? LanguageModelError)

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            #expect(info.resetDate == now.addingTimeInterval(30))
        }

        @Test func `an error in a stream without a status or code is a host failing while it generates`() throws {
            let body = OpenRouterErrorResponse(code: "server_error", message: "Overloaded.", metadata: nil)

            let error = try #require(OpenRouterFailure(streamError: body, provider: "Vendor").error(contextSize: nil) as? OpenRouterError)

            #expect(error == OpenRouterError(message: "Overloaded.", code: "server_error", providerName: "Vendor"))
        }
    }
}

/// An error's type, and its case for a language model error.
private func kind(of error: any Error) -> String {
    guard let error = error as? LanguageModelError else { return String(describing: type(of: error)) }
    return switch error {
    case .contextSizeExceeded: "LanguageModelError.contextSizeExceeded"
    case .rateLimited: "LanguageModelError.rateLimited"
    case .guardrailViolation: "LanguageModelError.guardrailViolation"
    case .refusal: "LanguageModelError.refusal"
    case .timeout: "LanguageModelError.timeout"
    default: "another LanguageModelError"
    }
}
