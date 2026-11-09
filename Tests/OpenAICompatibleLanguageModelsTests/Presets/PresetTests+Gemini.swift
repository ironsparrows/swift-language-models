import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    @Suite("Gemini")
    struct Gemini {
        @Test func `Gemini's models reason unless a request turns it off, take its efforts, and fail without a retry`() throws {
            let details = OpenAICompatibleModel("gemini-3.1-flash-lite", on: .gemini)

            #expect(OpenAICompatibleProvider.gemini.name == "Gemini")
            #expect(OpenAICompatibleProvider.gemini.url == URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/"))
            #expect(OpenAICompatibleProvider.gemini.format == .chatCompletions)
            #expect(OpenAICompatibleProvider.gemini.keyHeader == .bearer)
            #expect(details.reasoning == .onByDefault)
            #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["high", "medium", "low", "minimal", "none"])
            #expect(details.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
            #expect(
                OpenAICompatibleLanguageModel(details, auth: .unauthenticated).configuration
                    == OpenAICompatibleConfiguration(retries: .disabled))
        }

        @Test func `a request leaves out seed and metadata, which Gemini refuses, and asks for usage`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: .gemini.at(stub.baseURL))).respond(
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
                  "max_tokens": 50
                }
                """
            }
        }

        @Test func `a tool call's thought signature goes back on that call, and the answer names Google AI Studio as its host`()
            async throws
        {
            let stub = HTTPStub(.eventStream(Data(Self.toolRound.utf8)), chunks(text("It's 17 degrees in Paris."), finish()))
            let session = LanguageModelSession(model: gemini(stub), tools: [WeatherTool()])

            let response = try await session.respond(to: "What is the weather in Paris?")

            #expect(response.content == "It's 17 degrees in Paris.")
            #expect(Self.signatures(in: session.transcript) == [Data("dGVzdC1zaWduYXR1cmUtY2FsbA==".utf8)])
            #expect(Self.toolCalls(in: session.transcript)?.openAICompatible.finishReason == .stop)
            #expect(Self.toolCalls(in: session.transcript)?.providerMetadata.host == "Google AI Studio")
            assertInlineSnapshot(of: stub.requests[1].body, as: .memberLines) {
                #"""
                {
                  "model": "gemini-3.1-flash-lite",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What is the weather in Paris?"
                    },
                    {
                      "role": "assistant",
                      "tool_calls": [
                        {
                          "id": "call_00000000000000000001",
                          "type": "function",
                          "function": {
                            "name": "getWeather",
                            "arguments": "{\"city\":\"Paris\"}"
                          },
                          "extra_content": {
                            "google": {
                              "thought_signature": "dGVzdC1zaWduYXR1cmUtY2FsbA=="
                            }
                          }
                        }
                      ]
                    },
                    {
                      "role": "tool",
                      "tool_call_id": "call_00000000000000000001",
                      "content": "It is 17 degrees in Paris."
                    }
                  ],
                  "stream": true,
                  "stream_options": {
                    "include_usage": true
                  },
                  "tools": [
                    {
                      "type": "function",
                      "function": {
                        "name": "getWeather",
                        "description": "Gets the current temperature in a city, in degrees Celsius.",
                        "parameters": {
                          "additionalProperties": false,
                          "properties": {
                            "city": {
                              "description": "The city's name.",
                              "type": "string"
                            }
                          },
                          "required": [
                            "city"
                          ],
                          "title": "Arguments",
                          "type": "object"
                        }
                      }
                    }
                  ]
                }
                """#
            }
        }

        @Test func `a text answer's thought signature goes back on its message, and usage comes from the answer's own chunks`()
            async throws
        {
            let stub = HTTPStub(.eventStream(Data(Self.textAnswer.utf8)), chunks(text("Hello."), finish()))
            let session = LanguageModelSession(model: gemini(stub))

            let first = try await session.respond(to: "Say hi in one word.")
            _ = try await session.respond(to: "Again.")

            #expect(first.content == "Hi.")
            #expect(first.usage.input.totalTokenCount == 7)
            #expect(
                try body(stub, 1)["messages"]?[1]
                    == [
                        "role": "assistant", "content": "Hi.",
                        "extra_content": ["google": ["thought_signature": "dGVzdC1zaWduYXR1cmUtdGV4dA=="]],
                    ])
        }

        @Test func `a signature goes back only to the model that wrote it, so another model gets the placeholder on a call`()
            async throws
        {
            let calls = HTTPStub(.eventStream(Data(Self.toolRound.utf8)), chunks(text("It's 17 degrees in Paris."), finish()))
            let texts = HTTPStub(.eventStream(Data(Self.textAnswer.utf8)))
            let switched = HTTPStub(chunks(text("Cloudy."), finish()), chunks(text("Hello."), finish()))
            let callSession = LanguageModelSession(model: gemini(calls), tools: [WeatherTool()])
            let textSession = LanguageModelSession(model: gemini(texts))

            _ = try await callSession.respond(to: "What is the weather in Paris?")
            _ = try await textSession.respond(to: "Say hi in one word.")
            _ = try await LanguageModelSession(
                model: gemini(switched, id: "gemini-3-pro"), tools: [WeatherTool()], transcript: callSession.transcript
            ).respond(to: "And tomorrow?")
            _ = try await LanguageModelSession(model: gemini(switched, id: "gemini-3-pro"), transcript: textSession.transcript).respond(
                to: "Again.")

            #expect(
                try body(switched)["messages"]?[1]?["tool_calls"]?[0]?["extra_content"]
                    == ["google": ["thought_signature": "skip_thought_signature_validator"]])
            #expect(try body(switched, 1)["messages"]?[1] == ["role": "assistant", "content": "Hi."])
        }

        @Test func `of parallel calls, only the first goes back with a signature: Gemini's own, or a placeholder for another provider's`()
            async throws
        {
            // Two calls in one chunk, the first with a signature, as Gemini's docs describe parallel calls; not captured.
            let parallel = chunks(
                delta([
                    "tool_calls": [
                        [
                            "id": "call_00000000000000000001", "type": "function",
                            "function": ["name": "getWeather", "arguments": #"{"city":"Paris"}"#],
                            "extra_content": ["google": ["thought_signature": "dGVzdC1zaWduYXR1cmUtY2FsbA=="]],
                        ],
                        [
                            "id": "call_00000000000000000002", "type": "function",
                            "function": ["name": "getWeather", "arguments": #"{"city":"Rome"}"#],
                        ],
                    ]
                ]),
                finish())
            let own = HTTPStub(parallel, chunks(text("Mild in both."), finish()))
            let elsewhere = HTTPStub(
                chunks(
                    delta([
                        "tool_calls": [
                            [
                                "index": 0, "id": "call_a", "type": "function",
                                "function": ["name": "getWeather", "arguments": #"{"city":"Paris"}"#],
                            ],
                            [
                                "index": 1, "id": "call_b", "type": "function",
                                "function": ["name": "getWeather", "arguments": #"{"city":"Rome"}"#],
                            ],
                        ]
                    ]),
                    finish("tool_calls")),
                chunks(text("Mild in both."), finish()))
            let continued = HTTPStub(chunks(text("Still mild."), finish()))
            let other = LanguageModelSession(model: model(elsewhere), tools: [WeatherTool()])

            _ = try await LanguageModelSession(model: model(own, on: .gemini.at(own.baseURL)), tools: [WeatherTool()]).respond(
                to: "Weather in Paris and Rome?")
            _ = try await other.respond(to: "Weather in Paris and Rome?")
            _ = try await LanguageModelSession(
                model: model(continued, on: .gemini.at(continued.baseURL)), tools: [WeatherTool()], transcript: other.transcript
            ).respond(to: "And now?")

            let signed = try #require(try body(own, 1)["messages"]?[1]?["tool_calls"])
            let placed = try #require(try body(continued)["messages"]?[1]?["tool_calls"])
            #expect(signed[0]?["extra_content"] == ["google": ["thought_signature": "dGVzdC1zaWduYXR1cmUtY2FsbA=="]])
            #expect(signed[1]?["extra_content"] == nil)
            #expect(placed[0]?["extra_content"] == ["google": ["thought_signature": "skip_thought_signature_validator"]])
            #expect(placed[1]?["extra_content"] == nil)
        }

        @Test(arguments: [
            PresetTests.Rejection(
                name: "a missing key", status: 400,
                body: #"""
                    [{
                      "error": {
                        "code": 400,
                        "message": "Missing or invalid Authorization header.",
                        "status": "INVALID_ARGUMENT"
                      }
                    }
                    ]
                    """#,
                error: OpenAICompatibleError(
                    providerName: "Gemini", status: 400, message: "Missing or invalid Authorization header.", code: .authentication,
                    errorType: "INVALID_ARGUMENT")),
            // An invalid key, written from the Gemini API's wording for one; not captured.
            PresetTests.Rejection(
                name: "an invalid key", status: 400,
                body:
                    #"[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}]"#,
                error: OpenAICompatibleError(
                    providerName: "Gemini", status: 400, message: "API key not valid. Please pass a valid API key.", code: .authentication,
                    errorType: "INVALID_ARGUMENT")),
            PresetTests.Rejection(
                name: "an overloaded model, sent once", status: 503,
                body: #"""
                    [{
                      "error": {
                        "code": 503,
                        "message": "This model is currently experiencing high demand. Spikes in demand are usually temporary. Please try again later.",
                        "status": "UNAVAILABLE"
                      }
                    }
                    ]
                    """#,
                error: OpenAICompatibleError(
                    providerName: "Gemini", status: 503,
                    message:
                        "This model is currently experiencing high demand. Spikes in demand are usually temporary. Please try again later.",
                    code: .server, errorType: "UNAVAILABLE")),
        ])
        func `a refused key has the authentication code, and an overloaded model fails without a retry`(rejection: PresetTests.Rejection)
            async
        {
            let stub = HTTPStub(.json(rejection.body, status: rejection.status, headers: rejection.headers))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub, on: .gemini.at(stub.baseURL), configuration: nil)).respond(to: "Hi")
            }

            #expect(error == rejection.error)
            #expect(stub.requests.count == 1)
        }

        @Test func `a rate limit resets after the wait Gemini's body names, with no retry and with Google AI Studio as the host`()
            async throws
        {
            // Gemini's 429 on its free tier, as captured: no Retry-After header, the wait in the body's RetryInfo.
            let stub = HTTPStub(.json(Self.rateLimit, status: 429))
            let before = Date.now

            let error = await #expect(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model(stub, on: .gemini.at(stub.baseURL), configuration: nil)).respond(to: "Hi")
            }

            guard case .rateLimited(let context)? = error, let reset = context.resetDate else {
                Issue.record("Expected a rate limit with a reset date, got \(String(describing: error))")
                return
            }
            #expect(reset.timeIntervalSince(before) >= 7)
            #expect(reset.timeIntervalSince(before) < 60)
            #expect(error?.openAICompatible.code == "RESOURCE_EXHAUSTED")
            #expect(error?.providerMetadata.host == "Google AI Studio")
            #expect(stub.requests.count == 1)
        }

        @Test func `a prompt over the model's context throws Foundation Models' error with the sizes Gemini names`() async throws {
            // Gemini's words for an oversized prompt, written from reports; not captured, and the wording is unverified.
            let stub = HTTPStub(
                .json(
                    #"[{"error":{"code":400,"message":"The input token count (1050000) exceeds the maximum number of tokens allowed (1048576).","status":"INVALID_ARGUMENT"}}]"#,
                    status: 400))

            let error = await #expect(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model(stub, on: .gemini.at(stub.baseURL))).respond(to: "Hi")
            }

            guard case .contextSizeExceeded(let context)? = error else {
                Issue.record("Expected an oversized context, got \(String(describing: error))")
                return
            }
            #expect(context.contextSize == 1_048_576)
            #expect(context.tokenCount == 1_050_000)
        }

        /// Gemini's tool call with its thought signature, then a finish of `stop`, as captured: ids and the signature
        /// swapped.
        private static let toolRound = #"""
            data: {"choices":[{"delta":{"role":"assistant","tool_calls":[{"extra_content":{"google":{"thought_signature":"dGVzdC1zaWduYXR1cmUtY2FsbA=="}},"function":{"arguments":"{\"city\":\"Paris\"}","name":"getWeather"},"id":"call_00000000000000000001","type":"function"}]},"index":0}],"created":1794203010,"id":"test00000000000000000001","model":"gemini-3.1-flash-lite","object":"chat.completion.chunk"}

            data: {"choices":[{"delta":{"role":"assistant"},"finish_reason":"stop","index":0}],"created":1794203010,"id":"test00000000000000000001","model":"gemini-3.1-flash-lite","object":"chat.completion.chunk"}

            data: [DONE]


            """#

        /// Gemini's text answer with its usage on each chunk and its thought signature on the last, as captured: the id
        /// and the signature swapped.
        private static let textAnswer = #"""
            data: {"choices":[{"delta":{"content":"Hi.","role":"assistant"},"index":0}],"created":1794202705,"id":"test00000000000000000002","model":"gemini-3.1-flash-lite","object":"chat.completion.chunk","usage":{"completion_tokens":2,"prompt_tokens":7,"total_tokens":9}}

            data: {"choices":[{"delta":{"extra_content":{"google":{"thought_signature":"dGVzdC1zaWduYXR1cmUtdGV4dA=="}},"role":"assistant"},"finish_reason":"stop","index":0}],"created":1794202705,"id":"test00000000000000000002","model":"gemini-3.1-flash-lite","object":"chat.completion.chunk","usage":{"completion_tokens":2,"prompt_tokens":7,"total_tokens":9}}

            data: [DONE]


            """#

        /// Gemini's 429 on its free tier, as captured.
        private static let rateLimit = #"""
            [{
              "error": {
                "code": 429,
                "message": "You exceeded your current quota, please check your plan and billing details. For more information on this error, head to: https://aistudio.google.com/docs/rate-limits. To monitor your current usage, head to: https://ai.dev/rate-limit. \n* Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 15, model: gemini-3.1-flash-lite, description: Generate content requests per minute limit exceeded on Free Tier. See https://aistudio.google.com/docs/rate-limits.\nPlease retry in 7.206449503s.",
                "status": "RESOURCE_EXHAUSTED",
                "details": [
                  {
                    "@type": "type.googleapis.com/google.rpc.Help",
                    "links": [
                      {
                        "description": "Learn more about Gemini API quotas",
                        "url": "https://aistudio.google.com/docs/rate-limits"
                      }
                    ]
                  },
                  {
                    "@type": "type.googleapis.com/google.rpc.QuotaFailure",
                    "violations": [
                      {
                        "description": "Generate content requests per minute limit exceeded on Free Tier. See https://aistudio.google.com/docs/rate-limits.",
                        "quotaMetric": "generativelanguage.googleapis.com/generate_content_free_tier_requests",
                        "quotaId": "GenerateRequestsPerMinutePerProjectPerModel-FreeTier",
                        "quotaDimensions": {
                          "location": "global",
                          "model": "gemini-3.1-flash-lite"
                        },
                        "quotaValue": "15"
                      }
                    ]
                  },
                  {
                    "@type": "type.googleapis.com/google.rpc.RetryInfo",
                    "retryDelay": "7s"
                  }
                ]
              }
            }
            ]
            """#

        /// A model on Gemini, served by a stub, with the id Gemini's captured answers name it by unless another is given.
        private func gemini(_ stub: HTTPStub, id: OpenAICompatibleModelID = "gemini-3.1-flash-lite") -> OpenAICompatibleLanguageModel {
            OpenAICompatibleLanguageModel(
                OpenAICompatibleModel(id, on: .gemini.at(stub.baseURL)), session: stub.session, configuration: .stubbed,
                auth: .apiKey { "test-key" })
        }

        /// The signatures of a transcript's reasoning entries.
        private static func signatures(in transcript: Transcript) -> [Data] {
            transcript.compactMap { entry in
                if case .reasoning(let reasoning) = entry { reasoning.signature } else { nil }
            }
        }

        /// A transcript's first tool calls.
        private static func toolCalls(in transcript: Transcript) -> Transcript.ToolCalls? {
            transcript.lazy.compactMap { entry in
                if case .toolCalls(let calls) = entry { calls } else { nil }
            }.first
        }
    }
}
