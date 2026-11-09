import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    @Suite("Groq")
    struct Groq {
        @Test func `Groq's models reason when asked, take its efforts, and wait up to 60 seconds for the next data`() throws {
            let details = OpenAICompatibleModel("qwen/qwen3.8-27b", on: .groq)

            #expect(OpenAICompatibleProvider.groq.name == "Groq")
            #expect(OpenAICompatibleProvider.groq.url == URL(string: "https://api.groq.com/openai/v1"))
            #expect(OpenAICompatibleProvider.groq.keyHeader == .bearer)
            #expect(details.reasoning == .offByDefault)
            #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["high", "medium", "low", "none"])
            #expect(details.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
            #expect(
                OpenAICompatibleLanguageModel(details, auth: .unauthenticated).configuration
                    == OpenAICompatibleConfiguration(idleTimeout: .seconds(60)))
        }

        @Test func `a request sends the token limit as max_completion_tokens, leaves out metadata, and asks for no usage`()
            async throws
        {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: .groq.at(stub.baseURL))).respond(
                to: "Hi", options: GenerationOptions(samplingMode: .random(top: 40, seed: 7), maximumResponseTokens: 50),
                contextOptions: ContextOptions(reasoningLevel: .light), metadata: ["team": "meals"])

            assertInlineSnapshot(of: stub.requests[0].body, as: .memberLines) {
                """
                {
                  "model": "test-model",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Hi"
                    }
                  ],
                  "stream": true,
                  "reasoning_effort": "low",
                  "seed": 7,
                  "max_completion_tokens": 50
                }
                """
            }
        }

        // The recorded tool round shows a model's reasoning going back to the model that wrote it.
        @Test func `a model's reasoning doesn't go back to another model`() async throws {
            let stub = HTTPStub(.eventStream(try Bundle.module.fixture("Recorded/groq-text.1.sse")))
            let other = HTTPStub(chunks(text("Grey."), finish()))
            let gptOSS = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("openai/gpt-oss-20b", on: .groq.at(stub.baseURL)), session: stub.session,
                configuration: .stubbed, auth: .apiKey { "gsk-test" })
            let qwen = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("qwen/qwen3.8-27b", on: .groq.at(other.baseURL)), session: other.session,
                configuration: .stubbed, auth: .apiKey { "gsk-test" })
            let session = LanguageModelSession(model: gptOSS)

            _ = try await session.respond(to: "Name one color of the sea.")
            _ = try await LanguageModelSession(model: qwen, transcript: session.transcript).respond(to: "And one of the sky?")

            #expect(try body(other)["messages"]?[1] == ["role": "assistant", "content": "Blue."])
        }

        @Test(arguments: [(OpenAICompatibleProvider.groq, true), (.gemini, false)])
        func `a schema with tools is refused before it's sent to Groq, which refuses the two, and sent to Gemini`(
            provider: OpenAICompatibleProvider, refused: Bool
        ) async throws {
            let stub = HTTPStub(chunks(text(#"{"stars":4}"#), finish()))
            let session = LanguageModelSession(model: model(stub, on: provider.at(stub.baseURL)), tools: [WeatherTool()])

            do {
                _ = try await session.respond(to: "Rate the film.", generating: Rating.self)
                #expect(!refused)
                #expect(try body(stub)["response_format"] != nil)
                #expect(try body(stub)["tools"] != nil)
            } catch let error as LanguageModelError {
                guard case .unsupportedCapability(let context) = error else {
                    Issue.record("Expected an unsupported capability, got \(error)")
                    return
                }
                #expect(refused)
                #expect(context.capability == .guidedGeneration)
                #expect(stub.requests.isEmpty)
            }
        }

        @Test func `a guided answer Groq says broke its schema throws a parsing error with what the model generated`() async throws {
            // Groq's event for a guided answer that missed its schema, as captured on Qwen: ids swapped.
            let stream = #"""
                data: {"id":"chatcmpl-00000000-0000-4000-8000-000000000002","object":"chat.completion.chunk","created":1794203355,"model":"qwen/qwen3.8-27b","system_fingerprint":"fp_43dd1ea4ee","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}],"x_groq":{"id":"req_01test00000000000000000002","seed":1}}

                event: error
                data: {"error":{"message":"Failed to generate JSON. Please adjust your prompt. See 'failed_generation' for more details.","type":"invalid_request_error","code":"json_validate_failed","failed_generation":"\#u{FFFD}urbed","status_code":400}}


                """#
            let stub = HTTPStub(.eventStream(Data(stream.utf8)))

            let error = await #expect(throws: GeneratedContent.ParsingError.self) {
                try await LanguageModelSession(model: model(stub, on: .groq.at(stub.baseURL))).respond(
                    to: "Rate the film.", generating: Rating.self)
            }

            #expect(error?.rawContent == "\u{FFFD}urbed")
        }

        @Test func `a required call the model didn't make throws the module's error with Groq's code`() async throws {
            // Groq's event after a text answer to a request that required a call, as captured on gpt-oss: ids swapped.
            let stream = #"""
                data: {"id":"chatcmpl-00000000-0000-4000-8000-000000000003","object":"chat.completion.chunk","created":1794205505,"model":"openai/gpt-oss-20b","system_fingerprint":"fp_8d13edce1d","choices":[{"index":0,"delta":{"content":"Hi"},"logprobs":null,"finish_reason":null}]}

                event: error
                data: {"error":{"message":"Tool choice is required, but model did not call a tool","type":"invalid_request_error","code":"tool_use_failed","failed_generation":"","status_code":400}}


                """#
            let response = StubResponse.eventStream(Data(stream.utf8))
            let stub = HTTPStub(
                StubResponse(status: 200, headers: response.headers.merging(["x-request-id": "req_1"]) { $1 }, chunks: response.chunks))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub, on: .groq.at(stub.baseURL)), tools: [WeatherTool()]).respond(
                    to: "Say hi.", options: GenerationOptions(toolCallingMode: .required))
            }

            #expect(
                error
                    == OpenAICompatibleError(
                        providerName: "Groq", status: 400, message: "Tool choice is required, but model did not call a tool",
                        code: "tool_use_failed", errorType: .invalidRequest, requestID: "req_1"))
        }
    }
}
