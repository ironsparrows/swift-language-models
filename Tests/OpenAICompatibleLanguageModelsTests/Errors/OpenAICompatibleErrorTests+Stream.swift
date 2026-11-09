import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension OpenAICompatibleErrorTests {
    /// Failures in a stream, which arrive after the response's HTTP 200: the status an error names, the provider's words
    /// in their shapes, and streams the format couldn't use.
    @Suite("Stream")
    struct Stream {
        @Test func `Groq's error event after streamed reasoning names its status in status_code, with the request id`() async {
            // Groq's event for a guided answer that missed its schema, as captured.
            let stream = """
                data: {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"openai/gpt-oss-20b","choices":[{"index":0,"delta":{"reasoning":"4","channel":"analysis"},"logprobs":null,"finish_reason":null}]}

                event: error
                data: {"error":{"message":"Failed to validate JSON. Please adjust your prompt. See 'failed_generation' for more details.","type":"invalid_request_error","code":"json_validate_failed","failed_generation":"","status_code":400}}


                """
            let response = StubResponse.eventStream(Data(stream.utf8))
            let stub = HTTPStub(
                StubResponse(status: 200, headers: response.headers.merging(["x-request-id": "req_1"]) { $1 }, chunks: response.chunks))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub)).respond(to: "Rate it.")
            }

            #expect(
                error
                    == OpenAICompatibleError(
                        providerName: "Gateway", status: 400,
                        message: "Failed to validate JSON. Please adjust your prompt. See 'failed_generation' for more details.",
                        code: "json_validate_failed", errorType: .invalidRequest, requestID: "req_1"))
        }

        @Test(
            arguments: [
                (
                    #"{"error":{"message":"The engine failed while it generated.","type":"InternalServerError","param":null,"code":500}}"#,
                    OpenAICompatibleError(
                        providerName: "Gateway", status: 500, message: "The engine failed while it generated.", code: .server,
                        errorType: "InternalServerError")
                ),
                (
                    #"{"error":"model runner has unexpectedly stopped"}"#,
                    OpenAICompatibleError(providerName: "Gateway", message: "model runner has unexpectedly stopped", code: .server)
                ),
                (
                    #"{"type":"error","message":"The server is overloaded.","code":"overloaded"}"#,
                    OpenAICompatibleError(providerName: "Gateway", message: "The server is overloaded.", code: "overloaded")
                ),
                (
                    #"{"error":{"code":503,"status":"UNAVAILABLE"}}"#,
                    OpenAICompatibleError(
                        providerName: "Gateway", status: 503, message: #"{"code":503,"status":"UNAVAILABLE"}"#, code: .server,
                        errorType: "UNAVAILABLE")
                ),
            ] as [(String, OpenAICompatibleError)])
        func `an error chunk becomes the module's error, with the status a number in it names`(
            chunk: String, expected: OpenAICompatibleError
        ) async {
            let stub = HTTPStub(.eventStream(Data("data: \(chunk)\n\ndata: [DONE]\n\n".utf8)))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub)).respond(to: "Hi")
            }

            #expect(error == expected)
        }

        @Test func `an oversized prompt that a stream reports with a status of 400 throws Foundation Models' error`() async throws {
            let chunk =
                #"{"error":{"message":"This model's maximum context length is 4096 tokens. However, you requested 5000 tokens.","type":"BadRequestError","param":null,"code":400}}"#
            let stub = HTTPStub(.eventStream(Data("data: \(chunk)\n\ndata: [DONE]\n\n".utf8)))

            let error = await #expect(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model(stub)).respond(to: "Hi")
            }

            guard case .contextSizeExceeded(let context)? = error else {
                Issue.record("The answer ended with \(String(describing: error))")
                return
            }
            #expect(context.contextSize == 4_096)
            #expect(error?.openAICompatible.status == 400)
            #expect(error?.openAICompatible.providerName == "Gateway")
        }

        @Test func `a Responses error event becomes the module's error, or Foundation Models' for a rate limit`() async throws {
            let nested = HTTPStub(
                events([
                    "type": "error",
                    "error": [
                        "type": "invalid_request_error", "code": "invalid_value", "message": "Bad effort.", "param": "reasoning.effort",
                    ],
                ]))
            let flat = HTTPStub(events(["type": "error", "code": "rate_limit_exceeded", "message": "Slow down."]))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(nested, format: .responses)).respond(to: "Hi")
            }
            let limited = await #expect(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model(flat, format: .responses)).respond(to: "Hi")
            }

            #expect(
                error
                    == OpenAICompatibleError(
                        providerName: "Gateway", message: "Bad effort.", code: "invalid_value", errorType: .invalidRequest,
                        parameter: "reasoning.effort"))
            guard case .rateLimited? = limited else {
                Issue.record("The answer ended with \(String(describing: limited))")
                return
            }
            #expect(limited?.openAICompatible.code == "rate_limit_exceeded")
        }

        @Test func `a Responses answer that failed becomes the module's error, with or without the provider's message`() async {
            let failed = HTTPStub(
                events(lifecycle("response.failed", ["id": "resp_1", "error": ["code": "server_error", "message": "The model failed."]])))
            let wordless = HTTPStub(events(lifecycle("response.failed", ["id": "resp_1", "error": ["code": "server_error"]])))
            let unexplained = HTTPStub(events(lifecycle("response.failed", ["id": "resp_1"])))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(failed, format: .responses)).respond(to: "Hi")
            }
            let codeOnly = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(wordless, format: .responses)).respond(to: "Hi")
            }
            let bare = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(unexplained, format: .responses)).respond(to: "Hi")
            }

            #expect(error == OpenAICompatibleError(providerName: "Gateway", message: "The model failed.", code: .serverError))
            #expect(codeOnly == OpenAICompatibleError(providerName: "Gateway", message: #"{"code":"server_error"}"#, code: .serverError))
            #expect(
                bare == OpenAICompatibleError(providerName: "Gateway", message: "The model's response ended in an error.", code: .server))
        }

        @Test func `a stream the format can't use throws an invalid response that names the provider`() async {
            let cutOff = HTTPStub(
                .eventStream(Data(#"data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":"Part"}}]}\#n\#n"#.utf8)))
            let unreadable = HTTPStub(.eventStream(Data("data: {\"choices\": 7}\n\n".utf8)))

            let cutOffError = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(cutOff)).respond(to: "Hi")
            }
            let unreadableError = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(unreadable)).respond(to: "Hi")
            }

            #expect(cutOffError?.code == .invalidResponse)
            #expect(cutOffError?.providerName == "Gateway")
            #expect(unreadableError?.code == .invalidResponse)
            #expect(unreadableError?.providerName == "Gateway")
        }
    }
}
