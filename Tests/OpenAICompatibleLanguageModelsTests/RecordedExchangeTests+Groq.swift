import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing

extension RecordedExchangeTests {
    @Suite("Groq")
    struct Groq {
        @Test func `a real answer reads as Groq sent it, with its reasoning`() async throws {
            let exchange = try await ExactExchange(replaying: .groqText)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "openai/gpt-oss-20b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Name one color of the sea."
                    }
                  ],
                  "stream": true,
                  "reasoning_effort": "low",
                  "max_completion_tokens": 300
                }

                transcript
                prompt ["Name one color of the sea."] metadata: {}
                reasoning ["We need answer: \"Blue\" is one color."] metadata: {"model":"openai/gpt-oss-20b","reasoningOrigin":"openai-compatible/groq"} signature: nil
                response ["Blue."] metadata: {"finishReason":"stop","model":"openai/gpt-oss-20b","provider":"Groq","requestID":"req_015qz8ld8tvjhzmt437ut7mv81","responseID":"chatcmpl-6c3790f0-66ec-353e-435e-79cbf58b8904"}

                usage
                input 78 cached 0, output 23 reasoning 12, metadata: {}

                last snapshot
                "Blue." ["reasoning [\"We need answer: \\\"Blue\\\" is one color.\"] metadata: {\"model\":\"openai/gpt-oss-20b\",\"reasoningOrigin\":\"openai-compatible/groq\"} signature: nil", "response [\"Blue.\"] metadata: {\"finishReason\":\"stop\",\"model\":\"openai/gpt-oss-20b\",\"provider\":\"Groq\",\"requestID\":\"req_015qz8ld8tvjhzmt437ut7mv81\",\"responseID\":\"chatcmpl-6c3790f0-66ec-353e-435e-79cbf58b8904\"}"]
                """#
            }
        }

        @Test func `a call's reasoning goes back with it, and Groq answers the outputs of two rounds`() async throws {
            let exchange = try await ExactExchange(replaying: .groqTools)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "openai/gpt-oss-20b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence."
                    }
                  ],
                  "stream": true,
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
                  "reasoning_effort": "low",
                  "max_completion_tokens": 800
                }

                request 2
                {
                  "model": "openai/gpt-oss-20b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence."
                    },
                    {
                      "role": "assistant",
                      "reasoning": "Need to call getWeather twice.",
                      "tool_calls": [
                        {
                          "id": "fc_421300e5-43d6-07d8-8f56-42403ff37060",
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
                      "tool_call_id": "fc_421300e5-43d6-07d8-8f56-42403ff37060",
                      "content": "It is 17 degrees in Lisbon."
                    }
                  ],
                  "stream": true,
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
                  "reasoning_effort": "low",
                  "max_completion_tokens": 800
                }

                request 3
                {
                  "model": "openai/gpt-oss-20b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence."
                    },
                    {
                      "role": "assistant",
                      "reasoning": "Need to call getWeather twice.",
                      "tool_calls": [
                        {
                          "id": "fc_421300e5-43d6-07d8-8f56-42403ff37060",
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
                      "tool_call_id": "fc_421300e5-43d6-07d8-8f56-42403ff37060",
                      "content": "It is 17 degrees in Lisbon."
                    },
                    {
                      "role": "assistant",
                      "tool_calls": [
                        {
                          "id": "fc_4abc1963-0109-fc37-9934-16d43a8da737",
                          "type": "function",
                          "function": {
                            "name": "getWeather",
                            "arguments": "{\"city\":\"Porto\"}"
                          }
                        }
                      ]
                    },
                    {
                      "role": "tool",
                      "tool_call_id": "fc_4abc1963-0109-fc37-9934-16d43a8da737",
                      "content": "It is 17 degrees in Porto."
                    }
                  ],
                  "stream": true,
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
                  "reasoning_effort": "low",
                  "max_completion_tokens": 800
                }

                transcript
                instructions [] tools: ["getWeather"]
                prompt ["What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence."] metadata: {}
                reasoning ["Need to call getWeather twice."] metadata: {"model":"openai/gpt-oss-20b","reasoningOrigin":"openai-compatible/groq"} signature: nil
                toolCalls ["fc_421300e5-43d6-07d8-8f56-42403ff37060 getWeather {\"city\":\"Lisbon\"} metadata: {\"finishReason\":\"tool_calls\",\"model\":\"openai/gpt-oss-20b\",\"provider\":\"Groq\",\"requestID\":\"req_0190bp78kxg94b5obylemwhfjv\",\"responseID\":\"chatcmpl-98200e69-bdf9-db1f-fa92-a7d5ffd89e8c\"}"]
                toolOutput fc_421300e5-43d6-07d8-8f56-42403ff37060 getWeather ["It is 17 degrees in Lisbon."]
                toolCalls ["fc_4abc1963-0109-fc37-9934-16d43a8da737 getWeather {\"city\":\"Porto\"} metadata: {\"finishReason\":\"tool_calls\",\"model\":\"openai/gpt-oss-20b\",\"provider\":\"Groq\",\"requestID\":\"req_01ibnie42qgnnk437sxohh6goi\",\"responseID\":\"chatcmpl-8a983ce6-bbb9-c610-dcdc-f3666bfdb862\"}"]
                toolOutput fc_4abc1963-0109-fc37-9934-16d43a8da737 getWeather ["It is 17 degrees in Porto."]
                response ["The temperature is 17 °C in both Lisbon and Porto."] metadata: {"finishReason":"stop","model":"openai/gpt-oss-20b","provider":"Groq","requestID":"req_01jo59m8yl9g86phb3gd7gx6re","responseID":"chatcmpl-bc66169d-57cd-0951-7f3e-4c47cb53713e"}

                usage
                input 238 cached 0, output 17 reasoning 0, metadata: {}
                """#
            }
        }

        @Test func `a real guided answer decodes`() async throws {
            let exchange = try await ExactExchange(replaying: .groqGuided)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "openai/gpt-oss-20b",
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
                  "reasoning_effort": "low",
                  "max_completion_tokens": 1500
                }

                transcript
                prompt ["Plan a short trip to Lisbon."] metadata: {}
                reasoning ["Need JSON matching schema. Provide activities 3 with name and hours. Let's choose spring, 2 days."] metadata: {"model":"openai/gpt-oss-20b","reasoningOrigin":"openai-compatible/groq"} signature: nil
                response [{"activities":[{"hours":3,"name":"Explore Belém Tower and Jerónimos Monastery"},{"hours":4,"name":"Stroll through Alfama district and visit São Jorge Castle"},{"hours":1,"name":"Taste pastéis de nata at Pastéis de Belém"}],"city":"Lisbon","days":2,"note":"Enjoy the mild weather and historic sights","season":"spring"}] metadata: {"finishReason":"stop","model":"openai/gpt-oss-20b","provider":"Groq","requestID":"req_01nmsodw4x2ai9ocuyybln1t4v","responseID":"chatcmpl-76a4f450-377b-11b1-4da0-dab8b41b206a"}

                usage
                input 476 cached 0, output 116 reasoning 23, metadata: {}
                """#
            }
        }

        @Test func `an answer at a moderate effort keeps its reasoning`() async throws {
            let exchange = try await ExactExchange(replaying: .groqReasoning)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "openai/gpt-oss-20b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What is 17 times 23? Think it through."
                    }
                  ],
                  "stream": true,
                  "reasoning_effort": "medium",
                  "max_completion_tokens": 2000
                }

                transcript
                prompt ["What is 17 times 23? Think it through."] metadata: {}
                reasoning ["The user asks: \"What is 17 times 23? Think it through.\" So we need to compute 17*23. 17*20=340; 17*3=51; total 391. So answer is 391. But maybe the user expects explanation. Let's think: 17 times 23 = 391. Provide reasoning."] metadata: {"model":"openai/gpt-oss-20b","reasoningOrigin":"openai-compatible/groq"} signature: nil
                response ["17 × 23 = 391\n\n**How to see it:**\n\n- 17 × 20 = 340  \n- 17 × 3 = 51  \n- Add them together: 340 + 51 = **391**"] metadata: {"finishReason":"stop","model":"openai/gpt-oss-20b","provider":"Groq","requestID":"req_016qim5yjxl1qfg5rgli8biv4e","responseID":"chatcmpl-e4af15c4-69ec-8096-d6cb-6a2c43bfa17c"}

                usage
                input 83 cached 0, output 136 reasoning 74, metadata: {}

                last snapshot
                "17 × 23 = 391\n\n**How to see it:**\n\n- 17 × 20 = 340  \n- 17 × 3 = 51  \n- Add them together: 340 + 51 = **391**" ["reasoning [\"The user asks: \\\"What is 17 times 23? Think it through.\\\" So we need to compute 17*23. 17*20=340; 17*3=51; total 391. So answer is 391. But maybe the user expects explanation. Let\'s think: 17 times 23 = 391. Provide reasoning.\"] metadata: {\"model\":\"openai/gpt-oss-20b\",\"reasoningOrigin\":\"openai-compatible/groq\"} signature: nil", "response [\"17 × 23 = 391\\n\\n**How to see it:**\\n\\n- 17 × 20 = 340  \\n- 17 × 3 = 51  \\n- Add them together: 340 + 51 = **391**\"] metadata: {\"finishReason\":\"stop\",\"model\":\"openai/gpt-oss-20b\",\"provider\":\"Groq\",\"requestID\":\"req_016qim5yjxl1qfg5rgli8biv4e\",\"responseID\":\"chatcmpl-e4af15c4-69ec-8096-d6cb-6a2c43bfa17c\"}"]
                """#
            }
        }

        @Test func `a key Groq refuses throws its words and code`() async throws {
            let exchange = try await ExactExchange(replaying: .groqRefusedKey)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                """
                request 1
                {
                  "model": "openai/gpt-oss-20b",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Hi"
                    }
                  ],
                  "stream": true,
                  "reasoning_effort": "low"
                }

                error
                OpenAICompatibleError(providerName: "Groq", status: Optional(401), message: "Invalid API Key", code: invalid_api_key, errorType: Optional(invalid_request_error), parameter: nil, requestID: Optional("req_01gr51bg2v2d7yoizkz847m9rr"), retryAfter: nil, isQuotaExhausted: false)
                """
            }
        }

        // The request's prompt is 12,000 words, so only the error is compared.
        @Test func `a prompt over the tokens a minute throws the module's error with Groq's wait, not a rate limit`() async throws {
            let exchange = try await ExactExchange(replaying: .groqTooLarge)

            assertInlineSnapshot(of: exchange.error ?? "nil", as: .lines) {
                """
                OpenAICompatibleError(providerName: "Groq", status: Optional(413), message: "Request too large for model `openai/gpt-oss-20b` in organization `org_018hzsa9tcmsaferg6xe4zh3mf` service tier `on_demand` on tokens per minute (TPM): Limit 8000, Requested 12086, please reduce your message size and try again. Need more tokens? Upgrade to Dev Tier today at https://console.groq.com/settings/billing", code: rate_limit_exceeded, errorType: Optional(tokens), parameter: nil, requestID: Optional("req_01ah5r5u7xeqqy4rygxa2bg6zn"), retryAfter: Optional(31.0 seconds), isQuotaExhausted: false)
                """
            }
        }
    }
}
