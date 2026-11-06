import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing

/// Exchanges whose every byte and answer is pinned, so a change to how requests are built or answers are read shows
/// up here: the request bodies, OpenRouter's headers, the session's transcript, the usage, a streamed answer's last
/// snapshot, and the error it ends in.
@Suite("Executor: exact exchanges")
struct ExecutorExactExchangeTests {
    @Test func `the exact requests and answer of a streamed text answer`() async {
        let exchange = await ExactExchange.textAlone()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "system",
                  "content": [
                    {
                      "type": "text",
                      "text": "Be brief.",
                      "cache_control": {
                        "type": "ephemeral"
                      }
                    }
                  ]
                },
                {
                  "role": "user",
                  "content": "Plan the week."
                }
              ],
              "stream": true,
              "temperature": 0.5,
              "top_p": 0.9,
              "seed": 7,
              "max_completion_tokens": 100,
              "frequency_penalty": 0.5,
              "stop": [
                "END"
              ],
              "logit_bias": {
                "13": 2.5,
                "50256": -100
              },
              "verbosity": "low",
              "service_tier": "flex",
              "user": "user-1",
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>",
              "metadata": {
                "team": "coach"
              },
              "cache_control": {
                "type": "ephemeral"
              }
            }

            transcript
            instructions ["Be brief."] tools: []
            prompt ["Plan the week."] metadata: {"count":3,"team":"coach"}
            response ["The plan starts Monday."] metadata: {"cacheWriteTokenCount":2,"cost":0.00025,"finishReason":"stop","model":"vendor/model","provider":"Vendor","responseID":"gen-1","serviceTier":"flex"}

            usage
            input 12 cached 4, output 5 reasoning 0, metadata: {"cacheWriteTokenCount":2,"cost":0.00025}

            last snapshot
            "The plan starts Monday." ["response [\"The plan starts Monday.\"] metadata: {\"cacheWriteTokenCount\":2,\"cost\":0.00025,\"finishReason\":\"stop\",\"model\":\"vendor/model\",\"provider\":\"Vendor\",\"responseID\":\"gen-1\",\"serviceTier\":\"flex\"}"]
            """#
        }
    }

    @Test func `the exact requests and answer of parallel tool calls and the answer to their outputs`() async {
        let exchange = await ExactExchange.parallelTools()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": "Calories in an egg and rice?"
                }
              ],
              "stream": true,
              "tools": [
                {
                  "type": "function",
                  "function": {
                    "name": "lookUpFood",
                    "description": "Looks up a food's calories.",
                    "parameters": {
                      "additionalProperties": false,
                      "properties": {
                        "food": {
                          "type": "string"
                        }
                      },
                      "required": [
                        "food"
                      ],
                      "title": "Arguments",
                      "type": "object"
                    }
                  }
                }
              ],
              "provider": {
                "require_parameters": true
              },
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            request 2
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": "Calories in an egg and rice?"
                },
                {
                  "role": "assistant",
                  "content": "Looking both up. ",
                  "tool_calls": [
                    {
                      "id": "call_1",
                      "type": "function",
                      "function": {
                        "name": "lookUpFood",
                        "arguments": "{\"food\":\"egg\"}"
                      }
                    },
                    {
                      "id": "call_2",
                      "type": "function",
                      "function": {
                        "name": "lookUpFood",
                        "arguments": "{\"food\":\"rice\"}"
                      }
                    }
                  ]
                },
                {
                  "role": "tool",
                  "tool_call_id": "call_1",
                  "content": "egg: 100 kcal"
                },
                {
                  "role": "tool",
                  "tool_call_id": "call_2",
                  "content": "rice: 100 kcal"
                }
              ],
              "stream": true,
              "tools": [
                {
                  "type": "function",
                  "function": {
                    "name": "lookUpFood",
                    "description": "Looks up a food's calories.",
                    "parameters": {
                      "additionalProperties": false,
                      "properties": {
                        "food": {
                          "type": "string"
                        }
                      },
                      "required": [
                        "food"
                      ],
                      "title": "Arguments",
                      "type": "object"
                    }
                  }
                }
              ],
              "provider": {
                "require_parameters": true
              },
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            instructions [] tools: ["lookUpFood"]
            prompt ["Calories in an egg and rice?"] metadata: {}
            response ["Looking both up. "] metadata: {}
            toolCalls ["call_1 lookUpFood {\"food\":\"egg\"} metadata: {\"cost\":0.00025,\"finishReason\":\"tool_calls\",\"model\":\"vendor/model\",\"provider\":\"Vendor\",\"responseID\":\"gen-1\"}", "call_2 lookUpFood {\"food\":\"rice\"} metadata: {}"]
            toolOutput call_1 lookUpFood ["egg: 100 kcal"]
            toolOutput call_2 lookUpFood ["rice: 100 kcal"]
            response ["An egg and rice have 100 kcal each."] metadata: {"cost":0.00025,"finishReason":"stop","model":"vendor/model","provider":"Vendor","responseID":"gen-1"}

            usage
            input 12 cached 0, output 5 reasoning 0, metadata: {"cost":0.00025}

            last snapshot
            "An egg and rice have 100 kcal each." ["response [\"Looking both up. \"] metadata: {}", "toolCalls [\"call_1 lookUpFood {\\\"food\\\":\\\"egg\\\"} metadata: {\\\"cost\\\":0.00025,\\\"finishReason\\\":\\\"tool_calls\\\",\\\"model\\\":\\\"vendor/model\\\",\\\"provider\\\":\\\"Vendor\\\",\\\"responseID\\\":\\\"gen-1\\\"}\", \"call_2 lookUpFood {\\\"food\\\":\\\"rice\\\"} metadata: {}\"]", "toolOutput call_1 lookUpFood [\"egg: 100 kcal\"]", "toolOutput call_2 lookUpFood [\"rice: 100 kcal\"]", "response [\"An egg and rice have 100 kcal each.\"] metadata: {\"cost\":0.00025,\"finishReason\":\"stop\",\"model\":\"vendor/model\",\"provider\":\"Vendor\",\"responseID\":\"gen-1\"}"]
            """#
        }
    }

    @Test func `the exact requests and answer of guided generation retried with the portable schema`() async {
        let exchange = await ExactExchange.portableSchemaRetry()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "text",
                      "text": "Rate the soup."
                    },
                    {
                      "type": "text",
                      "text": "Respond with JSON that matches this JSON Schema:\n{\"additionalProperties\":false,\"properties\":{\"stars\":{\"description\":\"From 1 to 5\",\"maximum\":5,\"minimum\":1,\"type\":\"integer\"},\"reason\":{\"type\":\"string\"}},\"required\":[\"stars\",\"reason\"],\"title\":\"SoupRating\",\"type\":\"object\"}"
                    }
                  ]
                }
              ],
              "stream": true,
              "response_format": {
                "type": "json_schema",
                "json_schema": {
                  "name": "SoupRating",
                  "strict": true,
                  "schema": {
                    "additionalProperties": false,
                    "properties": {
                      "stars": {
                        "description": "From 1 to 5",
                        "maximum": 5,
                        "minimum": 1,
                        "type": "integer"
                      },
                      "reason": {
                        "type": "string"
                      }
                    },
                    "required": [
                      "stars",
                      "reason"
                    ],
                    "title": "SoupRating",
                    "type": "object"
                  }
                }
              },
              "provider": {
                "require_parameters": true
              },
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            request 2
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "text",
                      "text": "Rate the soup."
                    },
                    {
                      "type": "text",
                      "text": "Respond with JSON that matches this JSON Schema:\n{\"additionalProperties\":false,\"properties\":{\"stars\":{\"description\":\"From 1 to 5\",\"maximum\":5,\"minimum\":1,\"type\":\"integer\"},\"reason\":{\"type\":\"string\"}},\"required\":[\"stars\",\"reason\"],\"title\":\"SoupRating\",\"type\":\"object\"}"
                    }
                  ]
                }
              ],
              "stream": true,
              "response_format": {
                "type": "json_schema",
                "json_schema": {
                  "name": "SoupRating",
                  "strict": true,
                  "schema": {
                    "additionalProperties": false,
                    "properties": {
                      "stars": {
                        "description": "From 1 to 5\n\n{maximum: 5, minimum: 1}",
                        "type": "integer"
                      },
                      "reason": {
                        "type": "string"
                      }
                    },
                    "required": [
                      "stars",
                      "reason"
                    ],
                    "title": "SoupRating",
                    "type": "object"
                  }
                }
              },
              "provider": {
                "require_parameters": true
              },
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            prompt ["Rate the soup."] metadata: {}
            response [{"reason":"Tasty.","stars":4}] metadata: {"cost":0.00025,"finishReason":"stop","model":"vendor/model","provider":"Vendor","responseID":"gen-1"}

            usage
            input 12 cached 0, output 5 reasoning 0, metadata: {"cost":0.00025}
            """#
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `the exact requests and answer of an image, a PDF and audio`() async throws {
        let exchange = try await ExactExchange.attachments()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "text",
                      "text": "Keep these."
                    },
                    {
                      "type": "text",
                      "text": "Photo"
                    },
                    {
                      "type": "image_url",
                      "image_url": {
                        "url": "data:image/jpeg;base64,<jpeg>"
                      }
                    },
                    {
                      "type": "text",
                      "text": "Menu"
                    },
                    {
                      "type": "file",
                      "file": {
                        "filename": "Menu.pdf",
                        "file_data": "data:application/pdf;base64,JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSAvQ29udGVudHMgNCAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgNSAwIFIgPj4gPj4gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA0NiA+PgpzdHJlYW0KQlQgL0YxIDI0IFRmIDcyIDcyMCBUZCAoU291cCBvZiB0aGUgZGF5KSBUaiBFVAplbmRzdHJlYW0KZW5kb2JqCjUgMCBvYmoKPDwgL1R5cGUgL0ZvbnQgL1N1YnR5cGUgL1R5cGUxIC9CYXNlRm9udCAvSGVsdmV0aWNhID4+CmVuZG9iagp4cmVmCjAgNgowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMDkgMDAwMDAgbiAKMDAwMDAwMDA1OCAwMDAwMCBuIAowMDAwMDAwMTE1IDAwMDAwIG4gCjAwMDAwMDAyNDEgMDAwMDAgbiAKMDAwMDAwMDMzNyAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDYgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjQwNwolJUVPRgo="
                      }
                    },
                    {
                      "type": "input_audio",
                      "input_audio": {
                        "data": "UklGRi13YXZl",
                        "format": "wav"
                      }
                    }
                  ]
                },
                {
                  "role": "assistant",
                  "content": "Kept."
                },
                {
                  "role": "user",
                  "content": "What's in these?"
                }
              ],
              "stream": true,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                },
                {
                  "id": "file-parser",
                  "pdf": {
                    "engine": "mistral-ocr"
                  }
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            prompt ["Keep these.", attachment Photo, attachment Menu, attachment unlabeled] metadata: {}
            response ["Kept."] metadata: {"assetIDs":[]}
            prompt ["What's in these?"] metadata: {}
            response ["A menu, a photo and a song."] metadata: {"cost":0.00025,"finishReason":"stop","model":"vendor/model","provider":"Vendor","responseID":"gen-1"}

            usage
            input 12 cached 0, output 5 reasoning 0, metadata: {"cost":0.00025}
            """
        }
    }
    #endif

    @Test func `the exact requests and answer of reasoning in think tags`() async {
        let exchange = await ExactExchange.taggedReasoning()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": "How many days in a week?"
                }
              ],
              "stream": true,
              "reasoning": {
                "effort": "medium"
              },
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            prompt ["How many days in a week?"] metadata: {}
            reasoning ["Count the days."] metadata: {"model":"vendor/model","reasoningOrigin":"openrouter","taggedReasoning":"<think>Count the days.</think>\n\n"} signature: nil
            response ["Seven days."] metadata: {"cost":0.00025,"finishReason":"stop","model":"vendor/model","provider":"Vendor","responseID":"gen-1"}

            usage
            input 12 cached 0, output 5 reasoning 0, metadata: {"cost":0.00025}

            last snapshot
            "Seven days." ["reasoning [\"Count the days.\"] metadata: {\"model\":\"vendor/model\",\"reasoningOrigin\":\"openrouter\",\"taggedReasoning\":\"<think>Count the days.</think>\\n\\n\"} signature: nil", "response [\"Seven days.\"] metadata: {\"cost\":0.00025,\"finishReason\":\"stop\",\"model\":\"vendor/model\",\"provider\":\"Vendor\",\"responseID\":\"gen-1\"}"]
            """#
        }
    }

    @Test func `the exact requests and answer of reasoning details sent back and streamed`() async {
        let exchange = await ExactExchange.reasoningDetails()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": "How many days in a week?"
                },
                {
                  "role": "assistant",
                  "content": "Seven.",
                  "reasoning": "Count them.",
                  "reasoning_details": [
                    {
                      "format": "anthropic-claude-v1",
                      "index": 0,
                      "signature": "sig-1",
                      "text": "Count them.",
                      "type": "reasoning.text"
                    }
                  ]
                },
                {
                  "role": "user",
                  "content": "And in a fortnight?"
                }
              ],
              "stream": true,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            prompt ["How many days in a week?"] metadata: {}
            reasoning ["Count them."] metadata: {"model":"vendor/model","reasoningOrigin":"openrouter"} signature: "[{\"type\":\"reasoning.text\",\"text\":\"Count them.\",\"signature\":\"sig-1\",\"format\":\"anthropic-claude-v1\",\"index\":0}]"
            response ["Seven."] metadata: {"assetIDs":[]}
            prompt ["And in a fortnight?"] metadata: {}
            reasoning ["Two weeks."] metadata: {"model":"vendor/model","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"anthropic-claude-v1\",\"index\":0,\"text\":\"Two weeks.\",\"type\":\"reasoning.text\",\"signature\":\"sig-2\"},{\"data\":\"blob\",\"index\":1,\"type\":\"reasoning.encrypted\"}]"
            response ["Fourteen."] metadata: {"cost":0.00025,"finishReason":"stop","model":"vendor/model","provider":"Vendor","responseID":"gen-1"}

            usage
            input 12 cached 0, output 5 reasoning 3, metadata: {"cost":0.00025}

            last snapshot
            "Fourteen." ["reasoning [\"Two weeks.\"] metadata: {\"model\":\"vendor/model\",\"reasoningOrigin\":\"openrouter\"} signature: \"[{\\\"format\\\":\\\"anthropic-claude-v1\\\",\\\"index\\\":0,\\\"text\\\":\\\"Two weeks.\\\",\\\"type\\\":\\\"reasoning.text\\\",\\\"signature\\\":\\\"sig-2\\\"},{\\\"data\\\":\\\"blob\\\",\\\"index\\\":1,\\\"type\\\":\\\"reasoning.encrypted\\\"}]\"", "response [\"Fourteen.\"] metadata: {\"cost\":0.00025,\"finishReason\":\"stop\",\"model\":\"vendor/model\",\"provider\":\"Vendor\",\"responseID\":\"gen-1\"}"]
            """#
        }
    }

    @Test func `the exact requests and answer of fallbacks with routing and plugins`() async {
        let exchange = await ExactExchange.fallbacks()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            X-OpenRouter-Cache-TTL: 600
            X-OpenRouter-Cache: true
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            X-Session-Id: <generated id>
            {
              "model": "vendor/model",
              "models": [
                "vendor/fallback",
                "openrouter/auto"
              ],
              "messages": [
                {
                  "role": "user",
                  "content": "Hi"
                }
              ],
              "stream": true,
              "tools": [
                {
                  "type": "openrouter:web_search",
                  "parameters": {
                    "max_results": 3
                  }
                }
              ],
              "provider": {
                "order": [
                  "Anthropic"
                ],
                "allow_fallbacks": false,
                "require_parameters": true,
                "sort": "price"
              },
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                },
                {
                  "id": "auto-router",
                  "allowed_models": [
                    "anthropic/*"
                  ]
                }
              ]
            }

            transcript
            prompt ["Hi"] metadata: {}
            response ["Hello."] metadata: {"cost":0.00025,"finishReason":"stop","model":"vendor/fallback","openRouter.region":"iad","openRouter.responseCacheStatus":"MISS","openRouter.routingAttempt":2,"openRouter.routingStrategy":"fallback","provider":"Vendor","responseID":"gen-1"}

            usage
            input 12 cached 0, output 5 reasoning 0, metadata: {"cost":0.00025}
            """
        }
    }

    @Test func `the exact requests and answer of an error event mid-stream`() async {
        let exchange = await ExactExchange.errorMidStream()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": "Plan the week."
                }
              ],
              "stream": true,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            error
            OpenRouterError(status: Optional(502), message: "Provider returned error", code: provider_overloaded, providerName: Optional(Vendor), retryAfter: nil)
            """
        }
    }

    @Test func `the exact requests and answer of a stream cut off before its end`() async {
        let exchange = await ExactExchange.cutOff()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "vendor/model",
              "messages": [
                {
                  "role": "user",
                  "content": "Plan the week."
                }
              ],
              "stream": true,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            error
            OpenRouterError(status: nil, message: "The response ended before it was complete.", code: invalid_response, providerName: Optional(Vendor), retryAfter: nil)
            """
        }
    }
}
