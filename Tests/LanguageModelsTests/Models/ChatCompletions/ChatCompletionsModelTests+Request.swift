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
        @Test func `every request looks for a removed model among those it may reach, even one that fails`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("Hi", finishReason: "stop")), .json("{}", status: 404))

            try await confirmation(expectedCount: 4) { read in
                let model = model(stub, reaching: [Reached(reads: read), Reached(reads: read)])

                _ = try await LanguageModelSession(model: model).respond(to: "Hello")
                await #expect(throws: (any Error).self) {
                    _ = try await LanguageModelSession(model: model).respond(to: "Hello")
                }
            }
        }

        @Test func `a request to a model its provider stopped listing is still sent`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("Hi", finishReason: "stop")))

            let session = LanguageModelSession(model: model(stub, reaching: [Reached(removedOn: .distantPast)]))

            let response = try await session.respond(to: "Hello")

            #expect(response.content == "Hi")
            #expect(stub.requests.count == 1)
        }

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

        @Test(
            arguments: [
                ([:], [:], [], [.unsentSettings(["top_k"])]),
                (["top_k": 40], [:], [], []),
                ([:], ["top_k": 20], [], []),
                (["top_k": 40], [:], ["top_k"], [.unlistedParameters(["top_k"])]),
            ] as [(JSONObject, JSONObject, Set<ChatCompletions.Member>, [RequestAdjustment])])
        func `top_k goes out only as a member, and is noted once when none carries it`(
            members: JSONObject, overridingMembers: JSONObject, unsupported: Set<ChatCompletions.Member>, adjustments: [RequestAdjustment]
        ) throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.unsupportedMembers = unsupported
            model.exchange.prepares = { request in
                request.members = members
                request.overridingMembers = overridingMembers
            }
            let options = GenerationOptions(samplingMode: .random(top: 40, seed: 3))

            let sent = try ChatCompletionsSentRequest(generationRequest([prompt(text("Hi"))], options: options), model: model)

            #expect(sent.adjustments == adjustments)
        }

        @Test func `the app's members replace any but the four the answer depends on, though the models don't list them`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.unsupportedMembers = [.temperature, .metadata]
            model.exchange.prepares = { request in
                request.members = ["models": ["vendor/fallback"], "plugins": []]
                request.movedEffort = .init(requested: "medium", sent: "low")
                request.overridingMembers = [
                    "keep_alive": "5m", "stream": false, "temperature": 1.5, "plugins": [["id": "web"]], "model": "other", "messages": [],
                    "tools": [], "metadata": ["team": "coach"],
                ]
            }
            let options = GenerationOptions(temperature: 0.2)
            let request = generationRequest([prompt(text("Hi"))], options: options, metadata: ["count": 3])

            let sent = try ChatCompletionsSentRequest(request, model: model)

            #expect(keys(sent.body) == ["model", "models", "messages", "stream", "temperature", "plugins", "keep_alive", "metadata"])
            #expect(sent.body["model"] == "vendor/model")
            #expect(sent.body["stream"] == true)
            #expect(sent.body["temperature"] == 1.5)
            #expect(sent.body["plugins"] == [["id": "web"]])
            #expect(sent.body["metadata"] == ["team": "coach"])
            #expect(messages(sent.body).count == 1)
            #expect(
                sent.adjustments == [
                    .keptMembers(["stream", "model", "messages", "tools"]), .movedEffort(requested: "medium", sent: "low"),
                ])
        }

        @Test func `the app's members go out on the portable schema's retry too, and the app's response_format leaves none to retry with`()
            throws
        {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.overridingMembers = ["temperature": 1.5] }
            let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

            let portable = try ChatCompletionsSentRequest(request, model: model).portableSchemaBody
            model.exchange.prepares = { $0.overridingMembers = ["response_format": ["type": "json_object"]] }
            let replaced = try ChatCompletionsSentRequest(request, model: model)

            #expect(portable?["temperature"] == 1.5)
            #expect(replaced.body["response_format"] == ["type": "json_object"])
            #expect(replaced.portableSchemaBody == nil)
        }

        /// Options that set each of the format's members for them.
        private var everySetting: GenerationOptions {
            GenerationOptions(
                samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 10,
                toolCallingMode: .allowed)
        }
    }
}
