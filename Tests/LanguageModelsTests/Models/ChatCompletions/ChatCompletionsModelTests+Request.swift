import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Request")
    struct Request {
        @Test func `the format writes its members in a fixed order`() throws {
            let options = GenerationOptions(
                samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 10)
            let request = generationRequest([prompt(text("Hi"))], options: options, metadata: ["team": "coach"])

            let body = try ChatCompletionsSentRequest(request).body

            #expect(keys(body) == ["model", "messages", "stream", "temperature", "top_p", "seed", "max_completion_tokens", "metadata"])
            #expect(body["model"] == "vendor/model")
            #expect(body["stream"] == true)
        }

        @Test func `a plain model sends every member of the format in the format's order`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk(#"{"stars":4}"#, finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])

            _ = try await session.respond(
                to: "Rate it.", generating: Rating.self, options: everySetting,
                contextOptions: ContextOptions(includeSchemaInPrompt: false),
                metadata: ["team": "coach"])

            assertInlineSnapshot(of: stub.requests[0].body, as: .memberLines) {
                """
                {
                  "model": "vendor/model",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Rate it."
                    }
                  ],
                  "stream": true,
                  "tools": [
                    {
                      "type": "function",
                      "function": {
                        "name": "lookUp",
                        "description": "Looks up a word.",
                        "parameters": {
                          "additionalProperties": false,
                          "properties": {
                            "word": {
                              "type": "string"
                            }
                          },
                          "required": [
                            "word"
                          ],
                          "title": "Arguments",
                          "type": "object"
                        }
                      }
                    }
                  ],
                  "tool_choice": "auto",
                  "response_format": {
                    "type": "json_schema",
                    "json_schema": {
                      "name": "Rating",
                      "strict": true,
                      "schema": {
                        "additionalProperties": false,
                        "properties": {
                          "stars": {
                            "maximum": 5,
                            "minimum": 1,
                            "type": "integer"
                          }
                        },
                        "required": [
                          "stars"
                        ],
                        "title": "Rating",
                        "type": "object"
                      }
                    }
                  },
                  "temperature": 0.2,
                  "top_p": 0.5,
                  "seed": 1,
                  "max_completion_tokens": 10,
                  "metadata": {
                    "team": "coach"
                  }
                }
                """
            }
        }

        @Test func `the older token limit keeps the same place in the format's order`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.memberOrder = ChatCompletions.Member.formatOrder
            model.exchange.prepares = { $0.tokenLimitMember = .maxTokens }
            let request = generationRequest(
                [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())], schema: Rating.generationSchema,
                options: everySetting, metadata: ["team": "coach"])

            let body = try ChatCompletionsSentRequest(request, model: model).body

            #expect(
                keys(body) == [
                    "model", "messages", "stream", "tools", "tool_choice", "response_format", "temperature", "top_p", "seed", "max_tokens",
                    "metadata",
                ])
        }

        @Test func `a request's sampling goes out within the format's limits`() throws {
            let options = GenerationOptions(samplingMode: .random(probabilityThreshold: 0.5, seed: (1 << 63) + 7), temperature: 3)

            let body = try ChatCompletionsSentRequest(generationRequest([prompt(text("Hi"))], options: options)).body

            #expect(body["temperature"] == 2.0)
            #expect(body["seed"] == 7)
        }

        @Test func `the exchange adds its members, in the model's order`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.members = ["models": ["vendor/fallback"], "plugins": []] }

            let body = try ChatCompletionsSentRequest(generationRequest([prompt(text("Hi"))]), model: model).body

            #expect(keys(body) == ["model", "models", "messages", "stream", "plugins"])
        }

        @Test func `members the models don't list are left out and noted in body order, before metadata left out`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.movedEffort = .init(requested: "medium", sent: "low") }
            model.unsupportedMembers = [.temperature, .maxCompletionTokens]
            let options = GenerationOptions(
                samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 10)
            let request = generationRequest([prompt(text("Hi"))], options: options, metadata: ["count": 3])

            let completion = try ChatCompletionsSentRequest(request, model: model)

            #expect(keys(completion.body) == ["model", "messages", "stream", "top_p", "seed"])
            #expect(
                completion.adjustments == [
                    .unlistedParameters(["temperature", "max_completion_tokens"]), .droppedMetadata(keys: ["count"]),
                    .movedEffort(requested: "medium", sent: "low"),
                ])
        }

        @Test func `the last instructions' last part carries the exchange's marks`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.instructionsMark = ["cache_control": ["type": "ephemeral"]] }
            let entries: [Transcript.Entry] = [
                .instructions(Transcript.Instructions(segments: [text("Be brief.")], toolDefinitions: [])), prompt(text("Hi")),
            ]

            let sent = messages(try ChatCompletionsSentRequest(generationRequest(entries), model: model).body)

            #expect(sent.first?["content"] == [["type": "text", "text": "Be brief.", "cache_control": ["type": "ephemeral"]]])
        }

        /// Options that set each of the format's members for them.
        private var everySetting: GenerationOptions {
            GenerationOptions(
                samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 10,
                toolCallingMode: .allowed)
        }
    }
}
