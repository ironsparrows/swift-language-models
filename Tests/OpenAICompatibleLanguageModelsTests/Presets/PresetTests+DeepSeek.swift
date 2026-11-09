import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    /// DeepSeek's preset, on streams and errors written from DeepSeek's docs and reported issues, since none was
    /// captured.
    @Suite("DeepSeek")
    struct DeepSeek {
        @Test func `DeepSeek's models reason unless a request turns it off, take its efforts, and take no schema`() throws {
            let details = OpenAICompatibleModel("deepseek-flash", on: .deepSeek)

            #expect(OpenAICompatibleProvider.deepSeek.name == "DeepSeek")
            #expect(OpenAICompatibleProvider.deepSeek.url == URL(string: "https://api.deepseek.com"))
            #expect(OpenAICompatibleProvider.deepSeek.keyHeader == .bearer)
            #expect(details.reasoning == .onByDefault)
            #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["max", "high", "medium", "low", "none"])
            #expect(details.capabilities.listed == [.toolCalling, .reasoning, .vision])
            #expect(OpenAICompatibleLanguageModel(details, auth: .unauthenticated).configuration == OpenAICompatibleConfiguration())
        }

        @Test func `a request turns reasoning off with thinking beside the effort, and leaves out seed and metadata`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: .deepSeek.at(stub.baseURL))).respond(
                to: "Hi", options: GenerationOptions(samplingMode: .random(top: 40, seed: 7), maximumResponseTokens: 50),
                contextOptions: ContextOptions(reasoningLevel: .off), metadata: ["team": "meals"])

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
                  "reasoning_effort": "none",
                  "thinking": {
                    "type": "disabled"
                  },
                  "max_tokens": 50
                }
                """
            }
        }

        @Test(arguments: [
            (ContextOptions.ReasoningLevel.max, "max", "enabled"), (.deep, "high", "enabled"), (.moderate, "medium", "enabled"),
            (.light, "low", "enabled"), (.off, "none", "disabled"),
        ])
        func `thinking follows the effort a reasoning level sends`(level: ContextOptions.ReasoningLevel, effort: String, thinking: String)
            async throws
        {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: .deepSeek.at(stub.baseURL))).respond(
                to: "Hi", contextOptions: ContextOptions(reasoningLevel: level))

            let sent = try body(stub)
            #expect(sent["reasoning_effort"]?.stringValue == effort)
            #expect(sent["thinking"] == ["type": .string(thinking)])
        }

        @Test func `a model that doesn't reason turns thinking off with every request, and one without none does for the level off`()
            async throws
        {
            let plain = HTTPStub(chunks(text("Hi"), finish()))
            let narrow = HTTPStub(chunks(text("Hi"), finish()))
            let unreasoning = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("deepseek-flash", on: .deepSeek.at(plain.baseURL), reasoning: .unsupported),
                session: plain.session, configuration: .stubbed, auth: .apiKey { "test-key" })
            let withoutNone = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("deepseek-flash", on: .deepSeek.at(narrow.baseURL), efforts: [.high, .low]),
                session: narrow.session, configuration: .stubbed, auth: .apiKey { "test-key" })

            _ = try await LanguageModelSession(model: unreasoning, tools: [WeatherTool()]).respond(
                to: "Hi", options: GenerationOptions(toolCallingMode: .required))
            _ = try await LanguageModelSession(model: withoutNone, tools: [WeatherTool()]).respond(
                to: "Hi", options: GenerationOptions(toolCallingMode: .required), contextOptions: ContextOptions(reasoningLevel: .off))

            #expect(try body(plain)["thinking"] == ["type": "disabled"])
            #expect(try body(plain)["reasoning_effort"] == nil)
            #expect(try body(plain)["tool_choice"] == "required")
            #expect(try body(narrow)["thinking"] == ["type": "disabled"])
            #expect(try body(narrow)["reasoning_effort"] == "low")
            #expect(try body(narrow)["tool_choice"] == "required")
        }

        @Test func `an app's effort goes without the preset's thinking, and an app's thinking replaces it`() async throws {
            let effort = HTTPStub(chunks(text("Hi"), finish()))
            let thinking = HTTPStub(chunks(text("Hi"), finish()))
            let appEffort = OpenAICompatibleOptions(additionalMembers: ["reasoning_effort": GeneratedContent("max")])
            let appThinking = OpenAICompatibleOptions(additionalMembers: ["thinking": try GeneratedContent(json: #"{"type":"disabled"}"#)])

            _ = try await LanguageModelSession(model: model(effort, on: .deepSeek.at(effort.baseURL), options: appEffort)).respond(
                to: "Hi", contextOptions: ContextOptions(reasoningLevel: .off))
            _ = try await LanguageModelSession(model: model(thinking, on: .deepSeek.at(thinking.baseURL), options: appThinking)).respond(
                to: "Hi", contextOptions: ContextOptions(reasoningLevel: .deep))

            #expect(try body(effort)["reasoning_effort"] == "max")
            #expect(try body(effort)["thinking"] == nil)
            #expect(try body(thinking)["reasoning_effort"] == "high")
            #expect(try body(thinking)["thinking"] == ["type": "disabled"])
        }

        @Test(
            arguments: [
                (ContextOptions.ReasoningLevel?.none, [:], true), (.deep, [:], true), (.off, [:], false),
                (.deep, ["thinking": #"{"type":"disabled"}"#], false), (nil, ["reasoning_effort": #""none""#], false),
            ] as [(ContextOptions.ReasoningLevel?, [String: String], Bool)])
        func `a required tool call is refused before it's sent while the model reasons`(
            level: ContextOptions.ReasoningLevel?, members: [String: String], refused: Bool
        ) async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))
            let options = OpenAICompatibleOptions(additionalMembers: try members.mapValues { try GeneratedContent(json: $0) })
            let session = LanguageModelSession(model: model(stub, on: .deepSeek.at(stub.baseURL), options: options), tools: [WeatherTool()])

            do {
                _ = try await session.respond(
                    to: "Hi", options: GenerationOptions(toolCallingMode: .required), contextOptions: ContextOptions(reasoningLevel: level))
                #expect(!refused)
                #expect(try body(stub)["tool_choice"] == "required")
            } catch let error as LanguageModelError {
                guard case .unsupportedCapability(let context) = error else {
                    Issue.record("Expected an unsupported capability, got \(error)")
                    return
                }
                #expect(refused)
                #expect(context.capability == .toolCalling)
                #expect(stub.requests.isEmpty)
            }
        }

        @Test func `a required tool call goes to a model that reasons only when asked, with no level set`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))
            let details = OpenAICompatibleModel("deepseek-chat", on: .deepSeek.at(stub.baseURL), reasoning: .offByDefault)
            let model = OpenAICompatibleLanguageModel(details, session: stub.session, configuration: .stubbed, auth: .apiKey { "sk-test" })
            let session = LanguageModelSession(model: model, tools: [WeatherTool()])

            _ = try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: .required))

            #expect(try body(stub)["tool_choice"] == "required")
            #expect(try body(stub)["thinking"] == nil)
        }

        @Test func `reasoning goes back as reasoning_content in a tool loop, and usage comes from the last content chunk`() async throws {
            let stub = HTTPStub(.eventStream(Data(Self.toolRound.utf8)), .eventStream(Data(Self.answer.utf8)))
            let session = LanguageModelSession(model: model(stub, on: .deepSeek.at(stub.baseURL)), tools: [WeatherTool()])

            let response = try await session.respond(to: "What is the weather in Paris?")

            #expect(response.content == "It's 17 degrees in Paris.")
            #expect(response.usage.input.totalTokenCount == 160)
            #expect(response.usage.output.totalTokenCount == 12)
            assertInlineSnapshot(of: stub.requests[1].body, as: .memberLines) {
                #"""
                {
                  "model": "test-model",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What is the weather in Paris?"
                    },
                    {
                      "role": "assistant",
                      "reasoning_content": "The user wants the weather in Paris.",
                      "tool_calls": [
                        {
                          "id": "call_00_test000000000000000001",
                          "type": "function",
                          "function": {
                            "name": "getWeather",
                            "arguments": "{\"city\":\"Paris\"}"
                          }
                        }
                      ]
                    },
                    {
                      "role": "tool",
                      "tool_call_id": "call_00_test000000000000000001",
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

        @Test(arguments: ["request-id", "x-request-id", "x-deepseek-request-id"])
        func `the request id comes from whichever of DeepSeek's headers carries it`(header: String) async throws {
            let stub = HTTPStub(chunks(headers: [header: "req_1"], text("Hi"), finish()))
            let session = LanguageModelSession(model: model(stub, on: .deepSeek.at(stub.baseURL)))

            _ = try await session.respond(to: "Hi")

            guard case .response(let answer)? = session.transcript.last else {
                Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
                return
            }
            #expect(answer.openAICompatible.requestID == "req_1")
            #expect(answer.providerMetadata.host == "DeepSeek")
        }

        @Test(arguments: ["insufficient_system_resource", "aborted"])
        func `an answer DeepSeek's servers cut short throws the module's error, not a complete answer`(finishReason: String) async {
            let stub = HTTPStub(chunks(text("The weather in Par"), finish(finishReason)))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub, on: .deepSeek.at(stub.baseURL))).respond(to: "Hi")
            }

            #expect(
                error == OpenAICompatibleError(providerName: "DeepSeek", message: "The model's response ended in an error.", code: .server))
        }

        @Test func `a request DeepSeek's content filter refuses throws Foundation Models' guardrail error`() async throws {
            // DeepSeek's 400 for content its filter refuses, written from a reported body.
            let stub = HTTPStub(
                .json(
                    #"{"error":{"message":"Content Exists Risk","type":"invalid_request_error","param":null,"code":"invalid_request_error"}}"#,
                    status: 400, headers: ["request-id": "req_1"]))

            let error = await #expect(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model(stub, on: .deepSeek.at(stub.baseURL))).respond(to: "Hi")
            }

            guard case .guardrailViolation? = error else {
                Issue.record("Expected a guardrail violation, got \(String(describing: error))")
                return
            }
            #expect(error?.openAICompatible.providerName == "DeepSeek")
            #expect(error?.openAICompatible.requestID == "req_1")
            #expect(error?.providerMetadata.host == "DeepSeek")
        }

        /// A tool call after reasoning, with usage on its last chunk and no usage-only chunk, written from DeepSeek's
        /// docs.
        private static let toolRound = #"""
            data: {"id":"00000000-0000-4000-8000-000000000001","object":"chat.completion.chunk","created":1794300000,"model":"deepseek-flash","choices":[{"index":0,"delta":{"role":"assistant","content":null,"reasoning_content":"The user wants the weather in Paris."},"logprobs":null,"finish_reason":null}],"usage":null}

            data: {"id":"00000000-0000-4000-8000-000000000001","object":"chat.completion.chunk","created":1794300000,"model":"deepseek-flash","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_00_test000000000000000001","type":"function","function":{"name":"getWeather","arguments":""}}]},"logprobs":null,"finish_reason":null}],"usage":null}

            data: {"id":"00000000-0000-4000-8000-000000000001","object":"chat.completion.chunk","created":1794300000,"model":"deepseek-flash","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city\":\"Paris\"}"}}]},"logprobs":null,"finish_reason":null}],"usage":null}

            data: {"id":"00000000-0000-4000-8000-000000000001","object":"chat.completion.chunk","created":1794300000,"model":"deepseek-flash","choices":[{"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":120,"completion_tokens":30,"total_tokens":150,"prompt_tokens_details":{"cached_tokens":0},"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":120,"completion_tokens_details":{"reasoning_tokens":12}}}

            data: [DONE]


            """#

        /// A text answer after reasoning, with usage on its last chunk, written from DeepSeek's docs.
        private static let answer = #"""
            data: {"id":"00000000-0000-4000-8000-000000000002","object":"chat.completion.chunk","created":1794300001,"model":"deepseek-flash","choices":[{"index":0,"delta":{"role":"assistant","content":null,"reasoning_content":"The tool says 17 degrees."},"logprobs":null,"finish_reason":null}],"usage":null}

            data: {"id":"00000000-0000-4000-8000-000000000002","object":"chat.completion.chunk","created":1794300001,"model":"deepseek-flash","choices":[{"index":0,"delta":{"content":"It's 17 degrees in Paris."},"logprobs":null,"finish_reason":null}],"usage":null}

            data: {"id":"00000000-0000-4000-8000-000000000002","object":"chat.completion.chunk","created":1794300001,"model":"deepseek-flash","choices":[{"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"stop"}],"usage":{"prompt_tokens":160,"completion_tokens":12,"total_tokens":172,"prompt_tokens_details":{"cached_tokens":64},"prompt_cache_hit_tokens":64,"prompt_cache_miss_tokens":96,"completion_tokens_details":{"reasoning_tokens":6}}}

            data: [DONE]


            """#
    }
}
