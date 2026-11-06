import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// What every failure becomes, through a session: its type, code, status, message and metadata. Each line pair names a
/// failure and the error it ended in, so a change to how failures map shows up here, precedence included.
@Suite("OpenRouter error snapshots")
struct OpenRouterErrorSnapshotTests {
    @Test func `every failed response ends in the error it maps to`() async {
        let forbidden =
            #"{"error":{"message":"Request blocked by content filter: [BLOCKED]","code":403,"metadata":{"provider_name":null}},"#
        let pipeline = #""openrouter_metadata":{"pipeline":[{"type":"guardrail","name":"content-filter","#
        let failures = await [
            ("400 context length error type", rejected(400, "Too long.", ["error_type": "context_length_exceeded"])),
            ("400 token limit error type", rejected(400, "Token budget reached.", ["error_type": "token_limit_exceeded"])),
            ("400 context in the message", rejected(400, "This model's maximum context length is 200000 tokens.")),
            (
                "400 both sizes in the message",
                rejected(400, "This endpoint's maximum context length is 200000 tokens. However, you requested about 250000 tokens.")
            ),
            ("400 about a context setting", rejected(400, "Invalid value for context_management.")),
            ("400 without an error type", rejected(400, "Bad request.")),
            ("400 rate limit error type", rejected(400, "Slow down.", ["error_type": "rate_limit_exceeded"])),
            ("400 content policy error type", rejected(400, "Flagged.", ["error_type": "content_policy_violation"])),
            ("400 refusal error type", rejected(400, "I can't help with that.", ["error_type": "refusal"])),
            ("400 unknown error type", rejected(400, "Image not found", ["error_type": "image_not_found"])),
            ("401", rejected(401, "No auth credentials found")),
            ("402 without a limit", rejected(402, "No credits.")),
            ("402 in-flight budget", rejected(402, "Too many at once.", ["limit_source": "openrouter_in_flight_budget"])),
            (
                "402 refusal wins over the flags",
                rejected(402, "No.", ["error_type": "refusal", "limit_source": "openrouter_in_flight_budget"])
            ),
            ("403 without a flag", rejected(403, "Not allowed.")),
            ("403 flagged input", rejected(403, "Flagged.", ["flagged_input": "…"])),
            ("403 content filter without a report", rejected(403, "Request blocked by content filter: [BLOCKED]", ["provider_name": nil])),
            (
                "403 guardrail blocked",
                failure(.json(forbidden + pipeline + #""data":{"flagged":true,"action":"blocked"}}]}}"#, status: 403))
            ),
            (
                "403 guardrail redacted",
                failure(.json(forbidden + pipeline + #""data":{"flagged":true,"action":"redacted"}}]}}"#, status: 403))
            ),
            (
                "403 budget that resets",
                rejected(403, "Budget spent.", ["limit_source": "api_key", "resets_at": "2026-11-03T00:00:00.000Z"])
            ),
            ("403 lifetime budget", rejected(403, "Budget spent.", ["limit_source": "api_key", "resets_at": nil])),
            (
                "403 reasons win over another error type",
                rejected(403, "Flagged.", ["error_type": "permission_denied", "reasons": ["violence"]])
            ),
            ("404", rejected(404, "Failed")),
            ("408", rejected(408, "Timed out.")),
            ("413", rejected(413, "Failed")),
            ("422", rejected(422, "Failed")),
            ("429", rejected(429, "Slow down.")),
            ("500", rejected(500, "Failed.")),
            ("500 timeout error type", rejected(500, "Timed out.", ["error_type": "timeout"])),
            ("500 with a Retry-After wait", rejected(500, "Internal error", headers: ["Retry-After": "15", "x-should-retry": "false"])),
            ("503", rejected(503, "No host.")),
            ("504", rejected(504, "Gateway timed out.")),
            ("524", rejected(524, "Timed out.")),
            ("a body that isn't JSON", failure(.json("<html>Bad gateway</html>", status: 502))),
        ]

        assertInlineSnapshot(of: report(failures), as: .lines) {
            """
            400 context length error type
            LanguageModelError.contextSizeExceeded contextSize: 200000 tokenCount: 0 "Too long." metadata: [errorCode: context_length_exceeded, status: 400]

            400 token limit error type
            OpenRouterError(status: Optional(400), message: "Token budget reached.", code: token_limit_exceeded, providerName: nil, retryAfter: nil)

            400 context in the message
            LanguageModelError.contextSizeExceeded contextSize: 200000 tokenCount: 0 "This model's maximum context length is 200000 tokens." metadata: [errorCode: context_length_exceeded, status: 400]

            400 both sizes in the message
            LanguageModelError.contextSizeExceeded contextSize: 200000 tokenCount: 250000 "This endpoint's maximum context length is 200000 tokens. However, you requested about 250000 tokens." metadata: [errorCode: context_length_exceeded, status: 400]

            400 about a context setting
            OpenRouterError(status: Optional(400), message: "Invalid value for context_management.", code: invalid_request, providerName: nil, retryAfter: nil)

            400 without an error type
            OpenRouterError(status: Optional(400), message: "Bad request.", code: invalid_request, providerName: nil, retryAfter: nil)

            400 rate limit error type
            LanguageModelError.rateLimited resetDate: nil "Slow down." metadata: [errorCode: rate_limit_exceeded, status: 400]

            400 content policy error type
            LanguageModelError.guardrailViolation "Flagged." metadata: [errorCode: content_policy_violation, status: 400]

            400 refusal error type
            LanguageModelError.refusal "I can't help with that." metadata: [errorCode: refusal, status: 400]

            400 unknown error type
            OpenRouterError(status: Optional(400), message: "Image not found", code: image_not_found, providerName: nil, retryAfter: nil)

            401
            OpenRouterError(status: Optional(401), message: "No auth credentials found", code: authentication, providerName: nil, retryAfter: nil)

            402 without a limit
            OpenRouterError(status: Optional(402), message: "No credits.", code: payment_required, providerName: nil, retryAfter: nil)

            402 in-flight budget
            LanguageModelError.rateLimited resetDate: nil "Too many at once." metadata: [errorCode: payment_required, openRouter.limitSource: openrouter_in_flight_budget, status: 402]

            402 refusal wins over the flags
            LanguageModelError.refusal "No." metadata: [errorCode: refusal, openRouter.limitSource: openrouter_in_flight_budget, status: 402]

            403 without a flag
            OpenRouterError(status: Optional(403), message: "Not allowed.", code: permission_denied, providerName: nil, retryAfter: nil)

            403 flagged input
            LanguageModelError.guardrailViolation "Flagged." metadata: [errorCode: permission_denied, status: 403]

            403 content filter without a report
            OpenRouterError(status: Optional(403), message: "Request blocked by content filter: [BLOCKED]", code: permission_denied, providerName: nil, retryAfter: nil)

            403 guardrail blocked
            LanguageModelError.guardrailViolation "Request blocked by content filter: [BLOCKED]" metadata: [errorCode: permission_denied, status: 403]

            403 guardrail redacted
            OpenRouterError(status: Optional(403), message: "Request blocked by content filter: [BLOCKED]", code: permission_denied, providerName: nil, retryAfter: nil)

            403 budget that resets
            LanguageModelError.rateLimited resetDate: 2026-11-03T00:00:00Z "Budget spent." metadata: [errorCode: budget_exceeded, openRouter.limitSource: api_key, status: 403]

            403 lifetime budget
            OpenRouterError(status: Optional(403), message: "Budget spent.", code: budget_exceeded, providerName: nil, retryAfter: nil)

            403 reasons win over another error type
            LanguageModelError.guardrailViolation "Flagged." metadata: [errorCode: permission_denied, status: 403]

            404
            OpenRouterError(status: Optional(404), message: "Failed", code: not_found, providerName: nil, retryAfter: nil)

            408
            LanguageModelError.timeout "Timed out." metadata: [errorCode: timeout, status: 408]

            413
            OpenRouterError(status: Optional(413), message: "Failed", code: payload_too_large, providerName: nil, retryAfter: nil)

            422
            OpenRouterError(status: Optional(422), message: "Failed", code: unprocessable, providerName: nil, retryAfter: nil)

            429
            LanguageModelError.rateLimited resetDate: nil "Slow down." metadata: [errorCode: rate_limit_exceeded, status: 429]

            500
            OpenRouterError(status: Optional(500), message: "Failed.", code: server, providerName: nil, retryAfter: nil)

            500 timeout error type
            LanguageModelError.timeout "Timed out." metadata: [errorCode: timeout, status: 500]

            500 with a Retry-After wait
            OpenRouterError(status: Optional(500), message: "Internal error", code: server, providerName: nil, retryAfter: Optional(15.0 seconds))

            503
            OpenRouterError(status: Optional(503), message: "No host.", code: provider_unavailable, providerName: nil, retryAfter: nil)

            504
            LanguageModelError.timeout "Gateway timed out." metadata: [errorCode: timeout, status: 504]

            524
            LanguageModelError.timeout "Timed out." metadata: [errorCode: timeout, status: 524]

            a body that isn't JSON
            OpenRouterError(status: Optional(502), message: "bad gateway", code: provider_unavailable, providerName: nil, retryAfter: nil)
            """
        }
    }

    @Test func `every failure in a stream ends in the error it maps to`() async {
        let contextMessage = "This endpoint's maximum context length is 200000 tokens. However, you requested about 250000 tokens."
        let failures = await [
            (
                "context size error",
                failure(
                    events(
                        text("Hi"),
                        ["error": ["code": 400, "message": .string(contextMessage), "metadata": ["error_type": "context_length_exceeded"]]])
                )
            ),
            (
                "text code with the chunk's host",
                failure(events(text("Hi"), ["error": ["code": "server_error", "message": "Failed."], "provider": "openai"]))
            ),
            (
                "the metadata's host before the chunk's",
                failure(
                    events(
                        text("Hi"),
                        [
                            "error": ["code": 502, "message": "Provider returned error", "metadata": ["provider_name": "Anthropic"]],
                            "provider": "openai",
                        ]
                    ))
            ),
            ("no code", failure(events(text("Hi"), ["error": ["message": "Generation failed."]]))),
            (
                "rate limit",
                failure(
                    events(
                        text("Hi"),
                        [
                            "error": ["code": 429, "message": "Rate limit exceeded", "metadata": ["error_type": "rate_limit_exceeded"]],
                            "provider": "openai",
                        ]
                    ))
            ),
            ("refusal", failure(events(chunk(["refusal": "I can't help with that."]), done()))),
            ("content filter", failure(events(text("Partial"), done("content_filter")))),
            ("answer that ends in an error", failure(events(text("Hel"), done("error")))),
            ("event that isn't a chunk", failure(.eventStream(Data("data: {not json\n\n".utf8)))),
            ("cut off", failure(unfinishedEvents(text("Hel")))),
            ("connection lost", failure(unfinishedEvents(text("Hel")).droppingConnection(with: URLError(.networkConnectionLost)))),
            ("connection timed out", failure(unfinishedEvents(text("Hel")).droppingConnection(with: URLError(.timedOut)))),
            (
                "call whose arguments stop partway",
                toolFailure(events(toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"eg"#), done("tool_calls")))
            ),
            (
                "call that never gets a name",
                toolFailure(events(toolCall(0, id: "call_1", arguments: #"{"food":"egg"}"#), done("tool_calls")))
            ),
            (
                "call cut off at the token limit",
                toolFailure(events(toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"#), done("length")))
            ),
        ]

        assertInlineSnapshot(of: report(failures), as: .lines) {
            #"""
            context size error
            LanguageModelError.contextSizeExceeded contextSize: 200000 tokenCount: 250000 "This endpoint's maximum context length is 200000 tokens. However, you requested about 250000 tokens." metadata: [errorCode: context_length_exceeded, provider: Vendor, status: 400]

            text code with the chunk's host
            OpenRouterError(status: nil, message: "Failed.", code: server_error, providerName: Optional(openai), retryAfter: nil)

            the metadata's host before the chunk's
            OpenRouterError(status: Optional(502), message: "Provider returned error", code: provider_unavailable, providerName: Optional(Anthropic), retryAfter: nil)

            no code
            OpenRouterError(status: nil, message: "Generation failed.", code: server, providerName: Optional(Vendor), retryAfter: nil)

            rate limit
            LanguageModelError.rateLimited resetDate: nil "Rate limit exceeded" metadata: [errorCode: rate_limit_exceeded, provider: openai, status: 429]

            refusal
            LanguageModelError.refusal "I can't help with that." metadata: [provider: Vendor]

            content filter
            LanguageModelError.guardrailViolation "A content filter stopped the response." metadata: [provider: Vendor]

            answer that ends in an error
            OpenRouterError(status: nil, message: "The model\'s response ended in an error.", code: server, providerName: Optional(Vendor), retryAfter: nil)

            event that isn't a chunk
            OpenRouterError(status: nil, message: "OpenRouter sent an event that couldn\'t be read: <decoding error>", code: invalid_response, providerName: nil, retryAfter: nil)

            cut off
            OpenRouterError(status: nil, message: "The response ended before it was complete.", code: invalid_response, providerName: Optional(Vendor), retryAfter: nil)

            connection lost
            URLError -1005

            connection timed out
            LanguageModelError.timeout "<the system's text>" metadata: []

            call whose arguments stop partway
            OpenRouterError(status: nil, message: "The model sent arguments for lookUpFood that aren\'t a whole JSON object.", code: invalid_response, providerName: Optional(Vendor), retryAfter: nil)

            call that never gets a name
            OpenRouterError(status: nil, message: "The model sent a tool call without its name.", code: invalid_response, providerName: Optional(Vendor), retryAfter: nil)

            call cut off at the token limit
            OpenRouterError(status: nil, message: "The answer reached its token limit inside a tool call.", code: invalid_response, providerName: Optional(Vendor), retryAfter: nil)
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

    @Test func `every request refused before it goes out ends in its error`() async throws {
        let image = try #require(TestImage.halves(width: 8, height: 8))
        let imagePrompt = Transcript.Entry.prompt(
            Transcript.Prompt(segments: [.attachment(.init(content: .image(Transcript.ImageAttachment(image))))]))
        let answer = Transcript.Entry.response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Kept."))]))
        let failures = await [
            (
                "a reasoning level for a model that doesn't reason",
                outcome { stub in
                    let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, reasoning: .unsupported)
                    _ = try await LanguageModelSession(model: model).respond(
                        to: "Hi", contextOptions: ContextOptions(reasoningLevel: .moderate))
                }
            ),
            (
                "a schema for a model without structured outputs",
                outcome { stub in
                    _ = try await LanguageModelSession(model: model(stub, parameters: [.maxTokens])).respond(
                        to: "Hi", generating: FoodTool.Arguments.self)
                }
            ),
            (
                "an image for a model without vision",
                outcome { stub in
                    let transcript = Transcript(entries: [imagePrompt, answer])
                    _ = try await LanguageModelSession(model: model(stub), transcript: transcript).respond(to: "Which colors?")
                }
            ),
        ]

        assertInlineSnapshot(of: report(failures), as: .lines) {
            """
            a reasoning level for a model that doesn't reason
            LanguageModelError.unsupportedCapability capability: reasoning "<the system's text>" metadata: []

            a schema for a model without structured outputs
            LanguageModelError.unsupportedCapability capability: guidedGeneration "<the system's text>" metadata: []

            an image for a model without vision
            LanguageModelError.unsupportedCapability capability: vision "<the system's text>" metadata: []
            """
        }
    }

    /// The error of a failed response with OpenRouter's error body.
    private func rejected(_ status: Int, _ message: String, _ metadata: JSONValue? = nil, headers: [String: String] = [:]) async -> String {
        var error: [JSONObject.Member] = [.init(key: "code", value: .integer(status)), .init(key: "message", value: .string(message))]
        if let metadata {
            error.append(.init(key: "metadata", value: metadata))
        }
        let body = JSONValue.object(["error": .object(JSONObject(error))]).text
        return await failure(.json(body, status: status, headers: headers))
    }

    /// The error of a response that's answered the same way on every retry.
    private func failure(_ response: StubResponse) async -> String {
        await outcome(HTTPStub(response, response, response)) { try await respond($0) }
    }

    /// The error of a session with a tool, whose first answer is `response`.
    private func toolFailure(_ response: StubResponse) async -> String {
        await outcome(HTTPStub(response)) { stub in
            _ = try await LanguageModelSession(model: model(stub), tools: [FoodTool()]).respond(to: "Calories in an egg?")
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
