import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    /// vLLM's preset, on streams written from vLLM's server source, since none was captured.
    @Suite("vLLM")
    struct VLLM {
        @Test func `vLLM's models take its efforts, max among them`() throws {
            let details = OpenAICompatibleModel("Qwen/Qwen3-8B", on: .vLLM)

            #expect(OpenAICompatibleProvider.vLLM.name == "vLLM")
            #expect(OpenAICompatibleProvider.vLLM.url == URL(string: "http://localhost:8000/v1"))
            #expect(OpenAICompatibleProvider.vLLM.format == .chatCompletions)
            #expect(OpenAICompatibleProvider.vLLM.keyHeader == .bearer)
            #expect(details.reasoning == .offByDefault)
            #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["max", "xhigh", "high", "medium", "low", "minimal", "none"])
            #expect(details.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
            #expect(OpenAICompatibleLanguageModel(details, auth: .unauthenticated).configuration == OpenAICompatibleConfiguration())
        }

        @Test func `a request sends max_completion_tokens and top_k, and leaves out metadata, which vLLM ignores`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: .vLLM.at(stub.baseURL))).respond(
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
                  "stream_options": {
                    "include_usage": true
                  },
                  "reasoning_effort": "low",
                  "top_k": 40,
                  "seed": 7,
                  "max_completion_tokens": 50
                }
                """
            }
        }

        @Test func `a model's reasoning goes back as reasoning, to that model only`() async throws {
            let stub = HTTPStub(.eventStream(Data(Self.reasoningAnswer.utf8)), chunks(text("Sonder."), finish()))
            let other = HTTPStub(chunks(text("Hiraeth."), finish()))
            let qwen = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("Qwen/Qwen3-8B", on: .vLLM.at(stub.baseURL)), session: stub.session, configuration: .stubbed,
                auth: .unauthenticated)
            let llama = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("meta-llama/Llama-3.1-8B-Instruct", on: .vLLM.at(other.baseURL)), session: other.session,
                configuration: .stubbed, auth: .unauthenticated)
            let session = LanguageModelSession(model: qwen)

            _ = try await session.respond(to: "Write one unusual English word, nothing else.")
            _ = try await session.respond(to: "Another one.")
            _ = try await LanguageModelSession(model: llama, transcript: session.transcript).respond(to: "And one more.")

            let replayed = try #require(try body(stub, 1)["messages"]?[1])
            #expect(replayed["content"] == "Petrichor.")
            #expect(replayed["reasoning"] == "Pick a word few people know.")
            #expect(try body(other)["messages"]?[1] == ["role": "assistant", "content": "Petrichor."])
        }

        @Test func `an answer vLLM aborted throws the module's error, not a complete answer`() async {
            let stub = HTTPStub(chunks(text("The weather in Par"), finish("abort")))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub, on: .vLLM.at(stub.baseURL))).respond(to: "Hi")
            }

            #expect(error == OpenAICompatibleError(providerName: "vLLM", message: "The model's response ended in an error.", code: .server))
        }

        @Test func `an answer vLLM stopped for repeating itself counts as one at its token limit, with vLLM's word kept`()
            async throws
        {
            let text = HTTPStub(chunks(text("Again and again and again"), finish("repetition")))
            let call = HTTPStub(
                chunks(
                    delta([
                        "tool_calls": [
                            [
                                "index": 0, "id": "chatcmpl-tool-1", "type": "function",
                                "function": ["name": "getWeather", "arguments": #"{"city":"Pa"#],
                            ]
                        ]
                    ]),
                    finish("repetition")))
            let session = LanguageModelSession(model: model(text, on: .vLLM.at(text.baseURL)))

            let response = try await session.respond(to: "Hi")
            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(call, on: .vLLM.at(call.baseURL)), tools: [WeatherTool()]).respond(
                    to: "Weather in Paris?")
            }

            #expect(response.content == "Again and again and again")
            guard case .response(let answer)? = session.transcript.last else {
                Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
                return
            }
            #expect(answer.openAICompatible.finishReason == "repetition")
            #expect(answer.providerMetadata.host == nil)
            #expect(error?.code == .invalidResponse)
            #expect(error?.message == "The answer reached its token limit inside a tool call.")
        }

        /// A reasoning model's answer from a server started with a reasoning parser: its reasoning, then its text, with
        /// usage in a chunk of its own, written from vLLM's server source.
        private static let reasoningAnswer = #"""
            data: {"id":"chatcmpl-test0000000000000000000000000001","object":"chat.completion.chunk","created":1794300000,"model":"Qwen/Qwen3-8B","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}

            data: {"id":"chatcmpl-test0000000000000000000000000001","object":"chat.completion.chunk","created":1794300000,"model":"Qwen/Qwen3-8B","choices":[{"index":0,"delta":{"reasoning":"Pick a word few people know."},"logprobs":null,"finish_reason":null}]}

            data: {"id":"chatcmpl-test0000000000000000000000000001","object":"chat.completion.chunk","created":1794300000,"model":"Qwen/Qwen3-8B","choices":[{"index":0,"delta":{"content":"Petrichor."},"logprobs":null,"finish_reason":null}]}

            data: {"id":"chatcmpl-test0000000000000000000000000001","object":"chat.completion.chunk","created":1794300000,"model":"Qwen/Qwen3-8B","choices":[{"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"stop","stop_reason":null}]}

            data: {"id":"chatcmpl-test0000000000000000000000000001","object":"chat.completion.chunk","created":1794300000,"model":"Qwen/Qwen3-8B","choices":[],"usage":{"prompt_tokens":18,"total_tokens":30,"completion_tokens":12}}

            data: [DONE]


            """#
    }
}
