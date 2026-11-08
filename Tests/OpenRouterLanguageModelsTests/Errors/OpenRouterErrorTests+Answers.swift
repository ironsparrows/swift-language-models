import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterErrorTests {
    @Suite("Answers")
    struct Answers {
        @Test func `a rate limit throws rateLimited with the reset date from Retry-After`() async throws {
            let stub = HTTPStub(
                .json(#"{"error":{"code":429,"message":"Rate limit exceeded"}}"#, status: 429, headers: ["Retry-After": "30"]))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            let wait = try #require(info.resetDate).timeIntervalSinceNow
            #expect((25...31).contains(wait))
        }

        @Test func `a Retry-After date sets the rate limit's reset date`() async throws {
            let resetDate = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 120).rounded(.down))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .gmt
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            let header = formatter.string(from: resetDate)
            let stub = HTTPStub(
                .json(#"{"error":{"code":429,"message":"Rate limit exceeded"}}"#, status: 429, headers: ["Retry-After": header]))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            #expect(abs(try #require(info.resetDate).timeIntervalSince(resetDate)) < 2)
        }

        @Test func `without Retry-After, a rate limit takes its reset date from X-RateLimit-Reset`() async throws {
            let resetDate = Date.now.addingTimeInterval(60)
            let milliseconds = String(Int(resetDate.timeIntervalSince1970 * 1_000))
            let stub = HTTPStub(
                .json(#"{"error":{"code":429,"message":"Rate limit exceeded"}}"#, status: 429, headers: ["X-RateLimit-Reset": milliseconds])
            )

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            #expect(abs(try #require(info.resetDate).timeIntervalSince(resetDate)) < 2)
        }

        @Test func `an OpenRouter error carries the Retry-After wait`() async throws {
            // `x-should-retry: false` fails it at once, rather than after waiting 15 seconds for each retry.
            let headers = ["Retry-After": "15", "x-should-retry": "false"]
            let stub = HTTPStub(.json(#"{"error":{"code":500,"message":"Internal error"}}"#, status: 500, headers: headers))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.retryAfter == .seconds(15))
        }

        @Test func `a rejected key throws an OpenRouter error with the status and message`() async throws {
            let stub = HTTPStub(.json(#"{"error":{"code":401,"message":"No auth credentials found"}}"#, status: 401))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error == OpenRouterError(status: 401, message: "No auth credentials found", code: .authentication))
        }

        @Test(arguments: [
            (400, OpenRouterError.Code.invalidRequest),
            (401, .authentication),
            (402, .paymentRequired),
            (403, .permissionDenied),
            (404, .notFound),
            (413, .payloadTooLarge),
            (422, .unprocessable),
            (500, .server),
        ])
        func `an error without an error type takes its code from the status`(status: Int, code: OpenRouterError.Code) async throws {
            // A 500 is retried twice, so it fails three times.
            let failure = StubResponse.json(#"{"error":{"code":\#(status),"message":"Failed"}}"#, status: status)
            let stub = HTTPStub(failure, failure, failure)

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.code == code)
            #expect(error.status == status)
        }

        @Test func `an error type wins over the status`() async throws {
            let body = #"{"error":{"code":400,"message":"Image not found","metadata":{"error_type":"image_not_found"}}}"#
            let stub = HTTPStub(.json(body, status: 400))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.code == .imageNotFound)
        }

        @Test func `a 400 for a prompt longer than the context throws contextSizeExceeded with both sizes and its status`() async throws {
            let message =
                "This endpoint's maximum context length is 8192 tokens. However, you requested about 9000 tokens "
                + "(8000 of text input, 1000 in the output). Please reduce the length of either one."
            let stub = HTTPStub(.json(JSONValue.object(["error": ["code": 400, "message": .string(message)]]).text, status: 400))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .contextSizeExceeded(let info) = error else {
                Issue.record("Expected an oversized context, got \(error)")
                return
            }
            #expect(info.contextSize == 8_192)
            #expect(info.tokenCount == 9_000)
            #expect(info.metadata["status"] as? Int == 400)
        }

        @Test func `a 400 in the stream that mentions the context throws contextSizeExceeded with the model's context size`() async throws {
            let streamError: JSONValue = ["error": ["code": 400, "message": "Input exceeds the context window."]]
            let stub = HTTPStub(events(text("Hi"), streamError))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .contextSizeExceeded(let info) = error else {
                Issue.record("Expected an oversized context, got \(error)")
                return
            }
            #expect(info.contextSize == 200_000)
        }

        @Test func `a 400 about a context setting stays an invalid request`() async throws {
            let stub = HTTPStub(.json(#"{"error":{"code":400,"message":"Invalid value for context_management."}}"#, status: 400))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.code == .invalidRequest)
        }

        @Test func `an OpenRouter error carries its code and host`() async throws {
            let body =
                #"{"error":{"code":402,"message":"Insufficient credits","metadata":{"error_type":"payment_required","provider_name":"Anthropic"}}}"#
            let stub = HTTPStub(.json(body, status: 402))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.code == .paymentRequired)
            #expect(error.provider == "Anthropic")
            #expect(error.status == 402)
        }

        @Test func `a host's own message replaces OpenRouter's generic one`() async throws {
            let body =
                #"{"error":{"code":400,"message":"Provider returned error","metadata":{"provider_name":"Anthropic","raw":"{\"error\":{\"message\":\"messages: text content blocks must be non-empty\"}}"}}}"#
            let stub = HTTPStub(.json(body, status: 400))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.message == "messages: text content blocks must be non-empty")
            #expect(error.errorDescription == "[Anthropic] messages: text content blocks must be non-empty")
        }

        @Test func `an error in the stream throws the matching error`() async throws {
            let message = "This endpoint's maximum context length is 200000 tokens. However, you requested about 250000 tokens."
            let streamError: JSONValue = [
                "error": ["code": 400, "message": .string(message), "metadata": ["error_type": "context_length_exceeded"]]
            ]
            let stub = HTTPStub(events(text("Hi"), streamError))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .contextSizeExceeded(let info) = error else {
                Issue.record("Expected an oversized context, got \(error)")
                return
            }
            #expect(info.contextSize == 200_000)
            #expect(info.tokenCount == 250_000)
        }

        @Test func `an error in the stream with a text code throws that code and the chunk's host, without a status`() async throws {
            let message = "The server had an error while processing your request."
            let streamError: JSONValue = ["error": ["code": "server_error", "message": .string(message)], "provider": "openai"]
            let stub = HTTPStub(events(text("Hi"), streamError))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error == OpenRouterError(message: message, code: "server_error", provider: "openai"))
        }

        @Test func `an error in the stream takes the host its metadata names before the chunk's`() async throws {
            let streamError: JSONValue = [
                "error": ["code": 502, "message": "Provider returned error", "metadata": ["provider_name": "Anthropic"]],
                "provider": "openai",
            ]
            let stub = HTTPStub(events(text("Hi"), streamError))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.status == 502)
            #expect(error.code == .providerUnavailable)
            #expect(error.provider == "Anthropic")
        }

        @Test func `an error in the stream without a code is a server failure of the host an earlier chunk named`() async throws {
            let stub = HTTPStub(events(text("Hi"), ["error": ["message": "Generation failed."]]))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error == OpenRouterError(message: "Generation failed.", code: .server, provider: "Vendor"))
        }

        @Test func `a rate limit in the stream keeps its status, its code and the chunk's host in its metadata`() async throws {
            let streamError: JSONValue = [
                "error": ["code": 429, "message": "Rate limit exceeded", "metadata": ["error_type": "rate_limit_exceeded"]],
                "provider": "openai",
            ]
            let stub = HTTPStub(events(text("Hi"), streamError))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            #expect(info.metadata["provider"] as? String == "openai")
            #expect(info.metadata["status"] as? Int == 429)
            #expect(info.metadata["errorCode"] as? String == "rate_limit_exceeded")
            #expect(error.providerMetadata.host == "openai")
            #expect(error.providerMetadata.status == 429)
            #expect(error.openRouter.provider == "openai")
            #expect(error.openRouter.code == "rate_limit_exceeded")
            #expect(error.openRouter.limitSource == nil)
        }

        @Test func `a refusal throws refusal with the model's explanation`() async throws {
            let stub = HTTPStub(events(chunk(["refusal": "I can't help with that."]), done()))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .refusal(let info) = error else {
                Issue.record("Expected a refusal, got \(error)")
                return
            }
            #expect(info.metadata["provider"] as? String == "Vendor")
        }

        @Test func `a content filter throws a guardrail violation`() async throws {
            let stub = HTTPStub(events(text("Partial"), done("content_filter")))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .guardrailViolation(let info) = error else {
                Issue.record("Expected a guardrail violation, got \(error)")
                return
            }
            #expect(info.metadata["provider"] as? String == "Vendor")
        }

        @Test(
            .bug("https://github.com/ironsparrows/swift-language-models/pull/47"),
            arguments: [
                #"{"type":"guardrail","name":"content-filter","summary":"PII blocked via custom","data":{"flagged":true,"action":"blocked","filter_mode":"regex","engines":["custom"],"matched_entity_types":[]}}"#,
                #"{"type":"guardrail","name":"regex_pi_detection","guardrail_id":"grd_1","data":{"action":"blocked","detected":true}}"#,
            ])
        func `a guardrail's block throws a guardrail violation`(stage: String) async throws {
            let stub = HTTPStub(.json(Self.forbidden(pipeline: stage), status: 403))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .guardrailViolation(let info) = error else {
                Issue.record("Expected a guardrail violation, got \(error)")
                return
            }
            #expect(info.metadata["status"] as? Int == 403)
        }

        @Test(
            .bug("https://github.com/ironsparrows/swift-language-models/pull/47"),
            arguments: [
                #"{"type":"guardrail","name":"content-filter","data":{"flagged":true,"action":"redacted"}}"#,
                #"{"type":"guardrail","name":"content-filter"}"#,
                #"{"type":"a_future_stage","name":"new-plugin","data":{"action":"blocked"}}"#,
            ])
        func `a 403 with no guardrail stage that blocked stays OpenRouter's`(stage: String) async throws {
            let stub = HTTPStub(.json(Self.forbidden(pipeline: stage), status: 403))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.code == .permissionDenied)
        }

        /// A 403 with the router's report beside its error, as OpenRouter sends it.
        private static func forbidden(pipeline stage: String) -> String {
            #"{"error":{"message":"Request blocked by content filter: [BLOCKED]","code":403,"metadata":{"provider_name":null}},"user_id":"org_1","openrouter_metadata":{"requested":"vendor/model","strategy":"direct","attempt":0,"pipeline":[\#(stage)]}}"#
        }

        @Test func `an answer that ends in an error throws OpenRouter's server error, naming the host`() async throws {
            let stub = HTTPStub(events(text("Hel"), done("error")))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.code == .server)
            #expect(error.provider == "Vendor")
        }

        @Test(arguments: [408, 504, 524])
        func `a timeout status throws timeout`(status: Int) async throws {
            // A 504 or a 524 is retried twice, so it fails three times.
            let timeout = StubResponse.json(#"{"error":{"code":\#(status),"message":"Request timed out"}}"#, status: status)
            let stub = HTTPStub(timeout, timeout, timeout)

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .timeout = error else {
                Issue.record("Expected a timeout, got \(error)")
                return
            }
        }
    }
}
