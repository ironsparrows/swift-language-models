import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension OpenAICompatibleErrorTests {
    /// The shapes providers send their errors in, each read into the module's error: providers' own answers, ids
    /// swapped, where one was captured, and bodies written from providers' docs, source and issues otherwise.
    @Suite("Bodies")
    struct Bodies {
        /// A failed response and the error it becomes.
        struct Row: Sendable, CustomTestStringConvertible {
            let name: String
            let status: Int
            var headers = ["Content-Type": "application/json"]
            let body: String
            let error: OpenAICompatibleError

            var testDescription: String { name }
        }

        static let rows: [Row] = [
            Row(
                name: "Gemini, a JSON array", status: 404,
                body: #"""
                    [{
                      "error": {
                        "code": 404,
                        "message": "models/no-such-model-xyz is not found for API version v1main, or is not supported for generateContent. Call ModelService.ListModels to see the list of available models and their supported methods.",
                        "status": "NOT_FOUND"
                      }
                    }
                    ]
                    """#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 404,
                    message:
                        "models/no-such-model-xyz is not found for API version v1main, or is not supported for generateContent. Call ModelService.ListModels to see the list of available models and their supported methods.",
                    code: .notFound, errorType: "NOT_FOUND")),
            Row(
                name: "Gemini, a missing key", status: 400,
                body: #"[{"error":{"code":400,"message":"Missing or invalid Authorization header.","status":"INVALID_ARGUMENT"}}]"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 400, message: "Missing or invalid Authorization header.", code: "INVALID_ARGUMENT",
                    errorType: "INVALID_ARGUMENT")),
            Row(
                name: "Groq, nested, with a request id", status: 401,
                headers: ["Content-Type": "application/json", "x-request-id": "req_01test00000000000000000002"],
                body: #"{"error":{"message":"Invalid API Key","type":"invalid_request_error","code":"invalid_api_key"}}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 401, message: "Invalid API Key", code: .invalidAPIKey, errorType: .invalidRequest,
                    requestID: "req_01test00000000000000000002")),
            Row(
                name: "Groq, a member it doesn't know", status: 400,
                body: #"{"error":{"message":"property 'top_k' is unsupported","type":"invalid_request_error"}}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 400, message: "property 'top_k' is unsupported", code: .invalidRequest,
                    errorType: .invalidRequest)),
            Row(
                name: "Ollama, nested with null members", status: 404,
                body: #"{"error":{"message":"model 'no-such-model-xyz' not found","type":"not_found_error","param":null,"code":null}}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 404, message: "model 'no-such-model-xyz' not found", code: .notFound,
                    errorType: "not_found_error")),
            Row(
                name: "xAI, flat with the message as the error", status: 400,
                body:
                    #"{"code":"invalid-argument","error":"Incorrect API key provided. You can obtain an API key from https://console.x.ai."}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 400,
                    message: "Incorrect API key provided. You can obtain an API key from https://console.x.ai.", code: "invalid-argument")),
            Row(
                name: "Mistral, flat with the member it concerns", status: 400,
                body:
                    #"{"object":"error","message":"Invalid model: no-such-model","type":"invalid_request_error","param":"model","code":"unknown_model"}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 400, message: "Invalid model: no-such-model", code: "unknown_model",
                    errorType: .invalidRequest, parameter: "model")),
            Row(
                name: "Mistral, a validation's detail", status: 422,
                body:
                    #"{"detail":[{"type":"extra_forbidden","loc":["body","stream_options"],"msg":"Extra inputs are not permitted","input":{"include_usage":true}}]}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 422, message: "Extra inputs are not permitted", code: .unprocessable,
                    errorType: "extra_forbidden", parameter: "stream_options")),
            Row(
                name: "Mistral, a validation's detail as the message", status: 422,
                body:
                    #"{"object":"error","message":{"detail":[{"type":"extra_forbidden","loc":["body","messages",1,"reasoning_content"],"msg":"Extra inputs are not permitted"}]},"type":"invalid_request_message_error","param":null,"code":null}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 422, message: "Extra inputs are not permitted", code: .unprocessable,
                    errorType: "invalid_request_message_error", parameter: "messages.1.reasoning_content")),
            Row(
                name: "LM Studio, the error as text", status: 400,
                body: #"{"error":"'response_format.type' must be 'json_schema' or 'text'"}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 400, message: "'response_format.type' must be 'json_schema' or 'text'")),
            Row(
                name: "vLLM, the status as an integer code", status: 404,
                body:
                    #"{"error":{"message":"The model `no-such-model` does not exist.","type":"NotFoundError","param":"model","code":404}}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 404, message: "The model `no-such-model` does not exist.", code: .notFound,
                    errorType: "NotFoundError", parameter: "model")),
            Row(
                name: "an empty HTML body, as Gemini's Responses path sends it", status: 404, headers: ["Content-Type": "text/html"],
                body: "",
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 404, message: "HTTP 404, empty text/html body", code: .notFound)),
            Row(
                name: "a gateway's HTML page", status: 403, headers: ["Content-Type": "text/html; charset=utf-8"],
                body: "<html><body>Forbidden</body></html>",
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 403, message: "HTTP 403, text/html body of 35 bytes", code: .permissionDenied)),
            Row(
                name: "plain text", status: 400, headers: ["Content-Type": "text/plain"], body: "model is required\n",
                error: OpenAICompatibleError(providerName: "Gateway", status: 400, message: "model is required")),
            Row(
                name: "an error that names its kind without a message", status: 400,
                body: #"{"error":{"message":"","type":"server_error","code":"boom"}}"#,
                error: OpenAICompatibleError(
                    providerName: "Gateway", status: 400, message: #"{"code":"boom","message":"","type":"server_error"}"#,
                    code: "boom", errorType: .serverError)),
            Row(
                name: "a status of error, which names no kind", status: 400, body: #"{"status":"error","message":"The request failed."}"#,
                error: OpenAICompatibleError(providerName: "Gateway", status: 400, message: "The request failed.")),
            Row(
                name: "JSON with no member that holds a message", status: 400, body: #"{"status":"failed","retry":false}"#,
                error: OpenAICompatibleError(providerName: "Gateway", status: 400, message: #"{"status":"failed","retry":false}"#)),
        ]

        @Test(arguments: rows)
        func `a failed response's body becomes the module's error, whatever its shape`(row: Row) async {
            let stub = HTTPStub(.json(row.body, status: row.status, headers: row.headers))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub)).respond(to: "Hi")
            }

            #expect(error == row.error)
        }

        @Test func `a long body that holds no error is cut at 1,000 characters`() async {
            let text = String(repeating: "abcdefghij", count: 150)
            let stub = HTTPStub(.json(text, status: 400, headers: ["Content-Type": "text/plain"]))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub)).respond(to: "Hi")
            }

            #expect(error?.message == String(text.prefix(1_000)))
        }
    }
}
