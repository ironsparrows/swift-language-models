import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing

extension RecordedExchangeTests {
    @Suite("Gemini")
    struct Gemini {
        @Test func `a real answer reads as Gemini sent it`() async throws {
            let exchange = try await ExactExchange(replaying: .geminiText)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "gemini-3.1-flash-lite",
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
                  "max_tokens": 300
                }

                transcript
                prompt ["Name one color of the sea."] metadata: {}
                response ["Blue"] metadata: {"finishReason":"stop","model":"gemini-3.1-flash-lite","provider":"Google AI Studio","responseID":"CUzWRFY6bCGlgpa13cm9eh"}
                reasoning [] metadata: {"model":"gemini-3.1-flash-lite","reasoningOrigin":"openai-compatible/gemini"} signature: "EnIKcAFpFH0T4mq4RVOBWkbjE1VpSTOTvkD97HK9PdsuRQHQ0Qn+VE1/4XdBUDbPxWfyJKRBP77BEm91xFHO5h68FAW/wLpuQiXep2TEV+++OwuJTs5aeLOF/Sg4Eyqto2150/dxk5roUYiw78OS/swvlx4="

                usage
                input 8 cached 0, output 1 reasoning 0, metadata: {}

                last snapshot
                "Blue" ["response [\"Blue\"] metadata: {\"finishReason\":\"stop\",\"model\":\"gemini-3.1-flash-lite\",\"provider\":\"Google AI Studio\",\"responseID\":\"CUzWRFY6bCGlgpa13cm9eh\"}", "reasoning [] metadata: {\"model\":\"gemini-3.1-flash-lite\",\"reasoningOrigin\":\"openai-compatible/gemini\"} signature: \"EnIKcAFpFH0T4mq4RVOBWkbjE1VpSTOTvkD97HK9PdsuRQHQ0Qn+VE1/4XdBUDbPxWfyJKRBP77BEm91xFHO5h68FAW/wLpuQiXep2TEV+++OwuJTs5aeLOF/Sg4Eyqto2150/dxk5roUYiw78OS/swvlx4=\""]
                """#
            }
        }

        @Test func `parallel calls go back with the first call's signature only, and Gemini answers their outputs`() async throws {
            let exchange = try await ExactExchange(replaying: .geminiTools)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "gemini-3.1-flash-lite",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence."
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
                  "max_tokens": 800
                }

                request 2
                {
                  "model": "gemini-3.1-flash-lite",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence."
                    },
                    {
                      "role": "assistant",
                      "tool_calls": [
                        {
                          "id": "call_06216130476596394483",
                          "type": "function",
                          "function": {
                            "name": "getWeather",
                            "arguments": "{\"city\":\"Lisbon\"}"
                          },
                          "extra_content": {
                            "google": {
                              "thought_signature": "EnIKcAFpFH0TcCeqfKJmpjuQpCdaWbHGCbskyLboVUx7sSMR1SsB63j8+VI4mdw/ETRS+S9Cg0evt95qDwZG0+K+QQUbS8ZZPdpNHP62FV96ryjvfFOJPb8vXgfHl/DvHUYPZJdgYz1bf0S/FTmVdyISKWo="
                            }
                          }
                        },
                        {
                          "id": "call_94725008544535761356",
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
                      "tool_call_id": "call_06216130476596394483",
                      "content": "It is 17 degrees in Lisbon."
                    },
                    {
                      "role": "tool",
                      "tool_call_id": "call_94725008544535761356",
                      "content": "It is 17 degrees in Porto."
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
                  "max_tokens": 800
                }

                transcript
                instructions [] tools: ["getWeather"]
                prompt ["What's the temperature in Lisbon and in Porto? Call the tool for both cities at once, then answer in one sentence."] metadata: {}
                toolCalls ["call_06216130476596394483 getWeather {\"city\":\"Lisbon\"} metadata: {\"finishReason\":\"stop\",\"model\":\"gemini-3.1-flash-lite\",\"provider\":\"Google AI Studio\",\"responseID\":\"435AnFdzEs9obB2me8Jw8yY\"}", "call_94725008544535761356 getWeather {\"city\":\"Porto\"} metadata: {}"]
                reasoning [] metadata: {"model":"gemini-3.1-flash-lite","reasoningOrigin":"openai-compatible/gemini"} signature: "EnIKcAFpFH0TcCeqfKJmpjuQpCdaWbHGCbskyLboVUx7sSMR1SsB63j8+VI4mdw/ETRS+S9Cg0evt95qDwZG0+K+QQUbS8ZZPdpNHP62FV96ryjvfFOJPb8vXgfHl/DvHUYPZJdgYz1bf0S/FTmVdyISKWo="
                toolOutput call_06216130476596394483 getWeather ["It is 17 degrees in Lisbon."]
                toolOutput call_94725008544535761356 getWeather ["It is 17 degrees in Porto."]
                response ["The temperature is 17 degrees in both Lisbon and Porto."] metadata: {"finishReason":"stop","model":"gemini-3.1-flash-lite","provider":"Google AI Studio","responseID":"H8ZKYk689yB9JwuxXR4FpL"}
                reasoning [] metadata: {"model":"gemini-3.1-flash-lite","reasoningOrigin":"openai-compatible/gemini"} signature: "EnIKcAFpFH0TuPDXT2IETuo3JwoijYjaAq9DmQaLI+o7GfAqwDgh+fUoN4O8zfi8UKq8aPKB8PPGFOZCTn3HfgBpZbKlBtTaF++j23n9CVdBds5KhlKSevpFsQ04SVSf9LoTMJSA8yKl9i9vBMN3xuTLvgc="

                usage
                input 165 cached 0, output 13 reasoning 0, metadata: {}
                """#
            }
        }

        @Test func `a real guided answer decodes`() async throws {
            let exchange = try await ExactExchange(replaying: .geminiGuided)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "gemini-3.1-flash-lite",
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
                  "max_tokens": 1000
                }

                transcript
                prompt ["Plan a short trip to Lisbon."] metadata: {}
                response [{"activities":[{"hours":3,"name":"Explore Belém Tower"},{"hours":2,"name":"Ride Tram 28 through Alfama"},{"hours":4,"name":"Visit Jerónimos Monastery"}],"city":"Lisbon","days":3,"note":"Don't forget to try the local pastéis de nata.","season":"spring"}] metadata: {"finishReason":"stop","model":"gemini-3.1-flash-lite","provider":"Google AI Studio","responseID":"SqkK2DituwOEXlDiJ3mv9Sf"}
                reasoning [] metadata: {"model":"gemini-3.1-flash-lite","reasoningOrigin":"openai-compatible/gemini"} signature: "EnIKcAFpFH0TVpRp89Xg/804BtU1zd8Iho/kpznk+9d3Y5ktD2LkNJjV5uGkypProh1T9IsLpPS+Adbfmw9dzqlYiKOblKL5OUToAr5HzOjjRuAwMj3boY3l1mLQRCAVqeHPKDdhKFkcWwNp7I3EAD+kKVc="

                usage
                input 207 cached 0, output 133 reasoning 0, metadata: {}
                """#
            }
        }

        @Test func `an answer that reasons hard keeps Gemini's signature, and counts the reasoning Gemini leaves out of the completion`()
            async throws
        {
            let exchange = try await ExactExchange(replaying: .geminiReasoning)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                #"""
                request 1
                {
                  "model": "gemini-3.1-flash-lite",
                  "messages": [
                    {
                      "role": "user",
                      "content": "What is 17 times 23? Think it through."
                    }
                  ],
                  "stream": true,
                  "stream_options": {
                    "include_usage": true
                  },
                  "reasoning_effort": "high",
                  "max_tokens": 1200
                }

                transcript
                prompt ["What is 17 times 23? Think it through."] metadata: {}
                response ["To calculate **17 × 23**, there are a couple of efficient ways to think about it.\n\n### Method 1: The \"Difference of Squares\" Pattern\nThis is the fastest mental math method. Notice that both numbers are the same distance away from 20 (17 is 3 less than 20, and 23 is 3 more than 20).\n\nWe can rewrite the problem as:\n**(20 - 3) × (20 + 3)**\n\nAccording to the algebraic formula $(a - b)(a + b) = a^2 - b^2$:\n1. Square the 20: **20² = 400**\n2. Square the 3: **3² = 9**\n3. Subtract the second result from the first: **400 - 9 = 391**\n\n***\n\n### Method 2: Distributive Property\nIf you prefer breaking the numbers down, you can multiply 17 by 20 and then 17 by 3:\n\n1. **17 × 20 = 340**\n2. **17 × 3 = 51**\n3. Add them together: **340 + 51 = 391**\n\nBoth methods confirm the answer is **391**."] metadata: {"finishReason":"stop","model":"gemini-3.1-flash-lite","provider":"Google AI Studio","responseID":"djN7Rpdyqp0t3J95NjPGRNS"}
                reasoning [] metadata: {"model":"gemini-3.1-flash-lite","reasoningOrigin":"openai-compatible/gemini"} signature: "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"

                usage
                input 15 cached 0, output 1169 reasoning 879, metadata: {}

                last snapshot
                "To calculate **17 × 23**, there are a couple of efficient ways to think about it.\n\n### Method 1: The \"Difference of Squares\" Pattern\nThis is the fastest mental math method. Notice that both numbers are the same distance away from 20 (17 is 3 less than 20, and 23 is 3 more than 20).\n\nWe can rewrite the problem as:\n**(20 - 3) × (20 + 3)**\n\nAccording to the algebraic formula $(a - b)(a + b) = a^2 - b^2$:\n1. Square the 20: **20² = 400**\n2. Square the 3: **3² = 9**\n3. Subtract the second result from the first: **400 - 9 = 391**\n\n***\n\n### Method 2: Distributive Property\nIf you prefer breaking the numbers down, you can multiply 17 by 20 and then 17 by 3:\n\n1. **17 × 20 = 340**\n2. **17 × 3 = 51**\n3. Add them together: **340 + 51 = 391**\n\nBoth methods confirm the answer is **391**." ["response [\"To calculate **17 × 23**, there are a couple of efficient ways to think about it.\\n\\n### Method 1: The \\\"Difference of Squares\\\" Pattern\\nThis is the fastest mental math method. Notice that both numbers are the same distance away from 20 (17 is 3 less than 20, and 23 is 3 more than 20).\\n\\nWe can rewrite the problem as:\\n**(20 - 3) × (20 + 3)**\\n\\nAccording to the algebraic formula $(a - b)(a + b) = a^2 - b^2$:\\n1. Square the 20: **20² = 400**\\n2. Square the 3: **3² = 9**\\n3. Subtract the second result from the first: **400 - 9 = 391**\\n\\n***\\n\\n### Method 2: Distributive Property\\nIf you prefer breaking the numbers down, you can multiply 17 by 20 and then 17 by 3:\\n\\n1. **17 × 20 = 340**\\n2. **17 × 3 = 51**\\n3. Add them together: **340 + 51 = 391**\\n\\nBoth methods confirm the answer is **391**.\"] metadata: {\"finishReason\":\"stop\",\"model\":\"gemini-3.1-flash-lite\",\"provider\":\"Google AI Studio\",\"responseID\":\"djN7Rpdyqp0t3J95NjPGRNS\"}", "reasoning [] metadata: {\"model\":\"gemini-3.1-flash-lite\",\"reasoningOrigin\":\"openai-compatible/gemini\"} signature: \"EsoYCscYAWkUfRMhfgRzSJtWnZes1gQhQfnzczDkosY0gmhyGW229X2XcpTZKdaY4JKBr87qHNlx6I/gaYEAv5XR+YPtop3yT3WK4QWmtG2ER0c/8R+35IEQea3pomaG/l5AwdiXjUhd81ZHawC1lmLckc0RNWGhifIGGl4YEibVuRhzkGij9kM1SY2QbAyp05OPTidy7AbbfVs+q0WD/wdtA/triN2t6D8xNT5mnoXBS7SmHscvrgJ06APRhBj3kHaV/LoZamojcUj2EhtqSbDrOc/5xRPMTrDhGLBN4Y46rBH6aZXMlb785+1Pv9ZpvAWK29KQcJAegJwPvSSKEzkZ79uV3rlf5CdvrGYlyls3CGvL3CHs+T5oBDrwex8nNugRi2k0Sm6tBlywEVKUgwa2g8cG4F4635UXUS6hoP+O00wZwZac8qSIijo2ObHFZlnGI9OK6O3O3nRtBLEqiOakVnXrzFhmTKCr7hqIe0buom6smWzwoBBcGomZrXKILCtAGr4f1BpcAOBeFQtL/d2LIkQdzADyXeG7XD68fBbfqWFi5t3+aGApqWS04oKw0mxKCVUcJNMWrRwddCqRfOikyO0MVeeKzyfoXArZRz0P17HDJwTHANrZVfpd73Yj22vTESV35voKgqX3TEylNZlRkShUC2jipZwARidCx9ux2bx9asMz+Gmmom1zRv3vb6KNHq6dCJ0u95vcTcit175BufFcjg7SCzqYoB3w3LskEDojKjWHFO1ruiT9Y2EoMMNjhtnuW5KOf+5e//gtMPb2jtKEL6i5SFNIw6+qDNopIQqxBoC3K4R46pchuvlG0BlYUR6ibzFR4j+PqYIOM9Ju+YD6tTuZzgrwxT54hb+YbvwWDbPGNglzv/WH7TfF4LnvRHLpFFCg13k9lCQZEOsmqfJw5YhxwwXjWAU6rsncFwwkDmUJQpLxYJVWohJsEjBvuu82a/O70bt2bMJys6pQ6c8cqOTxNVKhhQ1BZ9a4YdE+35kBO7Up97WO4QElhJ3/+r7msAAKm1LPCPCaaE25L/UysnjE+016vtE9OiXVOEr/+IC/56MUZRrEQ7CnMIbpQS/joGp42K5pFxeRDbe7QrR2BJ95w1zycp5OSYHdP8WUCcS5haGq9OPylnSFc7rVpgb2G8PgXTJWwz2jCraUZp/1hLMWVS9DX31wdcf6XSmalWQCRW+HIIajx8S03yEhx84WTKfPfHLoVHSkrFaGvReYqdb3MSguQZqA91oTZaZIjfZBxIP2x3BFxWPUMLdC+mcCWL612j+9qAbZcCQK6aWWAaf1OOzMhmnUl1HZutoacIm9h3kzDdfXohmauy02mC7j7V/DekzOC4NCDJ4empWEbfL/C3kW0F45U1jR0Vu9OkByNAFg4TdhuIOsUsVTaSVYecAtqDNAkicX/SptmtJAXG2o2MnrPS1bFusEYL+2n+2X+BdgKMI7UQihEEhcB4zvR2f+UQaswBLe3Rcg3oJ3m/YS0od3GICKolplE3Uz4pRXAJnR4W+qVozrVr8YkF338+4Gg78vCcjcZzL6+AzuBgAd8cQFOwhRng92ZtB7sC7/Ypd3at/YEHRPfuypN1BDVkefkPUcxyo9P2nmS7tWKht+GRryNXEnK1RDRVQ/B5/tCsnuuD7XB4Ue4dKv8ublEVaZQWshkEE7DdCEENVwauepRoVguJpZbC4l81ZetG4+lxOMLspMTc00DcEPeXVd57TE43lerP3wlyohxCPdPClrwgiaHktdCSVtiYhgndfQa6X67ZxMCinqt66Nye3FC0zX439cwcsgkju7RirzNTjjwg1QHyLceWSaqfvEbsnrfRux2l525MDCT3R86/31WLk2Kp9rnevaku2gyRtMjaLGBUfH4yn98BHg8E2NlAmHkwOmr1kg5ERh2buTDQb0zEXgfXKf9YRctuIE5GLsxC7Y+DzQ4OCmVAtImFkg7a0Sk4BY0825N1Tci2TenDHVche3wfZOe3CxFKDoFsifRlKS49xb+gTNmv6HMd1ceKni0Z+WVtMrVaEKW6Ylo7qM9xk3/V2VIGmne5boZoSWa0oqqw4DXhVsupv8b9WFAnYa0zIO/QUz1lbDF/7eoD9ieyjAXphjjxOaKupdy3iB89yoWi4SDRn4CPYmzhFI47I4Y6Jh6EaX6Gl2o6f3hE7ZGqykTbzuZfB2Tn505eGMvdp8UyoU7Am30LUqd8fRqxWg9oMBOnGJIc3NAoIQclouQ5tG0WGPnMFyi+eLd8QGHsMOF6fd+FfFn0F5UFBmnuJbGqoXMJDZxLFwfDFRMsMTe2himvObAFvm0JfHfo1Y/R1H5XKTm3d9InEUQwnTcKkKY7FxBXGWwazZG+Ry33FkrOgG9pLBbya609zensXyH9NlSUXWlmDMBR7ERaNww/zQOT/y9j8O5OXrEV7JIb4rig7TxmlCYcJFDaRO1jtG/pfZJlkG1p4ejzZjjkGtghVA8DwetNqGY47HsN+gh72mnXK0wP/zuDdEAEtP3hUVY1Bibnyiv379e9ZkFDGOeR7SK4F6bEBEuIlsUqmNAhH+AwJP10T7Uyl6wF1vkqat1bGoJ8WV8BD/iyMlacqzd5DC/kMe8dVYo2k11o7dQkGa6KnWBMj2VEZrsXF8LqNedG5TjeV3fw8xMmKIG7UxOR/QeEUNxCq0mJq8Nui9pJtQsH5q9ook6Wd1gRMJjqXjETmI5owId3N7//X7xwYpQ7GK1xtP1yFuNEtSeW+LR/F0stR8ccP0dSMfqCx2w/0tcG/48dXp7FIOjPqalS9cVf16MMu4Sj5G+jW8YwkrlzQ47NcyrTNqwNtfoe2bHI5dXB+yLW7uQlE8EtFFJsdj1BXJ+pJxDYMNOcoVe+0+5K3VWPPEm7nvCzTHDvgpvuhv161U8JwjrRCBCngG2kNz5glUGr/JNm1LyG4EHuq41Rd6M7b2T+TX/bDRN6h+oF98liy7ogoW0LRj6/QO9Dj4zMBPP90H3tZUDIjx5jCcrA1AhrWOdZgvjFob1ho9VVY3EZOUWNNv1Z6uEOeANO3Jrh8B/56Ynu+lpfDH1GcUgZQG9vRfgl3kbw0SVnKgrX3rc1wYGMFt9bIDls5JQdRnSpVgb1Z6ZOiJftDgJK26V2zJ630uQwjOPwyXf7Y4bRB7SOQemii+gnRwcINwzrBzZ5MN8nd1cQi1xHfJ3PysLrqDnxfzvo3XlXrswZyxP4KE/mPtIP9V7Ndl7KZTC9PkDtMUkUdld4E91829S2L/wD/gOoqSB/pvmvzDcI9RzNApF40zl/2kPGy8Vgxz08sHNC6JzMGCPonYy/WEmetFub1WoL9ILN4oHHztsQoxYzxB/S95yBz4Mjf030vmIRU2vAVoqFD6KUuilVv505mdiz/k+GhV8oO4CrVI80oqzb56Pcnt63IE3Dy/pPXlRwOEjAlCA1jWPWJ/3bkhbjkFWyUcaZ8y5apx+q5MagGdZzh10b25hFd+8oOiA6nIr+cdqSwYk7Vk7UDtHsNMq5Xhzeb6nYmBiMl2Q9RBxa+2DKDEbstNFDx5c52r69UMNRClEE22uSvPDHdejVnpNwHHBGRv+4xisNJ5CnUiYiGfFg0N7VSqCn+/HMUh8HM+9u1LTu08g0YPZI2tB69CYoyt7q1OFUbQEbH38ISmNPMWtNpEYmiinmMlQV9TZ4eSreVKs9fUhHIkknRCirrUUlchMNxGDUKdNQz7nU23PDCdoHsV6CIz8RzuVIb0EP9JkgeMoobCQUFsnZCciNLmLzY8tBaREeBnlQXlqJ/eAfeuWWnKrZNBUAMa77XjtrkYMqglDP8BoBr8iSq7hEMCHQo1ML+Ki8sTYARi3qW3oZLxHcZj7aJXaHnBLJCU361vZKPWWAZ/dMyIzDTUlMbqE9HaWN2nd5IEJ/4sCC3llFfnhEIHOnb1eCCxTURdLhYf49XD6bhrO9USczfZLLr1yF/KBMDMgn0CeUzxVK5HY/vfBypwBVHUL8PMNJ5YVVwVENXDBcnxlBOS6thzW2xPmyU46m+C9HdF0ft/d019CeRyr2ibl1hmJjq7/or/gFZPflO7JUUM2Owfc2hq5zgFC873SAwhr++WGS9hAFEvCQN2XOLsSi4WaC/bClY9FOEgAfX69xEY+bkOKZSxc25n/38Z3fhK3flhlQj16oa0zuAurDtyA6KkpVstQQg=\""]
                """#
            }
        }

        @Test func `a key Gemini refuses throws with the code authentication`() async throws {
            let exchange = try await ExactExchange(replaying: .geminiRefusedKey)

            assertInlineSnapshot(of: exchange, as: .exchange) {
                """
                request 1
                {
                  "model": "gemini-3.1-flash-lite",
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
                OpenAICompatibleError(providerName: "Gemini", status: Optional(400), message: "Please pass a valid API key", code: authentication, errorType: Optional(INVALID_ARGUMENT), parameter: nil, requestID: nil, retryAfter: nil, isQuotaExhausted: false)
                """
            }
        }
    }
}
