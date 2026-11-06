import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

/// What every failure becomes, through a session: its type, code, status, message and metadata. Each line pair names a
/// failure and the error it ended in, so a change to how failures map shows up here, precedence included.
@Suite("OpenAI error snapshots")
struct OpenAIErrorSnapshotTests {
    @Test func `every failed response ends in the error it maps to`() async {
        let failures = await [
            (
                "401 invalid key",
                rejected(
                    401,
                    #"{"error":{"message":"Incorrect API key provided.","type":"invalid_request_error","code":"invalid_api_key","param":null}}"#
                )
            ),
            (
                "429 rate limit",
                rejected(429, #"{"error":{"message":"Rate limit reached.","type":"requests","code":"rate_limit_exceeded"}}"#)
            ),
            (
                "429 quota",
                rejected(
                    429,
                    #"{"error":{"message":"You exceeded your current quota.","type":"insufficient_quota","code":"insufficient_quota"}}"#)
            ),
            (
                "429 spend limit",
                rejected(429, #"{"error":{"message":"Spend limit.","type":"insufficient_quota","code":"project_spend_limit_exceeded"}}"#)
            ),
            (
                "429 credits",
                rejected(
                    429, #"{"error":{"message":"Credit balance exhausted.","type":"insufficient_quota","code":"credit_balance_exhausted"}}"#
                )
            ),
            (
                "429 that says not to retry",
                rejected(
                    429, #"{"error":{"message":"Slow down.","type":"requests","code":"rate_limit_exceeded"}}"#,
                    headers: ["x-should-retry": "false"])
            ),
            (
                "400 context with both sizes",
                rejected(
                    400,
                    #"{"error":{"message":"This model's maximum context length is 128000 tokens. However, your messages resulted in 130000 tokens.","type":"invalid_request_error","code":"context_length_exceeded"}}"#
                )
            ),
            (
                "400 context in the message",
                rejected(
                    400, #"{"error":{"message":"Your input exceeds the context window of this model.","type":"invalid_request_error"}}"#)
            ),
            (
                "400 flagged prompt",
                rejected(
                    400,
                    #"{"error":{"message":"Invalid prompt: your prompt was flagged as potentially violating our usage policy.","type":"invalid_request_error","code":"invalid_prompt"}}"#
                )
            ),
            (
                "400 invalid image",
                rejected(400, #"{"error":{"message":"Invalid image.","type":"invalid_request_error","code":"invalid_image_format"}}"#)
            ),
            (
                "400 with a parameter",
                rejected(
                    400, #"{"error":{"message":"Bad value.","type":"invalid_request_error","code":"invalid_value","param":"temperature"}}"#)
            ),
            ("403", rejected(403, #"{"error":{"message":"Country not supported."}}"#)),
            (
                "404",
                rejected(404, #"{"error":{"message":"The model does not exist.","type":"invalid_request_error","code":"model_not_found"}}"#)
            ),
            ("408", rejected(408, #"{"error":{"message":"Timed out."}}"#)),
            ("500 that isn't JSON", rejected(500, "<html>Internal Server Error</html>")),
        ]

        assertInlineSnapshot(of: report(failures), as: .lines) {
            """
            401 invalid key
            OpenAIError(status: Optional(401), message: "Incorrect API key provided.", code: invalid_api_key, errorType: Optional(invalid_request_error), parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: false)

            429 rate limit
            LanguageModelError.rateLimited resetDate: nil "Rate limit reached." metadata: [errorCode: rate_limit_exceeded, requestID: req_1, status: 429]

            429 quota
            OpenAIError(status: Optional(429), message: "You exceeded your current quota.", code: insufficient_quota, errorType: Optional(insufficient_quota), parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: true)

            429 spend limit
            OpenAIError(status: Optional(429), message: "Spend limit.", code: project_spend_limit_exceeded, errorType: Optional(insufficient_quota), parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: true)

            429 credits
            OpenAIError(status: Optional(429), message: "Credit balance exhausted.", code: credit_balance_exhausted, errorType: Optional(insufficient_quota), parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: true)

            429 that says not to retry
            LanguageModelError.rateLimited resetDate: nil "Slow down." metadata: [errorCode: rate_limit_exceeded, requestID: req_1, status: 429]

            400 context with both sizes
            LanguageModelError.contextSizeExceeded contextSize: 128000 tokenCount: 130000 "This model's maximum context length is 128000 tokens. However, your messages resulted in 130000 tokens." metadata: [errorCode: context_length_exceeded, requestID: req_1, status: 400]

            400 context in the message
            LanguageModelError.contextSizeExceeded contextSize: 400000 tokenCount: 0 "Your input exceeds the context window of this model." metadata: [errorCode: invalid_request_error, requestID: req_1, status: 400]

            400 flagged prompt
            LanguageModelError.guardrailViolation "Invalid prompt: your prompt was flagged as potentially violating our usage policy." metadata: [errorCode: invalid_prompt, requestID: req_1, status: 400]

            400 invalid image
            LanguageModelError.unsupportedTranscriptContent entries: [] "Invalid image." metadata: [errorCode: invalid_image_format, requestID: req_1, status: 400]

            400 with a parameter
            OpenAIError(status: Optional(400), message: "Bad value.", code: invalid_value, errorType: Optional(invalid_request_error), parameter: Optional("temperature"), requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: false)

            403
            OpenAIError(status: Optional(403), message: "Country not supported.", code: permission_denied, errorType: nil, parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: false)

            404
            OpenAIError(status: Optional(404), message: "The model does not exist.", code: model_not_found, errorType: Optional(invalid_request_error), parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: false)

            408
            LanguageModelError.timeout "Timed out." metadata: [errorCode: unmapped, requestID: req_1, status: 408]

            500 that isn't JSON
            OpenAIError(status: Optional(500), message: "internal server error", code: server, errorType: nil, parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: false)
            """
        }
    }

    @Test func `every failure in a stream ends in the error it maps to`() async throws {
        let recorded = try Bundle.module.fixture("no-credits-stream.sse")
        let failures = await [
            ("rate limit event", event(#"{"type":"error","code":"rate_limit_exceeded","message":"Slow down.","param":null}"#)),
            ("error event without a code", event(#"{"type":"error","code":null,"message":"Something went wrong.","param":null}"#)),
            (
                "error event with a nested error",
                event(#"{"type":"error","error":{"type":"insufficient_quota","code":"insufficient_quota","message":"Quota."}}"#)
            ),
            ("failed response", event(#"{"type":"response.failed","response":{"error":{"code":"server_error","message":"Failed."}}}"#)),
            ("failed response without an error", event(#"{"type":"response.failed","response":{"status":"failed"}}"#)),
            (
                "failed response about an image",
                event(#"{"type":"response.failed","response":{"error":{"code":"image_too_large","message":"Too large."}}}"#)
            ),
            ("event that can't be read", failure(.eventStream(Data("data: {not json\n\n".utf8)))),
            (
                "a real stream without credits",
                failure(
                    StubResponse(status: 200, headers: ["Content-Type": "text/event-stream", "x-request-id": "req_1"], chunks: [recorded]))
            ),
            ("cut off", failure(responseStream([created(), textDelta("Partial")]))),
            (
                "connection lost",
                failure(responseStream([created(), textDelta("Partial")]).droppingConnection(with: URLError(.networkConnectionLost)))
            ),
            (
                "connection timed out",
                failure(responseStream([created(), textDelta("Partial")]).droppingConnection(with: URLError(.timedOut)))
            ),
        ]

        assertInlineSnapshot(of: report(failures), as: .lines) {
            #"""
            rate limit event
            LanguageModelError.rateLimited resetDate: nil "Slow down." metadata: [errorCode: rate_limit_exceeded]

            error event without a code
            OpenAIError(status: nil, message: "Something went wrong.", code: server, errorType: nil, parameter: nil, requestID: nil, retryAfter: nil, isQuotaExhausted: false)

            error event with a nested error
            OpenAIError(status: nil, message: "Quota.", code: insufficient_quota, errorType: Optional(insufficient_quota), parameter: nil, requestID: nil, retryAfter: nil, isQuotaExhausted: true)

            failed response
            OpenAIError(status: nil, message: "Failed.", code: server_error, errorType: nil, parameter: nil, requestID: nil, retryAfter: nil, isQuotaExhausted: false)

            failed response without an error
            OpenAIError(status: nil, message: "The model\'s response ended in an error.", code: server, errorType: nil, parameter: nil, requestID: nil, retryAfter: nil, isQuotaExhausted: false)

            failed response about an image
            LanguageModelError.unsupportedTranscriptContent entries: [] "Too large." metadata: [errorCode: image_too_large]

            event that can't be read
            OpenAIError(status: nil, message: "OpenAI sent an event that couldn\'t be read: <decoding error>", code: invalid_response, errorType: nil, parameter: nil, requestID: nil, retryAfter: nil, isQuotaExhausted: false)

            a real stream without credits
            OpenAIError(status: nil, message: "You have no credits remaining. Add credits to continue using the API at https://platform.openai.com/settings/organization/billing/.", code: credit_balance_exhausted, errorType: Optional(insufficient_quota), parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: true)

            cut off
            OpenAIError(status: nil, message: "The response ended before it was complete.", code: invalid_response, errorType: nil, parameter: nil, requestID: nil, retryAfter: nil, isQuotaExhausted: false)

            connection lost
            URLError -1005

            connection timed out
            LanguageModelError.timeout "<the system's text>" metadata: []
            """#
        }
    }

    @Test func `every failed connection ends in the error it maps to`() async {
        let failures = await [
            ("not connected", failure(.failure(URLError(.notConnectedToInternet)))),
            ("host not found", failure(.failure(URLError(.cannotFindHost)))),
            ("can't connect", failure(.failure(URLError(.cannotConnectToHost)))),
            ("TLS failed", failure(.failure(URLError(.secureConnectionFailed)))),
            ("timed out", failure(.failure(URLError(.timedOut)))),
            ("cancelled", failure(.failure(URLError(.cancelled)))),
        ]

        assertInlineSnapshot(of: report(failures), as: .lines) {
            """
            not connected
            URLError -1009

            host not found
            URLError -1003

            can't connect
            URLError -1004

            TLS failed
            URLError -1200

            timed out
            LanguageModelError.timeout "<the system's text>" metadata: []

            cancelled
            CancellationError()
            """
        }
    }

    @Test func `every request refused before it goes out ends in its error`() async {
        let failures = await [
            (
                "a schema for a model without structured outputs",
                outcome { stub in
                    let details: OpenAIModel<ContextOptions.ReasoningLevel> = details(
                        parameters: [.maxOutputTokens, .reasoning], efforts: [.high])
                    _ = try await LanguageModelSession(model: model(stub, details)).respond(to: "Hi", generating: FoodTool.Arguments.self)
                }
            ),
            (
                "tools for a model without tools",
                outcome { stub in
                    let details: OpenAIModel<Efforts.Unsupported> = details(parameters: [.maxOutputTokens], reasoning: .unsupported)
                    _ = try await LanguageModelSession(model: model(stub, details), tools: [FoodTool()]).respond(to: "Hi")
                }
            ),
            (
                "a reasoning level for a model that doesn't reason",
                outcome { stub in
                    let contextOptions = ContextOptions(reasoningLevel: .moderate)
                    _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hi", contextOptions: contextOptions)
                }
            ),
        ]

        assertInlineSnapshot(of: report(failures), as: .lines) {
            """
            a schema for a model without structured outputs
            LanguageModelError.unsupportedCapability capability: guidedGeneration "<the system's text>" metadata: []

            tools for a model without tools
            LanguageModelError.unsupportedCapability capability: toolCalling "<the system's text>" metadata: []

            a reasoning level for a model that doesn't reason
            LanguageModelError.unsupportedCapability capability: reasoning "<the system's text>" metadata: []
            """
        }
    }

    /// The error of a failed response, with OpenAI's request id, that's answered the same way on every retry.
    private func rejected(_ status: Int, _ body: String, headers: [String: String] = [:]) async -> String {
        await failure(.json(body, status: status, headers: ["x-request-id": "req_1"].merging(headers) { $1 }))
    }

    /// The error of a stream that holds one event.
    private func event(_ event: String) async -> String {
        await failure(.eventStream(Data("data: \(event)\n\n".utf8)))
    }

    /// The error of a response that's answered the same way on every retry.
    private func failure(_ response: StubResponse) async -> String {
        await outcome(HTTPStub(response, response, response)) { stub in
            _ = try await LanguageModelSession(model: reasoningModel(stub)).respond(to: "Hi")
        }
    }

    /// What a session's answer ends in.
    private func outcome(_ stub: HTTPStub = HTTPStub(), answer: (HTTPStub) async throws -> Void) async -> String {
        do {
            try await answer(stub)
            return "no error"
        } catch {
            return ExactExchange.description(of: error)
        }
    }

    /// Each failure's name, then what it ended in.
    private func report(_ failures: [(String, String)]) -> String {
        failures.map { "\($0.0)\n\($0.1)" }.joined(separator: "\n\n")
    }
}
