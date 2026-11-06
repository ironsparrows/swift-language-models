import InlineSnapshotTesting
import LanguageModelsTestSupport
import Testing

/// Exchanges whose every byte and answer is pinned, so a change to how requests are built or answers are read shows
/// up here: the request bodies, OpenAI's headers, the session's transcript, the usage, a streamed answer's last
/// snapshot, and the error it ends in.
@Suite("Executor: exact exchanges")
struct ExecutorExactExchangeTests {
    @Test func `the exact requests and answer of a streamed answer with reasoning and OpenAI's options`() async {
        let exchange = await ExactExchange.textWithOptions()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            OpenAI-Organization: org-1
            OpenAI-Project: proj-1
            {
              "model": "gpt-test",
              "input": [
                {
                  "role": "developer",
                  "content": "Be brief."
                },
                {
                  "role": "user",
                  "content": "Plan the week."
                }
              ],
              "stream": true,
              "store": false,
              "include": [
                "reasoning.encrypted_content"
              ],
              "text": {
                "verbosity": "low"
              },
              "reasoning": {
                "effort": "low",
                "summary": "auto"
              },
              "max_output_tokens": 100,
              "metadata": {
                "team": "coach"
              },
              "service_tier": "flex",
              "prompt_cache_key": "<generated id>",
              "safety_identifier": "user-1"
            }

            transcript
            instructions ["Be brief."] tools: []
            prompt ["Plan the week."] metadata: {"team":"coach"}
            reasoning ["Plan it."] metadata: {"model":"gpt-test-2026-10-01","reasoningOrigin":"openai-responses"} signature: "[{\"encrypted_content\":\"blob-1\",\"id\":\"rs_1\",\"summary\":[{\"text\":\"Plan it.\",\"type\":\"summary_text\"}],\"type\":\"reasoning\"}]"
            response ["Start Monday."] metadata: {"finishReason":"stop","model":"gpt-test-2026-10-01","openAI.phases":[{"length":13,"phase":"final_answer"}],"requestID":"req_1","responseID":"resp_1","serviceTier":"default"}

            usage
            input 12 cached 4, output 9 reasoning 3, metadata: {}

            last snapshot
            "Start Monday." ["reasoning [\"Plan it.\"] metadata: {\"model\":\"gpt-test-2026-10-01\",\"reasoningOrigin\":\"openai-responses\"} signature: \"[{\\\"encrypted_content\\\":\\\"blob-1\\\",\\\"id\\\":\\\"rs_1\\\",\\\"summary\\\":[{\\\"text\\\":\\\"Plan it.\\\",\\\"type\\\":\\\"summary_text\\\"}],\\\"type\\\":\\\"reasoning\\\"}]\"", "response [\"Start Monday.\"] metadata: {\"finishReason\":\"stop\",\"model\":\"gpt-test-2026-10-01\",\"openAI.phases\":[{\"length\":13,\"phase\":\"final_answer\"}],\"requestID\":\"req_1\",\"responseID\":\"resp_1\",\"serviceTier\":\"default\"}"]
            """#
        }
    }

    @Test
    func `the exact requests and answer of parallel tool calls whose reasoning goes back before them, and the answer to their outputs`()
        async
    {
        let exchange = await ExactExchange.toolRound()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-test",
              "input": [
                {
                  "role": "user",
                  "content": "Calories in an egg and rice?"
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "tools": [
                {
                  "type": "function",
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
                  },
                  "strict": false
                }
              ],
              "parallel_tool_calls": true
            }

            request 2
            {
              "model": "gpt-test",
              "input": [
                {
                  "role": "user",
                  "content": "Calories in an egg and rice?"
                },
                {
                  "encrypted_content": "blob-1",
                  "id": "rs_1",
                  "summary": [
                    {
                      "text": "Look both up.",
                      "type": "summary_text"
                    }
                  ],
                  "type": "reasoning"
                },
                {
                  "type": "function_call",
                  "call_id": "call_1",
                  "name": "lookUpFood",
                  "arguments": "{\"food\":\"egg\"}"
                },
                {
                  "type": "function_call",
                  "call_id": "call_2",
                  "name": "lookUpFood",
                  "arguments": "{\"food\":\"rice\"}"
                },
                {
                  "type": "function_call_output",
                  "call_id": "call_1",
                  "output": "egg: 100 kcal"
                },
                {
                  "type": "function_call_output",
                  "call_id": "call_2",
                  "output": "rice: 100 kcal"
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "tools": [
                {
                  "type": "function",
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
                  },
                  "strict": false
                }
              ],
              "parallel_tool_calls": true
            }

            transcript
            instructions [] tools: ["lookUpFood"]
            prompt ["Calories in an egg and rice?"] metadata: {}
            reasoning ["Look both up."] metadata: {"model":"gpt-test-2026-10-01","reasoningOrigin":"openai-responses"} signature: "[{\"encrypted_content\":\"blob-1\",\"id\":\"rs_1\",\"summary\":[{\"text\":\"Look both up.\",\"type\":\"summary_text\"}],\"type\":\"reasoning\"}]"
            toolCalls ["call_1 lookUpFood {\"food\":\"egg\"} metadata: {\"finishReason\":\"tool_calls\",\"model\":\"gpt-test-2026-10-01\",\"responseID\":\"resp_1\",\"serviceTier\":\"default\"}", "call_2 lookUpFood {\"food\":\"rice\"} metadata: {}"]
            toolOutput call_1 lookUpFood ["egg: 100 kcal"]
            toolOutput call_2 lookUpFood ["rice: 100 kcal"]
            response ["Both have 100 kcal."] metadata: {"finishReason":"stop","model":"gpt-test-2026-10-01","responseID":"resp_1","serviceTier":"default"}

            usage
            input 40 cached 12, output 6 reasoning 0, metadata: {}
            """#
        }
    }

    @Test func `the exact requests and answer of a model that doesn't reason`() async {
        let exchange = await ExactExchange.plain()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            {
              "model": "gpt-plain",
              "input": [
                {
                  "role": "system",
                  "content": "Be brief."
                },
                {
                  "role": "user",
                  "content": "Hi"
                }
              ],
              "stream": true,
              "temperature": 0.5,
              "top_p": 0.9
            }

            transcript
            instructions ["Be brief."] tools: []
            prompt ["Hi"] metadata: {}
            response ["Hello."] metadata: {"finishReason":"stop","model":"gpt-plain","responseID":"resp_1","serviceTier":"default"}

            usage
            input 12 cached 0, output 5 reasoning 0, metadata: {}
            """
        }
    }

    @Test func `the exact requests and answer of a streamed answer that an error event ends`() async {
        let exchange = await ExactExchange.errorMidStream()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            {
              "model": "gpt-test",
              "input": [
                {
                  "role": "user",
                  "content": "Plan the week."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ]
            }

            error
            OpenAIError(status: nil, message: "The server had an error.", code: server_error, errorType: nil, parameter: nil, requestID: Optional("req_9"), retryAfter: nil, isQuotaExhausted: false)
            """
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `the exact requests and answer of an earlier prompt with an image and a PDF`() async throws {
        let exchange = try await ExactExchange.attachments()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            {
              "model": "gpt-test",
              "input": [
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "input_text",
                      "text": "Keep these."
                    },
                    {
                      "type": "input_text",
                      "text": "Photo"
                    },
                    {
                      "type": "input_image",
                      "image_url": "data:image/jpeg;base64,<jpeg>",
                      "detail": "auto"
                    },
                    {
                      "type": "input_text",
                      "text": "Menu"
                    },
                    {
                      "type": "input_file",
                      "filename": "Menu.pdf",
                      "file_data": "data:application/pdf;base64,JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSAvQ29udGVudHMgNCAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgNSAwIFIgPj4gPj4gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA0NiA+PgpzdHJlYW0KQlQgL0YxIDI0IFRmIDcyIDcyMCBUZCAoU291cCBvZiB0aGUgZGF5KSBUaiBFVAplbmRzdHJlYW0KZW5kb2JqCjUgMCBvYmoKPDwgL1R5cGUgL0ZvbnQgL1N1YnR5cGUgL1R5cGUxIC9CYXNlRm9udCAvSGVsdmV0aWNhID4+CmVuZG9iagp4cmVmCjAgNgowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMDkgMDAwMDAgbiAKMDAwMDAwMDA1OCAwMDAwMCBuIAowMDAwMDAwMTE1IDAwMDAwIG4gCjAwMDAwMDAyNDEgMDAwMDAgbiAKMDAwMDAwMDMzNyAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDYgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjQwNwolJUVPRgo="
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
              "include": [
                "reasoning.encrypted_content"
              ]
            }

            transcript
            prompt ["Keep these.", attachment Photo, attachment Menu] metadata: {}
            response ["Kept."] metadata: {"assetIDs":[]}
            prompt ["What's in these?"] metadata: {}
            response ["A menu and a photo."] metadata: {"finishReason":"stop","model":"gpt-test-2026-10-01","responseID":"resp_1","serviceTier":"default"}

            usage
            input 12 cached 0, output 5 reasoning 0, metadata: {}
            """
        }
    }
    #endif

    @Test func `a real streamed answer with reasoning ends in its text, its reasoning item, phase and usage`() async throws {
        let exchange = try await ExactExchange.realStream()

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-test",
              "input": [
                {
                  "role": "user",
                  "content": "What is 17 times 23? Reply with the number only."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ]
            }

            transcript
            prompt ["What is 17 times 23? Reply with the number only."] metadata: {}
            reasoning [] metadata: {"model":"gpt-6-luna","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq6aVuiNh11ZCoC_8VzGiRZqoIgNX6C5UK3qhGWJctukmQ7T4a4yyR3TQYMaEfRof3sv8hhHHgNjoUOJ1a0rDgKGjXU3EZFgRK-uZUBWGB_Mo2nQAPpyYWzCH6EQ5zj7013hExe6Wa2exV9AIY9FKyH1pF5GOHavf0lEVTi14AWp7RdwRO908a3W866tftEw5N68yQ-paWxNxAFhyKPG-Xj3xa38cqGHyw12kR1f8EkKhlCt-cr1gz3ECLe0qacrVcydZhsfY9T_UEvxddVc81bTEZ9WULlXnFa232A0p3BOb-iB1ljv0e_NerRej0OrdukxLyeTIRLzrWlYzS1_bAQmv6qqLCnPPJwPecrmyUlos16wC7PB0thkTjRqcshKwE9rxWfPlGC5px5Jar7nE6Uahif8R2jeeIsd277nAD1aaspe6Ln5MoErDTq2WWGBkuLDAs39G-88lz1JLaFOH_5fvoX8Pf7phbM1MVoToD9L5gOEzxHcq7uEU2YKgG4mvyWSFhnasNBxmhHpYDMsbZmSx2vWK1FTWyBX_DNjMqVfYwvZ0rscFrO-38qU6EJmJnA3WJNBCny5tqJbMZ5iowcto6QNcZ3RUgEAFLk-IwITmk6VCO9xF-cGMvLIT6YHLvOILq_Nnf2W6NnSlQH9R8jLQQVBPwJpPhSbfzm3NyuhaZ_ShQTOjWC0q2NTmClSsxmAnc3G23dDup3NOHwEoNaNRRSKs6qpf7DzZ4OkbAJgFh8v5IUC7CUkh_gv2SU3TsROCppQBes18EDxJpmKyMjvzUy2f2rI6dBrxgn_wmqWwOsl7LT6DyO64fVwN9k4i63JSUKosO-ApSgU1EIXeRQZyNZHvFj6UwHyB_zpn7epPDhdLh7BL2hEQH2itLsja41G-kqbyN-Au4NROPzZKiUsXeqpMZlhmJboOyIOCOy7iQ5w-TFm3PzW6CVI2oG6PeMyJBM0GQTpmT4Slrq43V6xRiLs9LTImuRUTi_-um0dMPM54mZ9cPpQus8j2bOuhElBTlony2XNM3YQLaMVrkr5IbxFRVLyGcPwGuIhhvq6xcMg8S0aR9OG7s9zVdVs7V3d-w9-0cxU84i8fXckwfHMrFB4wk1ANVUHJczXMUYxE-r2-UzZt0tBfy76QEag2t6ivJ9NSep1MWorw11NbKLLJ7gkKvkHPT_GBskdCMKiR1kJ2JXpVmAZLwDbssgvR6vtcDYWl3uKFNlIgl74Q79NX6R0B6BHbDQf1NU3qs_OmbwOqkfbKKitRio20l83gq0W-7SXrfSf3rV9LLGzcMjCcGNusWm9C63BeCt3XbWtG_DTAhqam3P710uCJfv1N0MOq169gaQPfYvRwxna0ahZFKaQO5uEqG83ghdBJa3XJ5deQrqqqkTiDj-B97OLQZDcgrPj2DcyUIvENqAOMlwq_kE8D3j_62bqFE4E4-kFtzIOX_R_XWjlwcGmq9kNba-WXx-M3rEHqm_34yr5pMLVTAW4se6z8V0HP1gRylunJxy2c=\",\"id\":\"rs_021ee27c8790196a016ae9a56ea35087d2b60dd22f849ee6a7\",\"summary\":[],\"type\":\"reasoning\"}]"
            response ["391"] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":3,"phase":"final_answer"}],"responseID":"resp_021ee27c8790196a016ae9a56d688887d290214057379e9b39","serviceTier":"default"}

            usage
            input 20 cached 0, output 17 reasoning 10, metadata: {"cacheWriteTokenCount":0}
            """#
        }
    }
}
