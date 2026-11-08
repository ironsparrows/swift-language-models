import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

extension OpenAIErrorTests {
    @Suite("Failures")
    struct Failures {
        /// What a failure is expected to become.
        enum Outcome: Equatable, CustomTestStringConvertible {
            case rateLimited
            case contextSizeExceeded(contextSize: Int, tokenCount: Int)
            case guardrailViolation
            case timeout
            case unsupportedContent
            case openAIError(OpenAIError.Code, status: Int?)

            var testDescription: String { "\(self)" }
        }

        @Test(arguments: [
            (400, "unmapped", false), (401, "authentication", false), (402, "unmapped", false), (403, "permission_denied", false),
            (404, "not_found", false), (408, "unmapped", true), (409, "conflict", false), (412, "unmapped", false),
            (413, "unmapped", false), (418, "unmapped", false), (422, "unprocessable", false), (429, "unmapped", true),
            (500, "server", false), (501, "server", false), (502, "server", false), (503, "server", false), (504, "server", true),
            (524, "server", false), (529, "server", false), (600, "server", false),
        ])
        func `a status stands for its kind when the body names none`(status: Int, code: String, isLanguageModelError: Bool) async {
            let stub = HTTPStub(.json(#"{"error":{"message":"Failed."}}"#, status: status))
            var limited = reasoningModel(stub)
            limited.configuration.retries = .disabled

            let error = await #expect(throws: (any Error).self) { try await LanguageModelSession(model: limited).respond(to: "Hi") }

            let languageModelError = error as? LanguageModelError
            #expect((languageModelError != nil) == isLanguageModelError)
            #expect((languageModelError?.providerMetadata.code ?? (error as? OpenAIError)?.code.rawValue) == code)
        }

        @Test(
            arguments: [
                (
                    401,
                    #"{"error":{"message":"Incorrect API key provided.","type":"invalid_request_error","code":"invalid_api_key","param":null}}"#,
                    Outcome.openAIError(.invalidAPIKey, status: 401)
                ),
                (429, #"{"error":{"message":"Rate limit reached.","type":"requests","code":"rate_limit_exceeded"}}"#, .rateLimited),
                (
                    429,
                    #"{"error":{"message":"You exceeded your current quota.","type":"insufficient_quota","code":"insufficient_quota"}}"#,
                    .openAIError(.insufficientQuota, status: 429)
                ),
                (
                    429,
                    #"{"error":{"message":"Credit balance exhausted.","type":"insufficient_quota","code":"credit_balance_exhausted"}}"#,
                    .openAIError("credit_balance_exhausted", status: 429)
                ),
                (
                    400,
                    #"{"error":{"message":"This model's maximum context length is 128000 tokens. However, your messages resulted in 130000 tokens.","type":"invalid_request_error","code":"context_length_exceeded"}}"#,
                    .contextSizeExceeded(contextSize: 128_000, tokenCount: 130_000)
                ),
                (
                    400, #"{"error":{"message":"Your input exceeds the context window of this model.","type":"invalid_request_error"}}"#,
                    .contextSizeExceeded(contextSize: 400_000, tokenCount: 0)
                ),
                (
                    400,
                    #"{"error":{"message":"Invalid prompt: your prompt was flagged as potentially violating our usage policy.","type":"invalid_request_error","code":"invalid_prompt"}}"#,
                    .guardrailViolation
                ),
                (
                    400, #"{"error":{"message":"Invalid image.","type":"invalid_request_error","code":"invalid_image_format"}}"#,
                    .unsupportedContent
                ),
                (
                    404, #"{"error":{"message":"The model does not exist.","type":"invalid_request_error","code":"model_not_found"}}"#,
                    .openAIError(.modelNotFound, status: 404)
                ),
                (403, #"{"error":{"message":"Country not supported."}}"#, .openAIError(.permissionDenied, status: 403)),
                (500, "<html>Internal Server Error</html>", .openAIError(.server, status: 500)),
                (408, #"{"error":{"message":"Timed out."}}"#, .timeout),
            ] as [(Int, String, Outcome)])
        func `a failed response throws what its status and error say`(status: Int, body: String, outcome: Outcome) async {
            // A 408, 429 or 500 is retried twice, so it fails three times.
            let failure = StubResponse.json(body, status: status, headers: ["x-request-id": "req_1"])
            let stub = HTTPStub(failure, failure, failure)

            let error = await respond(stub)

            #expect(Self.outcome(of: error) == outcome)
            if case .openAIError = outcome { #expect((error as? OpenAIError)?.requestID == "req_1") }
        }

        @Test(
            arguments: [
                (#"{"error":{"message":"Quota.","type":"insufficient_quota","code":"insufficient_quota"}}"#, true),
                (#"{"error":{"message":"Spend limit.","type":"insufficient_quota","code":"project_spend_limit_exceeded"}}"#, true),
                (#"{"error":{"message":"No credits.","code":"credit_balance_exhausted"}}"#, true),
                (#"{"error":{"message":"Bad key.","type":"invalid_request_error","code":"invalid_api_key"}}"#, false),
            ] as [(String, Bool)])
        func `every code of a quota, credit or spending limit that ran out says so`(body: String, isQuotaExhausted: Bool) async throws {
            let failure = StubResponse.json(body, status: isQuotaExhausted ? 429 : 401)
            let stub = HTTPStub(failure, failure, failure)

            let error = try #require(await respond(stub) as? OpenAIError)

            #expect(error.isQuotaExhausted == isQuotaExhausted)
        }

        @Test func `a rate limit's reset date is the later of its limits' resets`() async throws {
            let failure = StubResponse.json(
                #"{"error":{"message":"Rate limit reached.","code":"rate_limit_exceeded"}}"#, status: 429,
                headers: ["x-ratelimit-reset-requests": "1s", "x-ratelimit-reset-tokens": "6m0s"])
            let stub = HTTPStub(failure, failure, failure)
            let before = Date.now

            let error = await respond(stub)

            guard case .rateLimited(let context)? = error as? LanguageModelError, let reset = context.resetDate else {
                Issue.record("The answer ended with \(String(describing: error))")
                return
            }
            #expect(reset.timeIntervalSince(before) >= 360)
            #expect(reset.timeIntervalSince(before) < 365)
        }

        @Test func `an error keeps OpenAI's error type beside its code`() async throws {
            let stub = HTTPStub(
                .json(#"{"error":{"message":"Bad key.","type":"invalid_request_error","code":"invalid_api_key"}}"#, status: 401))

            let error = try #require(await respond(stub) as? OpenAIError)

            #expect(error.code == .invalidAPIKey)
            #expect(error.errorType == .invalidRequest)
        }

        @Test func `a failure that isn't a rate limit has no retry delay from the rate limits' resets`() async throws {
            let stub = HTTPStub(
                .json(
                    #"{"error":{"message":"Bad key.","type":"invalid_request_error","code":"invalid_api_key"}}"#, status: 401,
                    headers: ["x-ratelimit-reset-requests": "1s", "x-ratelimit-reset-tokens": "6m0s"]))

            let error = try #require(await respond(stub) as? OpenAIError)

            #expect(error.retryAfter == nil)
        }

        @Test(
            arguments: [
                (#"{"type":"error","code":"rate_limit_exceeded","message":"Slow down.","param":null}"#, Outcome.rateLimited),
                (#"{"type":"error","code":null,"message":"Something went wrong.","param":null}"#, .openAIError(.server, status: nil)),
                (
                    #"{"type":"error","error":{"type":"insufficient_quota","code":"insufficient_quota","message":"Quota."}}"#,
                    .openAIError(.insufficientQuota, status: nil)
                ),
                (
                    #"{"type":"response.failed","response":{"error":{"code":"server_error","message":"Failed."}}}"#,
                    .openAIError(.serverError, status: nil)
                ),
                (#"{"type":"response.failed","response":{"status":"failed"}}"#, .openAIError(.server, status: nil)),
                (
                    #"{"type":"response.failed","response":{"error":{"code":"image_too_large","message":"Too large."}}}"#,
                    .unsupportedContent
                ),
            ] as [(String, Outcome)])
        func `a failure in the stream throws what its error says`(event: String, outcome: Outcome) async throws {
            let stub = HTTPStub(.eventStream(Data("data: \(event)\n\n".utf8)))

            #expect(Self.outcome(of: await respond(stub)) == outcome)
        }

        @Test func `a real stream that ran out of credits throws OpenAI's error with its code and request id`() async throws {
            let recorded = try Bundle.module.fixture("no-credits-stream.sse")
            let stub = HTTPStub(
                StubResponse(status: 200, headers: ["Content-Type": "text/event-stream", "x-request-id": "req_1"], chunks: [recorded]))

            let error = try #require(await respond(stub) as? OpenAIError)

            #expect(error.code == "credit_balance_exhausted")
            #expect(error.isQuotaExhausted)
            #expect(error.status == nil)
            #expect(error.requestID == "req_1")
            #expect(error.message.hasPrefix("You have no credits remaining."))
        }

        @Test func `a rate limit's error reads its status, code and request id as typed values`() async throws {
            let stub = HTTPStub(
                .json(
                    #"{"error":{"message":"Slow down.","type":"requests","code":"rate_limit_exceeded"}}"#, status: 429,
                    headers: ["x-request-id": "req_1", "x-should-retry": "false"]))

            let error = try #require(await respond(stub) as? LanguageModelError)

            #expect(error.providerMetadata.status == 429)
            #expect(error.providerMetadata.code == "rate_limit_exceeded")
            #expect(error.providerMetadata.requestID == "req_1")
            #expect(error.providerMetadata.host == nil)
            #expect(error.openAI.status == 429)
            #expect(error.openAI.code == "rate_limit_exceeded")
            #expect(error.openAI.requestID == "req_1")
        }

        @Test func `a stream cut off before its end throws an invalid response`() async {
            let stub = HTTPStub(responseStream([created(), textDelta("Partial")]))

            #expect(Self.outcome(of: await respond(stub)) == .openAIError(.invalidResponse, status: nil))
        }

        /// The error a prompt's answer ends in.
        private func respond(_ stub: HTTPStub) async -> (any Error)? {
            do {
                _ = try await LanguageModelSession(model: reasoningModel(stub)).respond(to: "Hi")
                return nil
            } catch {
                return error
            }
        }

        private static func outcome(of error: (any Error)?) -> Outcome? {
            switch error {
            case let error as OpenAIError:
                return .openAIError(error.code, status: error.status)
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
