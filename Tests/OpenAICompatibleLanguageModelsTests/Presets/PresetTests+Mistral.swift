import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    /// Mistral's preset, on streams and errors written from Mistral's SDKs, docs and reported issues, since none was
    /// captured.
    @Suite("Mistral")
    struct Mistral {
        @Test func `Mistral's models reason when asked, take its efforts, and wait up to 300 seconds without a retry`() throws {
            let details = OpenAICompatibleModel("mistral-small-latest", on: .mistral)

            #expect(OpenAICompatibleProvider.mistral.name == "Mistral")
            #expect(OpenAICompatibleProvider.mistral.url == URL(string: "https://api.mistral.ai/v1"))
            #expect(OpenAICompatibleProvider.mistral.keyHeader == .bearer)
            #expect(details.reasoning == .offByDefault)
            #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["max", "xhigh", "high", "medium", "low", "minimal", "none"])
            #expect(details.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
            #expect(
                OpenAICompatibleLanguageModel(details, auth: .unauthenticated).configuration
                    == OpenAICompatibleConfiguration(idleTimeout: .seconds(300), retries: .disabled))
        }

        @Test func `a request leaves out seed, sends metadata, and asks for no usage`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: .mistral.at(stub.baseURL))).respond(
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
                  "max_tokens": 50,
                  "metadata": {
                    "team": "meals"
                  }
                }
                """
            }
        }

        @Test func `reasoning arrives in thinking parts and stays on Mistral's side, and usage comes from the last chunk`()
            async throws
        {
            let stub = HTTPStub(.eventStream(Data(Self.reasoningAnswer.utf8)), chunks(text("Hello again."), finish()))
            let session = LanguageModelSession(model: model(stub, on: .mistral.at(stub.baseURL)))

            let first = try await session.respond(to: "Say hello.", contextOptions: ContextOptions(reasoningLevel: .deep))
            _ = try await session.respond(to: "Again.")

            #expect(first.content == "Hello.")
            #expect(first.usage.input.totalTokenCount == 9)
            #expect(Self.firstAnswerHost(of: session) == "Mistral")
            let reasoning = session.transcript.compactMap { entry -> String? in
                guard case .reasoning(let reasoning) = entry else { return nil }
                return reasoning.segments.compactMap { segment in if case .text(let text) = segment { text.content } else { nil } }.joined()
            }
            #expect(reasoning == ["Plan a greeting."])
            #expect(try body(stub, 1)["messages"]?[1] == ["role": "assistant", "content": "Hello."])
        }

        @Test func `an answer that reaches the model's length counts as one at its token limit, with Mistral's word kept`()
            async throws
        {
            let text = HTTPStub(chunks(text("Half an answer"), finish("model_length")))
            let call = HTTPStub(
                chunks(
                    delta([
                        "tool_calls": [["index": 0, "id": "abcDEF123", "function": ["name": "getWeather", "arguments": #"{"city":"Pa"#]]]
                    ]),
                    finish("model_length")))
            let session = LanguageModelSession(model: model(text, on: .mistral.at(text.baseURL)))

            let response = try await session.respond(to: "Hi")
            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(call, on: .mistral.at(call.baseURL)), tools: [WeatherTool()]).respond(
                    to: "Weather in Paris?")
            }

            #expect(response.content == "Half an answer")
            guard case .response(let answer)? = session.transcript.last else {
                Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
                return
            }
            #expect(answer.openAICompatible.finishReason == "model_length")
            #expect(answer.providerMetadata.host == "Mistral")
            #expect(error?.code == .invalidResponse)
            #expect(error?.message == "The answer reached its token limit inside a tool call.")
        }

        /// The host the first answer of a session names.
        private static func firstAnswerHost(of session: LanguageModelSession) -> String? {
            session.transcript.lazy.compactMap { entry in
                if case .response(let answer) = entry { answer.providerMetadata.host } else { nil }
            }.first
        }

        /// A reasoning model's answer: its thinking in a part of its own, then its text, with usage on the last chunk,
        /// written from Mistral's SDKs.
        private static let reasoningAnswer = #"""
            data: {"id":"test0000000000000000000000000001","object":"chat.completion.chunk","created":1794300000,"model":"magistral-small-latest","choices":[{"index":0,"delta":{"role":"assistant","content":[{"type":"thinking","thinking":[{"type":"text","text":"Plan a greeting."}]}]},"finish_reason":null}]}

            data: {"id":"test0000000000000000000000000001","object":"chat.completion.chunk","created":1794300000,"model":"magistral-small-latest","choices":[{"index":0,"delta":{"content":"Hello."},"finish_reason":null}]}

            data: {"id":"test0000000000000000000000000001","object":"chat.completion.chunk","created":1794300000,"model":"magistral-small-latest","choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}],"usage":{"prompt_tokens":9,"total_tokens":21,"completion_tokens":12}}

            data: [DONE]


            """#
    }
}
