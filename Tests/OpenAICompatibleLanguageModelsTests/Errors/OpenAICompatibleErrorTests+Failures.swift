import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension OpenAICompatibleErrorTests {
    @Suite("Failures")
    struct Failures {
        /// What a failure is expected to become.
        enum Outcome: Equatable, Sendable, CustomTestStringConvertible {
            case rateLimited
            case contextSizeExceeded(contextSize: Int, tokenCount: Int)
            case guardrailViolation
            case timeout
            case unsupportedContent
            case moduleError(OpenAICompatibleError.Code, quotaExhausted: Bool)

            var testDescription: String { "\(self)" }
        }

        @Test(arguments: [
            (400, "unmapped", false), (401, "authentication", false), (402, "payment_required", false), (403, "permission_denied", false),
            (404, "not_found", false), (408, "unmapped", true), (409, "conflict", false), (412, "unmapped", false),
            (413, "unmapped", false), (418, "unmapped", false), (422, "unprocessable", false), (429, "unmapped", true),
            (500, "server", false), (501, "server", false), (502, "server", false), (503, "server", false), (504, "server", true),
            (524, "server", true), (529, "server", false), (600, "server", false),
        ])
        func `a status stands for its kind when the body names none`(status: Int, code: String, isLanguageModelError: Bool) async {
            let stub = HTTPStub(.json(#"{"error":{"message":"Failed."}}"#, status: status))
            var limited = model(stub)
            limited.configuration.retries = .disabled

            let error = await #expect(throws: (any Error).self) { try await LanguageModelSession(model: limited).respond(to: "Hi") }

            let languageModelError = error as? LanguageModelError
            #expect((languageModelError != nil) == isLanguageModelError)
            #expect((languageModelError?.openAICompatible.code ?? (error as? OpenAICompatibleError)?.code)?.rawValue == code)
        }

        @Test(
            arguments: [
                (429, #"{"error":{"message":"Rate limit reached.","type":"requests","code":"rate_limit_exceeded"}}"#, Outcome.rateLimited),
                (
                    429,
                    #"{"error":{"message":"You exceeded your current quota.","type":"insufficient_quota","code":"insufficient_quota"}}"#,
                    .moduleError(.insufficientQuota, quotaExhausted: true)
                ),
                (
                    402, #"{"error":{"message":"Insufficient Balance","type":"unknown_error"}}"#,
                    .moduleError(.paymentRequired, quotaExhausted: true)
                ),
                (
                    400,
                    #"{"error":{"message":"This model's maximum context length is 4096 tokens. However, you requested 5000 tokens in the messages.","type":"BadRequestError","param":null,"code":400}}"#,
                    .contextSizeExceeded(contextSize: 4_096, tokenCount: 5_000)
                ),
                (
                    400, #"{"error":{"message":"The input is too long for the context window.","code":"context_length_exceeded"}}"#,
                    .contextSizeExceeded(contextSize: 128_000, tokenCount: 0)
                ),
                (400, #"{"error":{"message":"Flagged by the content filter.","code":"content_policy_violation"}}"#, .guardrailViolation),
                (400, #"{"error":{"message":"The image isn't valid.","code":"invalid_image_format"}}"#, .unsupportedContent),
                (504, #"{"error":{"message":"Timed out."}}"#, .timeout),
                (
                    404, #"{"error":{"message":"The model doesn't exist.","code":"model_not_found"}}"#,
                    .moduleError(.modelNotFound, quotaExhausted: false)
                ),
            ] as [(Int, String, Outcome)])
        func `a failed response throws what its status and error say`(status: Int, body: String, outcome: Outcome) async {
            // A 429 or a 504 is retried twice, so it fails three times.
            let failure = StubResponse.json(body, status: status, headers: ["x-request-id": "req_1"])
            let stub = HTTPStub(failure, failure, failure)

            let error = await #expect(throws: (any Error).self) { try await LanguageModelSession(model: model(stub)).respond(to: "Hi") }

            #expect(Self.outcome(of: error) == outcome)
        }

        @Test func `a failure that becomes Foundation Models' error names the provider, its code and its request id`() async throws {
            let failure = StubResponse.json(
                #"{"error":{"message":"Rate limit reached.","code":"rate_limit_exceeded"}}"#, status: 429,
                headers: ["x-request-id": "req_1", "Retry-After": "30"])
            let stub = HTTPStub(failure, failure, failure)
            var limited = model(stub)
            limited.configuration.retries = .disabled
            let before = Date.now

            let error = await #expect(throws: LanguageModelError.self) { try await LanguageModelSession(model: limited).respond(to: "Hi") }

            #expect(error?.openAICompatible.providerName == "Gateway")
            #expect(error?.openAICompatible.status == 429)
            #expect(error?.openAICompatible.code == "rate_limit_exceeded")
            #expect(error?.openAICompatible.requestID == "req_1")
            #expect(error?.providerMetadata.code == "rate_limit_exceeded")
            #expect(error?.providerMetadata.requestID == "req_1")
            #expect(error?.providerMetadata.host == nil)
            guard case .rateLimited(let context)? = error, let reset = context.resetDate else {
                Issue.record("Expected a rate limit with a reset date, got \(String(describing: error))")
                return
            }
            #expect(reset.timeIntervalSince(before) >= 30)
        }

        @Test func `a server that asks for a longer wait than the retries allow fails at once, with the wait on the error`() async {
            let stub = HTTPStub(.json(#"{"error":{"message":"Busy."}}"#, status: 503, headers: ["Retry-After": "600"]))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub)).respond(to: "Hi")
            }

            #expect(
                error
                    == OpenAICompatibleError(
                        providerName: "Gateway", status: 503, message: "Busy.", code: .server, retryAfter: .seconds(600)))
        }

        @Test func `the module's error prints the provider's name before the message, and logs its kind and code`() {
            let error = OpenAICompatibleError(providerName: "Gateway", status: 401, message: "Invalid API Key", code: .invalidAPIKey)

            #expect(error.errorDescription == "[Gateway] Invalid API Key")
            #expect(error.logFields == ("OpenAICompatibleError", 401, "invalid_api_key", nil))
        }

        /// What an error is, as an outcome.
        private static func outcome(of error: (any Error)?) -> Outcome? {
            switch error {
            case let error as OpenAICompatibleError:
                return .moduleError(error.code, quotaExhausted: error.isQuotaExhausted)
            case let error as LanguageModelError:
                switch error {
                case .rateLimited: return .rateLimited
                case .contextSizeExceeded(let context):
                    return .contextSizeExceeded(contextSize: context.contextSize, tokenCount: context.tokenCount)
                case .guardrailViolation: return .guardrailViolation
                case .timeout: return .timeout
                case .unsupportedTranscriptContent: return .unsupportedContent
                default: return nil
                }
            default:
                return nil
            }
        }
    }
}
