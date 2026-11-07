import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Request")
    struct Request {
        @Test func `every request looks for a removed model among those it may reach, even one that fails`() async throws {
            let stub = HTTPStub(events(textDelta("Hi"), lifecycle("response.completed")), .json("{}", status: 404))

            try await confirmation(expectedCount: 4) { read in
                let model = model(stub, reaching: [Reached(reads: read), Reached(reads: read)])

                _ = try await LanguageModelSession(model: model).respond(to: "Hello")
                await #expect(throws: (any Error).self) {
                    _ = try await LanguageModelSession(model: model).respond(to: "Hello")
                }
            }
        }

        @Test func `a request to a model its provider stopped listing is still sent`() async throws {
            let stub = HTTPStub(events(textDelta("Hi"), lifecycle("response.completed")))

            let session = LanguageModelSession(model: model(stub, reaching: [Reached(removedOn: .distantPast)]))

            let response = try await session.respond(to: "Hello")

            #expect(response.content == "Hi")
            #expect(stub.requests.count == 1)
        }

        @Test func `the format writes its members in a fixed order, leaves out a seed and raises a token limit below 16`() throws {
            let options = GenerationOptions(
                samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 10)
            let request = generationRequest([prompt(text("Hi"))], options: options, metadata: ["team": "coach"])

            let sent = try SentRequest(request)

            #expect(keys(sent.body) == ["model", "input", "stream", "temperature", "top_p", "max_output_tokens", "metadata"])
            #expect(sent.body["model"] == "vendor/model")
            #expect(sent.body["stream"] == true)
            #expect(sent.body["max_output_tokens"] == 16)
            #expect(sent.adjustments == [.unsentSettings(["seed"]), .raisedTokenLimit(requested: 10, sent: 16)])
        }

        @Test func `a plain model sends every member of the format in the format's order`() async throws {
            let stub = HTTPStub(events(textDelta(#"{"stars":4}"#), lifecycle("response.completed")))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])
            let options = GenerationOptions(
                samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 100,
                toolCallingMode: .allowed)

            _ = try await session.respond(
                to: "Rate it.", generating: Rating.self, options: options, contextOptions: ContextOptions(includeSchemaInPrompt: false),
                metadata: ["team": "coach"])

            assertInlineSnapshot(of: stub.requests[0].body, as: .memberLines) {
                """
                {
                  "model": "vendor/model",
                  "input": [
                    {
                      "role": "user",
                      "content": "Rate it."
                    }
                  ],
                  "stream": true,
                  "tools": [
                    {
                      "type": "function",
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
                      },
                      "strict": false
                    }
                  ],
                  "tool_choice": "auto",
                  "text": {
                    "format": {
                      "type": "json_schema",
                      "name": "Rating",
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
                      },
                      "strict": true
                    }
                  },
                  "temperature": 0.2,
                  "top_p": 0.5,
                  "max_output_tokens": 100,
                  "metadata": {
                    "team": "coach"
                  }
                }
                """
            }
        }

        @Test func `the exchange's members go after the format's, in the order it writes them`() throws {
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { $0.members = ["service_tier": "flex", "prompt_cache_key": "session"] }

            let body = try SentRequest(generationRequest([prompt(text("Hi"))]), model: model).body

            #expect(keys(body) == ["model", "input", "stream", "service_tier", "prompt_cache_key"])
        }

        @Test func `the exchange's storage, encrypted reasoning, reasoning and text members go out in the format's places`() throws {
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { request in
                request.storage = .notStored
                request.asksForEncryptedReasoning = true
                request.reasoning = .init(effort: "low", summary: "auto")
                request.textMembers = ["verbosity": "low"]
            }
            let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

            let body = try SentRequest(request, model: model).body

            #expect(keys(body) == ["model", "input", "stream", "store", "include", "text", "reasoning"])
            #expect(body["store"] == false)
            #expect(body["include"] == ["reasoning.encrypted_content"])
            #expect(keys(body["text"]) == ["format", "verbosity"])
            #expect(keys(body["text"]?["format"]) == ["type", "name", "schema", "strict"])
            #expect(body["text"]?["format"]?["type"] == "json_schema")
            #expect(body["text"]?["format"]?["strict"] == true)
            #expect(body["text"]?["verbosity"] == "low")
            #expect(body["reasoning"] == ["effort": "low", "summary": "auto"])
        }

        @Test func `storage the provider keeps sends store, and the provider's default sends none`() throws {
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { request in
                request.storage = .stored
                request.reasoning = .init()
            }

            let stored = try SentRequest(generationRequest([prompt(text("Hi"))]), model: model).body
            let automatic = try SentRequest(generationRequest([prompt(text("Hi"))])).body

            #expect(stored["store"] == true)
            #expect(stored["reasoning"] == nil)
            #expect(automatic["store"] == nil)
        }

        @Test func `members the models don't list are left out, then settings the format has no member for`() throws {
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.unsupportedMembers = [.temperature, .maxOutputTokens]
            let options = GenerationOptions(samplingMode: .random(top: 40, seed: 3), temperature: 0.2, maximumResponseTokens: 10)

            let sent = try SentRequest(generationRequest([prompt(text("Hi"))], options: options), model: model)

            // A token limit left out isn't raised.
            #expect(keys(sent.body) == ["model", "input", "stream"])
            #expect(sent.adjustments == [.unlistedParameters(["temperature", "max_output_tokens"]), .unsentSettings(["top_k", "seed"])])
        }

        @Test func `members the exchange leaves out with the request's settings are noted`() throws {
            var model = Responses.Model<ResponsesTestExchange>.test()
            model.exchange.prepares = { request in
                request.leftOutMembers = [.temperature, .topP]
                request.movedEffort = .init(requested: "medium", sent: "low")
            }
            let options = GenerationOptions(temperature: 0.2)

            let sent = try SentRequest(generationRequest([prompt(text("Hi"))], options: options), model: model)

            #expect(sent.body["temperature"] == nil)
            #expect(sent.adjustments == [.unsentSettings(["temperature"]), .movedEffort(requested: "medium", sent: "low")])
        }
    }
}
