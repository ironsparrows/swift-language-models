import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing

extension RecordedExchangeTests {
    @Suite("Ollama")
    struct Ollama {
        @Test func `a real answer without reasoning reads as Ollama sent it`() async throws {
            let exchange = try await ExactExchange(replaying: .ollamaText)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "qwen3:0.6b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Name one color of the sea."
                    }
                  ],
                  "stream": true,
                  "stream_options": {
                    "include_usage": true
                  },
                  "reasoning_effort": "none",
                  "max_tokens": 300
                }

                transcript
                prompt ["Name one color of the sea."] metadata: {}
                response ["One color of the sea is the **blue**."] metadata: {"finishReason":"stop","model":"qwen3:0.6b","responseID":"chatcmpl-443"}

                usage
                input 23 cached 0, output 12 reasoning 0, metadata: {}

                last snapshot
                "One color of the sea is the **blue**." ["response [\"One color of the sea is the **blue**.\"] metadata: {\"finishReason\":\"stop\",\"model\":\"qwen3:0.6b\",\"responseID\":\"chatcmpl-443\"}"]
                """#
            }
        }

        @Test func `a call's reasoning goes back with it, and Ollama answers its output`() async throws {
            let exchange = try await ExactExchange(replaying: .ollamaTools)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "qwen3:0.6b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What's the temperature in Lisbon? Use the tool."
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
                  ],
                  "max_tokens": 1500
                }

                request 2
                {
                  "model": "qwen3:0.6b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What's the temperature in Lisbon? Use the tool."
                    },
                    {
                      "role": "assistant",
                      "reasoning": "Okay, the user is asking for the temperature in Lisbon. I need to use the getWeather function to get that information. Let me check the function's parameters. The function takes a city name as an argument, which is a string. So I should call getWeather with the city set to \"Lisbon\". I don't see any other parameters needed for this function. Just make sure to format the tool call correctly as specified.\n",
                      "tool_calls": [
                        {
                          "id": "call_eds04pjl",
                          "type": "function",
                          "function": {
                            "name": "getWeather",
                            "arguments": "{\"city\":\"Lisbon\"}"
                          }
                        }
                      ]
                    },
                    {
                      "role": "tool",
                      "tool_call_id": "call_eds04pjl",
                      "content": "It is 17 degrees in Lisbon."
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
                  ],
                  "max_tokens": 1500
                }

                transcript
                instructions [] tools: ["getWeather"]
                prompt ["What's the temperature in Lisbon? Use the tool."] metadata: {}
                reasoning ["Okay, the user is asking for the temperature in Lisbon. I need to use the getWeather function to get that information. Let me check the function's parameters. The function takes a city name as an argument, which is a string. So I should call getWeather with the city set to \"Lisbon\". I don't see any other parameters needed for this function. Just make sure to format the tool call correctly as specified.\n"] metadata: {"model":"qwen3:0.6b","reasoningOrigin":"openai-compatible/ollama"} signature: nil
                toolCalls ["call_eds04pjl getWeather {\"city\":\"Lisbon\"} metadata: {\"finishReason\":\"tool_calls\",\"model\":\"qwen3:0.6b\",\"responseID\":\"chatcmpl-000\"}"]
                toolOutput call_eds04pjl getWeather ["It is 17 degrees in Lisbon."]
                reasoning ["Okay, the user asked for the temperature in Lisbon using the tool. I called getWeather with \"Lisbon\" as the city, and the response was 17 degrees. Now I need to present this information clearly. Let me make sure to state the temperature in a friendly manner and confirm that it's Lisbon. No other details are needed here.\n"] metadata: {"model":"qwen3:0.6b","reasoningOrigin":"openai-compatible/ollama"} signature: nil
                response ["The temperature in Lisbon is currently 17 degrees Celsius."] metadata: {"finishReason":"stop","model":"qwen3:0.6b","responseID":"chatcmpl-618"}

                usage
                input 288 cached 156, output 89 reasoning 0, metadata: {}
                """#
            }
        }

        @Test func `a real guided answer decodes`() async throws {
            let exchange = try await ExactExchange(replaying: .ollamaGuided)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "qwen3.5:4b",
                  "messages": [
                    {
                      "role": "user",
                      "content": [
                        {
                          "type": "text",
                          "text": "Plan a short trip to Lisbon."
                        },
                        {
                          "type": "text",
                          "text": "Respond with JSON that matches this JSON Schema:\n{\"$defs\":{\"Activity\":{\"additionalProperties\":false,\"properties\":{\"name\":{\"type\":\"string\"},\"hours\":{\"description\":\"How many hours it takes.\",\"maximum\":12,\"minimum\":1,\"type\":\"integer\"}},\"required\":[\"name\",\"hours\"],\"title\":\"Activity\",\"type\":\"object\"}},\"additionalProperties\":false,\"properties\":{\"city\":{\"description\":\"The city to visit.\",\"type\":\"string\"},\"season\":{\"enum\":[\"spring\",\"summer\",\"autumn\",\"winter\"],\"type\":\"string\"},\"activities\":{\"description\":\"Three things to do.\",\"items\":{\"$ref\":\"#/$defs/Activity\"},\"maxItems\":3,\"minItems\":3,\"type\":\"array\"},\"days\":{\"description\":\"How many days to stay.\",\"maximum\":14,\"minimum\":1,\"type\":\"integer\"},\"note\":{\"type\":\"string\"}},\"required\":[\"city\",\"season\",\"activities\",\"days\"],\"title\":\"Trip\",\"type\":\"object\"}"
                        }
                      ]
                    }
                  ],
                  "stream": true,
                  "stream_options": {
                    "include_usage": true
                  },
                  "response_format": {
                    "type": "json_schema",
                    "json_schema": {
                      "name": "Trip",
                      "strict": true,
                      "schema": {
                        "$defs": {
                          "Activity": {
                            "additionalProperties": false,
                            "properties": {
                              "name": {
                                "type": "string"
                              },
                              "hours": {
                                "description": "How many hours it takes.",
                                "maximum": 12,
                                "minimum": 1,
                                "type": "integer"
                              }
                            },
                            "required": [
                              "name",
                              "hours"
                            ],
                            "title": "Activity",
                            "type": "object"
                          }
                        },
                        "additionalProperties": false,
                        "properties": {
                          "city": {
                            "description": "The city to visit.",
                            "type": "string"
                          },
                          "season": {
                            "enum": [
                              "spring",
                              "summer",
                              "autumn",
                              "winter"
                            ],
                            "type": "string"
                          },
                          "activities": {
                            "description": "Three things to do.",
                            "items": {
                              "$ref": "#/$defs/Activity"
                            },
                            "maxItems": 3,
                            "minItems": 3,
                            "type": "array"
                          },
                          "days": {
                            "description": "How many days to stay.",
                            "maximum": 14,
                            "minimum": 1,
                            "type": "integer"
                          },
                          "note": {
                            "anyOf": [
                              {
                                "type": "string"
                              },
                              {
                                "type": "null"
                              }
                            ]
                          }
                        },
                        "required": [
                          "city",
                          "season",
                          "activities",
                          "days",
                          "note"
                        ],
                        "title": "Trip",
                        "type": "object"
                      }
                    }
                  },
                  "reasoning_effort": "none",
                  "max_tokens": 1500
                }

                transcript
                prompt ["Plan a short trip to Lisbon."] metadata: {}
                response [{"activities":[{"hours":3,"name":"Explore Alfama and Belém Tower"},{"hours":4,"name":"Take a boat tour up the Tagus River"},{"hours":2,"name":"Wander through LX Factory and São Carlos Square"}],"city":"Lisbon","days":3,"note":"Best for enjoying vibrant outdoor cafes and warm sunny weather.","season":"summer"}] metadata: {"finishReason":"stop","model":"qwen3.5:4b","responseID":"chatcmpl-294"}

                usage
                input 211 cached 0, output 140 reasoning 0, metadata: {}
                """#
            }
        }

        @Test func `an answer that reasons keeps its reasoning`() async throws {
            let exchange = try await ExactExchange(replaying: .ollamaReasoning)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "qwen3:0.6b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What is 12 plus 30? Reply with the number only."
                    }
                  ],
                  "stream": true,
                  "stream_options": {
                    "include_usage": true
                  },
                  "max_tokens": 1500
                }

                transcript
                prompt ["What is 12 plus 30? Reply with the number only."] metadata: {}
                reasoning ["Okay, let's see. The question is asking, \"What is 12 plus 30?\" and they want the answer in numbers only. Hmm, so first, I need to add 12 and 30. Let me think... 12 plus 30. Well, adding them together... let's break it down. 12 is two tens and zero ones. 30 is three tens and zero ones. Adding the tens first: 2 + 3 is 5. Then the ones: 0 + 0 is 0. So altogether, it's 50. That makes sense. Wait, but maybe I should check again. 12 plus 30, adding the ones first: 12 + 30. So if I add 12 to 30, it's 42? Wait, no, that's not right. Wait, no, 12 plus 30. Let me do it in another way. 12 + 30. Let's think of 12 + 30 as (10 + 2) + (30). So that's 10 + 30 which is 40, plus 2 is 42. Oh, so that's 42. Wait, but earlier I thought it was 50. Which is correct? Wait, no, I think I made a mistake here. If 12 plus 30, adding the ones first: 12 + 30. So the ones are 12 and 30. So 12 + 30. So the ones are 12 and 30. Wait, no, the ones are 2 and 0. So 2 + 0 = 2. Then the tens: 1 + 3 = 4. So total is 42. Oh my goodness, I confused the tens and ones. So 12 plus 30 is 42. So why did I get confused before? Oh right, when I first thought, I thought of 12 as two tens and zero ones, and 30 as three tens and zero ones. Then adding the tens: 2 + 3 = 5, and the ones: 0 + 0 = 0. So 50. But that's wrong because 12 is 10 + 2 and 30 is 30. So adding them gives 40 + 2 = 42. So the correct answer is 42. So why did I think it was 50 before? Because I thought of 12 as two tens and zero ones, and 30 as three tens and zero ones, so adding the tens gives 5, and the ones gives 0. But that's incorrect because when you have 12 + 30, the ones are 2 (from 12) and 0 (from 30), so adding them gives 2. So the correct answer is 42. I must have made a mistake in the addition process earlier. So the final answer is 42.\n"] metadata: {"model":"qwen3:0.6b","reasoningOrigin":"openai-compatible/ollama"} signature: nil
                response ["42"] metadata: {"finishReason":"stop","model":"qwen3:0.6b","responseID":"chatcmpl-242"}

                usage
                input 26 cached 7, output 676 reasoning 0, metadata: {}

                last snapshot
                "42" ["reasoning [\"Okay, let\'s see. The question is asking, \\\"What is 12 plus 30?\\\" and they want the answer in numbers only. Hmm, so first, I need to add 12 and 30. Let me think... 12 plus 30. Well, adding them together... let\'s break it down. 12 is two tens and zero ones. 30 is three tens and zero ones. Adding the tens first: 2 + 3 is 5. Then the ones: 0 + 0 is 0. So altogether, it\'s 50. That makes sense. Wait, but maybe I should check again. 12 plus 30, adding the ones first: 12 + 30. So if I add 12 to 30, it\'s 42? Wait, no, that\'s not right. Wait, no, 12 plus 30. Let me do it in another way. 12 + 30. Let\'s think of 12 + 30 as (10 + 2) + (30). So that\'s 10 + 30 which is 40, plus 2 is 42. Oh, so that\'s 42. Wait, but earlier I thought it was 50. Which is correct? Wait, no, I think I made a mistake here. If 12 plus 30, adding the ones first: 12 + 30. So the ones are 12 and 30. So 12 + 30. So the ones are 12 and 30. Wait, no, the ones are 2 and 0. So 2 + 0 = 2. Then the tens: 1 + 3 = 4. So total is 42. Oh my goodness, I confused the tens and ones. So 12 plus 30 is 42. So why did I get confused before? Oh right, when I first thought, I thought of 12 as two tens and zero ones, and 30 as three tens and zero ones. Then adding the tens: 2 + 3 = 5, and the ones: 0 + 0 = 0. So 50. But that\'s wrong because 12 is 10 + 2 and 30 is 30. So adding them gives 40 + 2 = 42. So the correct answer is 42. So why did I think it was 50 before? Because I thought of 12 as two tens and zero ones, and 30 as three tens and zero ones, so adding the tens gives 5, and the ones gives 0. But that\'s incorrect because when you have 12 + 30, the ones are 2 (from 12) and 0 (from 30), so adding them gives 2. So the correct answer is 42. I must have made a mistake in the addition process earlier. So the final answer is 42.\\n\"] metadata: {\"model\":\"qwen3:0.6b\",\"reasoningOrigin\":\"openai-compatible/ollama\"} signature: nil", "response [\"42\"] metadata: {\"finishReason\":\"stop\",\"model\":\"qwen3:0.6b\",\"responseID\":\"chatcmpl-242\"}"]
                """#
            }
        }

        @Test func `a model the server doesn't have throws with the code not found`() async throws {
            let exchange = try await ExactExchange(replaying: .ollamaUnknownModel)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "no-such-model:1b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Hi"
                    }
                  ],
                  "stream": true,
                  "stream_options": {
                    "include_usage": true
                  }
                }

                error
                OpenAICompatibleError(providerName: "Ollama", status: Optional(404), message: "model \'no-such-model:1b\' not found", code: not_found, errorType: Optional(not_found_error), parameter: nil, requestID: nil, retryAfter: nil, isQuotaExhausted: false)
                """#
            }
        }
    }
}
