import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// Exchanges replayed from what OpenRouter really sent, so these pin how real streams and failures read. Ids and what shows
/// the account or its location are swapped for fake values; encrypted reasoning stays as it came. The streams and
/// failures a real host can't be made to send stay hand-built, in the other suites.
@Suite("Recorded exchanges", .timeLimit(.minutes(1)))
struct RecordedExchangeTests {
    @Test func `a real streamed answer reads as OpenRouter sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .text)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "mistralai/mistral-nemo",
              "messages": [
                {
                  "role": "user",
                  "content": "Name one color of the sea."
                }
              ],
              "stream": true,
              "max_tokens": 30,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            prompt ["Name one color of the sea."] metadata: {}
            response ["Blue"] metadata: {"cacheWriteTokenCount":0,"cost":2.4e-07,"finishReason":"stop","model":"mistralai/mistral-nemo","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":6e-08,"openRouter.upstreamInferenceCost":2.4e-07,"openRouter.upstreamInferencePromptCost":1.8e-07,"provider":"DekaLLM","responseID":"gen-1794001075-yf9TzUNNrW9Wui7QQzsr"}

            usage
            input 10 cached 0, output 2 reasoning 0, metadata: {"cacheWriteTokenCount":0,"cost":2.4e-07,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":6e-08,"openRouter.upstreamInferenceCost":2.4e-07,"openRouter.upstreamInferencePromptCost":1.8e-07}

            last snapshot
            "Blue" ["response [\"Blue\"] metadata: {\"cacheWriteTokenCount\":0,\"cost\":2.4e-07,\"finishReason\":\"stop\",\"model\":\"mistralai/mistral-nemo\",\"openRouter.isBYOK\":false,\"openRouter.upstreamInferenceCompletionCost\":6e-08,\"openRouter.upstreamInferenceCost\":2.4e-07,\"openRouter.upstreamInferencePromptCost\":1.8e-07,\"provider\":\"DekaLLM\",\"responseID\":\"gen-1794001075-yf9TzUNNrW9Wui7QQzsr\"}"]
            """#
        }
    }

    @Test func `a real answer with encrypted reasoning keeps its reasoning`() async throws {
        let exchange = try await ExactExchange(replaying: .reasoning)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "openai/gpt-5-nano",
              "messages": [
                {
                  "role": "user",
                  "content": "What is 17 times 23? Think it through."
                }
              ],
              "stream": true,
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 1200,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            prompt ["What is 17 times 23? Think it through."] metadata: {}
            reasoning ["**Calculating the multiplication**\n\nI need to compute 17 multiplied by 23. I checked that 17 times 23 equals 391, and I walked through the calculation step by step. I can illustrate it as 23 times (20 - 3), and I ended up with 230 plus 161, which also gives me 391. So, the final answer is indeed 391. I'm ready to provide a brief explanation without using any images. Let's respond to the user!"] metadata: {"model":"openai/gpt-5-nano","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"openai-responses-v1\",\"index\":0,\"summary\":\"**Calculating the multiplication**\\n\\nI need to compute 17 multiplied by 23. I checked that 17 times 23 equals 391, and I walked through the calculation step by step. I can illustrate it as 23 times (20 - 3), and I ended up with 230 plus 161, which also gives me 391. So, the final answer is indeed 391. I'm ready to provide a brief explanation without using any images. Let's respond to the user!\",\"type\":\"reasoning.summary\"},{\"data\":\"gAAAAABq7ki3uNOFVHTF9Rh0D-kRbOfwxAZORfR5ROJPepQZ90jA8gnw3PrGCxDR0O2I0nQVeRlvah5Z7v2nQarfY-oUdR6bqPU-m1hDeiWR_XueL_1oU1cOM-KPI5gZsmK5Xm0-7RniuYoDujGn6JXRiGhD69o9XW4cw_KSna58CT5w0gX3apg0qfQot5L9cu_6ihs5NG-EQQQdZ6P25btX_MHCGwUR6oURTzyfC3w1zGAFrMDixQQCmh-3n69rpdDt-sujRKqowzrK1XAO81DRktwd_YvTyaVPS3mZrdzVAqODOn6tF_yXWuOYaZ3jXXWC-x-rvo3OoKW_EujzkxEZAfmcOlyUU7oWyzHjcTovgo79jUakrFXZ7prQ4MA8ZwsyWqQpzqrhl_mWkZXAAFTArihs8P-rdA-QcYe-lqt-sKFQL91UGFvpIWZrusTARB33lSQj9_SsSnMlUHAM1Ha1IWDgJi_iGp7XNrhmP7qZvPr-C9cuYhJXwMUrGKpMXzsXB2wcQIqAASpJ3tPV1mRl722YxhT70DTpt3FTMYDimppDpC6CDs63tZku6zbdflml8TLXBMuNvcB2_BY5FvuBIBuxk64DUFmKIOyj15P6y8TBaVs_KorrZMRAr5DBHPAFr7l9785ReDoEGimGdbRMct1HJQzrFi7cKunIiBc6zRQDu-UHcRNbkN19BHlmKHB1OOdh8ZD7dfTqrXDefWPw7oXsgIX2mjbuNnYb6MHaBMM7ZNJlac9H15IOUjAzQepXPSBdzY1Lc6d87Y5LDr07u2nI8z42l9iWowAN6hDIg_vw-yIJS4HK6R1c_iDmTU8OxrW3uJbYMIfOdrutxgVe4nTfx2fR_8UWC6awhLH6vDa1RFQluycHH6MAuBMRcJD1oyNeq-ngr053tbsKCQi-z8W6hiWoE66wCePpiYqW0CQk7YCXu7CE4MeX_NkuWucpVrIMSLkUxEppU6W5RYWMA4gWjNgCuYGyDVK3dpOuVxxgzGxM7ue4quAP9Ts_lLG9QT-1Y4GmwhYunQojhe8jM5TowHekGawGtEV4AeZXcoHblLPP5kX5hP77kwC0J9On3A6dIGqKzYwqIaL2w20daNISJqH7UruJ0pRK7tprClIsmFhki5fMpUJLnFmiCJN9RJw71p_XXnSArksCMZHtAb2TEe6IV1gC7Y6ZGMad7ORa0gRI3ZOSd05UnAqVltscVA1qAM3Wk-dSJCWnN9tWE48zCuaIBYxzeKzcfoLh4T_Z8LmeBHVlogT5gjctFn2M7pB_MXy6QVNatbYlDDUzJ75RgMY265-OT4VqGbdVpfOe4jYc4QY6qLmS2DwY22tqfDija1Mm0OkH7FQHbmvhHhosUoF_fJ3suPAtkvLzJVFnBGdcmXjy7mOF5SPhqHnVFCCf06uB4CEMwE-lJtpSQWBtn7UxIWjMVXTc3pk0WPX480xXNRvfMbKSo-RpBMin4MfTo9WSjDgD6k1pw98iaVLPA-aoF_IoOVkbeXsHqSyvVWwje91UqBw_afQXnwfIZc9sUYST0xoRwo_ShlPshHFPZy0viTN1H824zYKJzB9CVsjFy1-r7m-7-eu71P5I_zIYo7JPCao4cd-3D52WvsIfgnT7i0lILetsjH2nR_PomW3HAZwHBwTMGWKfxJM-VrMGAO5LzLfXDGjDmcegtkrM55nIC1fRgpjjxwpfYNOaFPz9kLEvC90v7cbN0t5-0bb6OfzPClx2RKplirUnSOsa5ZuibigBhu6YIJjcObNVuyEm_Uoo8ANHUX5aT9aZ75m9Z36pjmtNK0ztQyjf_IFmX3TtpyrI2-oLoSpaUDs0EruswMy0uFTg1gRI4ihW3XyU1Wlgjg2trY66ZKMwdfucZK63kv0_FlduqATU7vzsc3RfLUym9_i2G9yYLpVL9dT_knLf5WUoDV_kFaSeSf4wjtts8qM-tnukh3Di8eAmuYvao1j9JkMKKElMwWEIGssF8jc6O29fnRmWlfj5pwg9YM0gC3nhqoFGX1VHVv8KeWNk1GO_4IC5LidfBEjTmF2qSMHN6BFYUhVHg4OKBGuvAMz5lUv16pGeyTFESfZVpi9rjlY9FjPehWFVtyLxrzYajr-9vJOVVAiwg9VyBwVSrmZACGiQfJFpt6Hf9f1-GMOhB8xui2DsvVpP7qWIIDYwr10E2lkI9hZuuoqHcNhnGYZERXXPEPNzrz-fE5XRTL-ewBSsPtOEIpSsRFJblLBgjUWmnHuyYWXxWTu324OxUji2OAspNOSrm7NhS4fbdiDhweMrEugUNbDUd88qJmT6hGCujMx3-BrTErscMyr825a9ABuFKIecKUaE77SfHsE8OBqAD4ThWxTXf0DAHzMau8XowcgRTn_Bd9DwoS6cOuhkkxXTDIaz0lFoz9jMoOJbxVcAET7aPXFdxKJgTS5EGjUBLwZEMPDJLDfrnYeeIbULlMK85p8A9R9xf74ugaAEsyErUOJlmCu7SlORrjO24S9XqyW4AJtPA3ZLUJHpyiKsXHFCnWCPyTkwMvqRruBf_WqsPxf9rGpBYSggKUuXpfUcgFfLae-Jfxfl64Z6p-M_f3NCPUnraWnALmzje3w3DtaFWj3IIdFhS6eUJaMM-GYvvvSgXE83SXIT9a8ER5_FU_oxw_s3chiv0PjXVMzz8NRH431JMj4i0jMD2Kdi9lOPl2t0VlJH49CUuHh34eX-eOGruzxcXmX_hGYqCLZ_hKUakdjTBXiCqIZqDdQ7UH--aXguQNUr1uv5xAbG5gmTNVg-T7-1pxTAysGH23IDdiYW-OItSpgz1vS849LoqCGxT2q1I3ubjWSc_QHv-OKARuEZtkZLOtTVk6sly1v_5hTBLkWNgLOjaU-6NEv6on6LLc6t9dCyGOcRRW3e9r0olu2903Ia7yCrM--dtYCYcE7j-Orf39Ja45SUvBhdP72wuIsI8NevxpC9_1a1veZbFrkf-7NwgB_GtREevnJCEBaSzmJkESj5zHbzYeApQcxz.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\",\"format\":\"openai-responses-v1\",\"id\":\"rs_72207d7635e1fa6427033a8177a9da96c046a5f1463dfb650c\",\"index\":1,\"type\":\"reasoning.encrypted\"}]"
            response ["391\n\nReason: 17 × 23 = (10 + 7) × 23 = 10×23 + 7×23 = 230 + 161 = 391."] metadata: {"cacheWriteTokenCount":0,"cost":6.57e-05,"finishReason":"stop","model":"openai/gpt-5-nano","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":6.48e-05,"openRouter.upstreamInferenceCost":6.57e-05,"openRouter.upstreamInferencePromptCost":9e-07,"provider":"OpenAI","responseID":"gen-1794001077-6fBZduGtFnS6mmgx2YCK","serviceTier":"default"}

            usage
            input 18 cached 0, output 162 reasoning 64, metadata: {"cacheWriteTokenCount":0,"cost":6.57e-05,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":6.48e-05,"openRouter.upstreamInferenceCost":6.57e-05,"openRouter.upstreamInferencePromptCost":9e-07}

            last snapshot
            "391\n\nReason: 17 × 23 = (10 + 7) × 23 = 10×23 + 7×23 = 230 + 161 = 391." ["reasoning [\"**Calculating the multiplication**\\n\\nI need to compute 17 multiplied by 23. I checked that 17 times 23 equals 391, and I walked through the calculation step by step. I can illustrate it as 23 times (20 - 3), and I ended up with 230 plus 161, which also gives me 391. So, the final answer is indeed 391. I\'m ready to provide a brief explanation without using any images. Let\'s respond to the user!\"] metadata: {\"model\":\"openai/gpt-5-nano\",\"reasoningOrigin\":\"openrouter\"} signature: \"[{\\\"format\\\":\\\"openai-responses-v1\\\",\\\"index\\\":0,\\\"summary\\\":\\\"**Calculating the multiplication**\\\\n\\\\nI need to compute 17 multiplied by 23. I checked that 17 times 23 equals 391, and I walked through the calculation step by step. I can illustrate it as 23 times (20 - 3), and I ended up with 230 plus 161, which also gives me 391. So, the final answer is indeed 391. I\'m ready to provide a brief explanation without using any images. Let\'s respond to the user!\\\",\\\"type\\\":\\\"reasoning.summary\\\"},{\\\"data\\\":\\\"gAAAAABq7ki3uNOFVHTF9Rh0D-kRbOfwxAZORfR5ROJPepQZ90jA8gnw3PrGCxDR0O2I0nQVeRlvah5Z7v2nQarfY-oUdR6bqPU-m1hDeiWR_XueL_1oU1cOM-KPI5gZsmK5Xm0-7RniuYoDujGn6JXRiGhD69o9XW4cw_KSna58CT5w0gX3apg0qfQot5L9cu_6ihs5NG-EQQQdZ6P25btX_MHCGwUR6oURTzyfC3w1zGAFrMDixQQCmh-3n69rpdDt-sujRKqowzrK1XAO81DRktwd_YvTyaVPS3mZrdzVAqODOn6tF_yXWuOYaZ3jXXWC-x-rvo3OoKW_EujzkxEZAfmcOlyUU7oWyzHjcTovgo79jUakrFXZ7prQ4MA8ZwsyWqQpzqrhl_mWkZXAAFTArihs8P-rdA-QcYe-lqt-sKFQL91UGFvpIWZrusTARB33lSQj9_SsSnMlUHAM1Ha1IWDgJi_iGp7XNrhmP7qZvPr-C9cuYhJXwMUrGKpMXzsXB2wcQIqAASpJ3tPV1mRl722YxhT70DTpt3FTMYDimppDpC6CDs63tZku6zbdflml8TLXBMuNvcB2_BY5FvuBIBuxk64DUFmKIOyj15P6y8TBaVs_KorrZMRAr5DBHPAFr7l9785ReDoEGimGdbRMct1HJQzrFi7cKunIiBc6zRQDu-UHcRNbkN19BHlmKHB1OOdh8ZD7dfTqrXDefWPw7oXsgIX2mjbuNnYb6MHaBMM7ZNJlac9H15IOUjAzQepXPSBdzY1Lc6d87Y5LDr07u2nI8z42l9iWowAN6hDIg_vw-yIJS4HK6R1c_iDmTU8OxrW3uJbYMIfOdrutxgVe4nTfx2fR_8UWC6awhLH6vDa1RFQluycHH6MAuBMRcJD1oyNeq-ngr053tbsKCQi-z8W6hiWoE66wCePpiYqW0CQk7YCXu7CE4MeX_NkuWucpVrIMSLkUxEppU6W5RYWMA4gWjNgCuYGyDVK3dpOuVxxgzGxM7ue4quAP9Ts_lLG9QT-1Y4GmwhYunQojhe8jM5TowHekGawGtEV4AeZXcoHblLPP5kX5hP77kwC0J9On3A6dIGqKzYwqIaL2w20daNISJqH7UruJ0pRK7tprClIsmFhki5fMpUJLnFmiCJN9RJw71p_XXnSArksCMZHtAb2TEe6IV1gC7Y6ZGMad7ORa0gRI3ZOSd05UnAqVltscVA1qAM3Wk-dSJCWnN9tWE48zCuaIBYxzeKzcfoLh4T_Z8LmeBHVlogT5gjctFn2M7pB_MXy6QVNatbYlDDUzJ75RgMY265-OT4VqGbdVpfOe4jYc4QY6qLmS2DwY22tqfDija1Mm0OkH7FQHbmvhHhosUoF_fJ3suPAtkvLzJVFnBGdcmXjy7mOF5SPhqHnVFCCf06uB4CEMwE-lJtpSQWBtn7UxIWjMVXTc3pk0WPX480xXNRvfMbKSo-RpBMin4MfTo9WSjDgD6k1pw98iaVLPA-aoF_IoOVkbeXsHqSyvVWwje91UqBw_afQXnwfIZc9sUYST0xoRwo_ShlPshHFPZy0viTN1H824zYKJzB9CVsjFy1-r7m-7-eu71P5I_zIYo7JPCao4cd-3D52WvsIfgnT7i0lILetsjH2nR_PomW3HAZwHBwTMGWKfxJM-VrMGAO5LzLfXDGjDmcegtkrM55nIC1fRgpjjxwpfYNOaFPz9kLEvC90v7cbN0t5-0bb6OfzPClx2RKplirUnSOsa5ZuibigBhu6YIJjcObNVuyEm_Uoo8ANHUX5aT9aZ75m9Z36pjmtNK0ztQyjf_IFmX3TtpyrI2-oLoSpaUDs0EruswMy0uFTg1gRI4ihW3XyU1Wlgjg2trY66ZKMwdfucZK63kv0_FlduqATU7vzsc3RfLUym9_i2G9yYLpVL9dT_knLf5WUoDV_kFaSeSf4wjtts8qM-tnukh3Di8eAmuYvao1j9JkMKKElMwWEIGssF8jc6O29fnRmWlfj5pwg9YM0gC3nhqoFGX1VHVv8KeWNk1GO_4IC5LidfBEjTmF2qSMHN6BFYUhVHg4OKBGuvAMz5lUv16pGeyTFESfZVpi9rjlY9FjPehWFVtyLxrzYajr-9vJOVVAiwg9VyBwVSrmZACGiQfJFpt6Hf9f1-GMOhB8xui2DsvVpP7qWIIDYwr10E2lkI9hZuuoqHcNhnGYZERXXPEPNzrz-fE5XRTL-ewBSsPtOEIpSsRFJblLBgjUWmnHuyYWXxWTu324OxUji2OAspNOSrm7NhS4fbdiDhweMrEugUNbDUd88qJmT6hGCujMx3-BrTErscMyr825a9ABuFKIecKUaE77SfHsE8OBqAD4ThWxTXf0DAHzMau8XowcgRTn_Bd9DwoS6cOuhkkxXTDIaz0lFoz9jMoOJbxVcAET7aPXFdxKJgTS5EGjUBLwZEMPDJLDfrnYeeIbULlMK85p8A9R9xf74ugaAEsyErUOJlmCu7SlORrjO24S9XqyW4AJtPA3ZLUJHpyiKsXHFCnWCPyTkwMvqRruBf_WqsPxf9rGpBYSggKUuXpfUcgFfLae-Jfxfl64Z6p-M_f3NCPUnraWnALmzje3w3DtaFWj3IIdFhS6eUJaMM-GYvvvSgXE83SXIT9a8ER5_FU_oxw_s3chiv0PjXVMzz8NRH431JMj4i0jMD2Kdi9lOPl2t0VlJH49CUuHh34eX-eOGruzxcXmX_hGYqCLZ_hKUakdjTBXiCqIZqDdQ7UH--aXguQNUr1uv5xAbG5gmTNVg-T7-1pxTAysGH23IDdiYW-OItSpgz1vS849LoqCGxT2q1I3ubjWSc_QHv-OKARuEZtkZLOtTVk6sly1v_5hTBLkWNgLOjaU-6NEv6on6LLc6t9dCyGOcRRW3e9r0olu2903Ia7yCrM--dtYCYcE7j-Orf39Ja45SUvBhdP72wuIsI8NevxpC9_1a1veZbFrkf-7NwgB_GtREevnJCEBaSzmJkESj5zHbzYeApQcxz.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\\\",\\\"format\\\":\\\"openai-responses-v1\\\",\\\"id\\\":\\\"rs_72207d7635e1fa6427033a8177a9da96c046a5f1463dfb650c\\\",\\\"index\\\":1,\\\"type\\\":\\\"reasoning.encrypted\\\"}]\"", "response [\"391\\n\\nReason: 17 × 23 = (10 + 7) × 23 = 10×23 + 7×23 = 230 + 161 = 391.\"] metadata: {\"cacheWriteTokenCount\":0,\"cost\":6.57e-05,\"finishReason\":\"stop\",\"model\":\"openai/gpt-5-nano\",\"openRouter.isBYOK\":false,\"openRouter.upstreamInferenceCompletionCost\":6.48e-05,\"openRouter.upstreamInferenceCost\":6.57e-05,\"openRouter.upstreamInferencePromptCost\":9e-07,\"provider\":\"OpenAI\",\"responseID\":\"gen-1794001077-6fBZduGtFnS6mmgx2YCK\",\"serviceTier\":\"default\"}"]
            """#
        }
    }

    @Test func `real signed reasoning goes back on the next turn`() async throws {
        let exchange = try await ExactExchange(replaying: .signedReasoning)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "anthropic/claude-haiku-4.5",
              "messages": [
                {
                  "role": "user",
                  "content": "What is 17 times 23? Think it through."
                }
              ],
              "stream": true,
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 2000,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>",
              "cache_control": {
                "type": "ephemeral"
              }
            }

            request 2
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "anthropic/claude-haiku-4.5",
              "messages": [
                {
                  "role": "user",
                  "content": "What is 17 times 23? Think it through."
                },
                {
                  "role": "assistant",
                  "content": "# 17 × 23\n\nI'll break this into easier parts:\n\n17 × 23 = 17 × (20 + 3)\n\n**Step 1:** 17 × 20 = 340\n\n**Step 2:** 17 × 3 = 51\n\n**Step 3:** 340 + 51 = **391**\n\nThe answer is **391**.",
                  "reasoning": "I need to calculate 17 × 23.\n\nLet me break this down:\n17 × 23 = 17 × (20 + 3)\n= (17 × 20) + (17 × 3)\n= 340 + 51\n= 391\n\nLet me verify this another way:\n17 × 23 = (10 + 7) × 23\n= (10 × 23) + (7 × 23)\n= 230 + 161\n= 391\n\nBoth methods give me 391, so that's the answer.",
                  "reasoning_details": [
                    {
                      "format": "anthropic-claude-v1",
                      "index": 0,
                      "signature": "EpEECpwBCBMQARgCKkCM0so1867YjUkj05wXjyvSWRC03LcVHGr4F/urhzXpNfF49Kij0izdJlC9/evtdF//AMMpaHjvikMx9IbAcyEjMhljbGF1ZGUtaGFpa3UtNC01LTIwMjUxMDAxOABCCHRoaW5raW5nWgw1MzY2OTcyNDk3MjhyENrkNIDPvK+G6yste9b7RhWIAQGoAbmRudcGsAECEgydbYgBCraqEl5ITR8aDE/YCThpbTDf9qHPBiIw6eM5aabCCctg/XBctc+yW8Xq6EAY3rIXHOq/czEt5Z6meVwdVLL3CKjIlQiHHiarKqEC33J++ELdFIrMdFu+N8lwHBK8fMi7Uqx4nKNI2bLQwesFmVJdcSrjGJ3u7oMqPeE6nM1Q0CAaqPgF6o3hJFap40AxewgHCIc3guaHTVFccxWQnXGVi+Pi1Vb5nduqZE6pBcv7RBSp+rPNUMM3MQSsp7GR7FNM/JVTAV62v5DPYJrpNMGGI2edCvEKmTYGyVRKmmfw3dHDU5VOLPm6sB6Hv+C6KA3K+q14/ReJ8fDbD51OJVCPgla/yxoRVXfCJxQ0RN6UEAEundI1N++j+Irle655q9MHZhdGW88V06HY8+PbnSfzXM/CQ80Jq06lt2iv/k64fclunv58MkCfPgKpm1rk2De1Pf5yS+YLbLEsX4haE0UUZQva7ubAtbvtyw+VHxgB.eyJlbmRwb2ludF9zbHVnIjoiYW50aHJvcGljL2NsYXVkZS00LjUtaGFpa3UtMjAyNTEwMDF8YW1hem9uLWJlZHJvY2svZ2xvYmFsIn0",
                      "text": "I need to calculate 17 × 23.\n\nLet me break this down:\n17 × 23 = 17 × (20 + 3)\n= (17 × 20) + (17 × 3)\n= 340 + 51\n= 391\n\nLet me verify this another way:\n17 × 23 = (10 + 7) × 23\n= (10 × 23) + (7 × 23)\n= 230 + 161\n= 391\n\nBoth methods give me 391, so that's the answer.",
                      "type": "reasoning.text"
                    }
                  ]
                },
                {
                  "role": "user",
                  "content": "And 23 times 17?"
                }
              ],
              "stream": true,
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 2000,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>",
              "cache_control": {
                "type": "ephemeral"
              }
            }

            transcript
            prompt ["What is 17 times 23? Think it through."] metadata: {}
            reasoning ["I need to calculate 17 × 23.\n\nLet me break this down:\n17 × 23 = 17 × (20 + 3)\n= (17 × 20) + (17 × 3)\n= 340 + 51\n= 391\n\nLet me verify this another way:\n17 × 23 = (10 + 7) × 23\n= (10 × 23) + (7 × 23)\n= 230 + 161\n= 391\n\nBoth methods give me 391, so that's the answer."] metadata: {"model":"anthropic/claude-haiku-4.5","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"anthropic-claude-v1\",\"index\":0,\"text\":\"I need to calculate 17 × 23.\\n\\nLet me break this down:\\n17 × 23 = 17 × (20 + 3)\\n= (17 × 20) + (17 × 3)\\n= 340 + 51\\n= 391\\n\\nLet me verify this another way:\\n17 × 23 = (10 + 7) × 23\\n= (10 × 23) + (7 × 23)\\n= 230 + 161\\n= 391\\n\\nBoth methods give me 391, so that's the answer.\",\"type\":\"reasoning.text\",\"signature\":\"EpEECpwBCBMQARgCKkCM0so1867YjUkj05wXjyvSWRC03LcVHGr4F/urhzXpNfF49Kij0izdJlC9/evtdF//AMMpaHjvikMx9IbAcyEjMhljbGF1ZGUtaGFpa3UtNC01LTIwMjUxMDAxOABCCHRoaW5raW5nWgw1MzY2OTcyNDk3MjhyENrkNIDPvK+G6yste9b7RhWIAQGoAbmRudcGsAECEgydbYgBCraqEl5ITR8aDE/YCThpbTDf9qHPBiIw6eM5aabCCctg/XBctc+yW8Xq6EAY3rIXHOq/czEt5Z6meVwdVLL3CKjIlQiHHiarKqEC33J++ELdFIrMdFu+N8lwHBK8fMi7Uqx4nKNI2bLQwesFmVJdcSrjGJ3u7oMqPeE6nM1Q0CAaqPgF6o3hJFap40AxewgHCIc3guaHTVFccxWQnXGVi+Pi1Vb5nduqZE6pBcv7RBSp+rPNUMM3MQSsp7GR7FNM/JVTAV62v5DPYJrpNMGGI2edCvEKmTYGyVRKmmfw3dHDU5VOLPm6sB6Hv+C6KA3K+q14/ReJ8fDbD51OJVCPgla/yxoRVXfCJxQ0RN6UEAEundI1N++j+Irle655q9MHZhdGW88V06HY8+PbnSfzXM/CQ80Jq06lt2iv/k64fclunv58MkCfPgKpm1rk2De1Pf5yS+YLbLEsX4haE0UUZQva7ubAtbvtyw+VHxgB.eyJlbmRwb2ludF9zbHVnIjoiYW50aHJvcGljL2NsYXVkZS00LjUtaGFpa3UtMjAyNTEwMDF8YW1hem9uLWJlZHJvY2svZ2xvYmFsIn0\"}]"
            response ["# 17 × 23\n\nI'll break this into easier parts:\n\n17 × 23 = 17 × (20 + 3)\n\n**Step 1:** 17 × 20 = 340\n\n**Step 2:** 17 × 3 = 51\n\n**Step 3:** 340 + 51 = **391**\n\nThe answer is **391**."] metadata: {"cacheWriteTokenCount":0,"cost":0.001234,"finishReason":"stop","model":"anthropic/claude-haiku-4.5","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":0.001185,"openRouter.upstreamInferenceCost":0.001234,"openRouter.upstreamInferencePromptCost":4.9e-05,"provider":"Amazon Bedrock","responseID":"gen-1794001079-rvuRbSJCQNYWZ0LFOBQc","serviceTier":"default"}
            prompt ["And 23 times 17?"] metadata: {}
            reasoning ["The user is asking for 23 times 17. This is actually the same as 17 times 23 due to the commutative property of multiplication. So the answer should be 391 as well.\n\nBut let me show the calculation to demonstrate:\n\n23 × 17 = 23 × (10 + 7)\n= 23 × 10 + 23 × 7\n= 230 + 161\n= 391\n\nOr I could break it down differently:\n23 × 17 = (20 + 3) × 17\n= 20 × 17 + 3 × 17\n= 340 + 51\n= 391\n\nEither way, it's 391, same as before."] metadata: {"model":"anthropic/claude-haiku-4.5","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"anthropic-claude-v1\",\"index\":0,\"text\":\"The user is asking for 23 times 17. This is actually the same as 17 times 23 due to the commutative property of multiplication. So the answer should be 391 as well.\\n\\nBut let me show the calculation to demonstrate:\\n\\n23 × 17 = 23 × (10 + 7)\\n= 23 × 10 + 23 × 7\\n= 230 + 161\\n= 391\\n\\nOr I could break it down differently:\\n23 × 17 = (20 + 3) × 17\\n= 20 × 17 + 3 × 17\\n= 340 + 51\\n= 391\\n\\nEither way, it's 391, same as before.\",\"type\":\"reasoning.text\",\"signature\":\"EqUFCpwBCBMQARgCKkB1oBCnSwxtkwk8KsGVdUHWIE6TSxX2/ySAuQSLljHLWs+BqfbM1W598w4mQyUma7VBl0iIt9Fk+w1wg/tkNtFFMhljbGF1ZGUtaGFpa3UtNC01LTIwMjUxMDAxOABCCHRoaW5raW5nWgw1MzY2OTcyNDk3MjhyENrkNIDPvK+G6yste9b7RhWIAQGoAbuRudcGsAECEgytfmKpOOHXlUkupDIaDHj3LYpVa5nLVBmDVyIw+iLDinJyV+rQLJ/kmWokbKFY2A9OOrDRYzp9BXW0LXPsB5NrkgIRbfjAxnXdpApEKrUD9vSd7BewQeq1zpQXk5Pa/59mEZSzdY0a4JJEtYmjEgHtPlfzhmHCPQp6Rp5JIewy3y7OJCibBzxUrSySHhGE6geQ/fplv/H6ZtvIIo7+EZavWOK+ZkbLQszQ9jjxGORpoaU+1/V0eKVF0UhN4mXQIfKI1y7hcRaQOs2k4goZnnMAsmTI2zxTbsw3Ls2xDwBp/+y324SEM78rhnsv6qZ7MmeHJfoPYKNFcD6Ca6d1xn9KQyOphL1pruqxeMSo6JsF6aub5FGAXn5r4ah+ZIdslJ6SMAfl5upXWuVbHpSboqdiW2CJ0OBJLlCjlubvRlmXG9RlSm9B4NQC9xwDidF7qobR6/mwfeJP4dG1OzlXM5AZIYZzRuWp0YDHcv7hLZ8SO3bpJeqZ7dLZM6uTLLprUO3j2xVkgcuvwKHFtY5VwQ+UYZA4FjswZ0jy/mmlxX6/p38uWQErSxLHt+cCGKKo1w8G5pyJlQGkaS9YpgeihT3F2/vnSd/uWMcHObp4BIIo0K+2PFi9dvHvsvGCLik01hgH6XZjL1w5OaI+7vqmvbNJBWs4okoMSCOHTUqcBoxrUhlszScYAQ==.eyJlbmRwb2ludF9zbHVnIjoiYW50aHJvcGljL2NsYXVkZS00LjUtaGFpa3UtMjAyNTEwMDF8YW1hem9uLWJlZHJvY2svZ2xvYmFsIn0\"}]"
            response ["# 23 × 17\n\nI'll break this down:\n\n23 × 17 = 23 × (10 + 7)\n\n**Step 1:** 23 × 10 = 230\n\n**Step 2:** 23 × 7 = 161\n\n**Step 3:** 230 + 161 = **391**\n\nThe answer is **391**.\n\nThis is the same as before! This demonstrates the commutative property of multiplication: the order doesn't matter, so 17 × 23 = 23 × 17."] metadata: {"cacheWriteTokenCount":0,"cost":0.001709,"finishReason":"stop","model":"anthropic/claude-haiku-4.5","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":0.001555,"openRouter.upstreamInferenceCost":0.001709,"openRouter.upstreamInferencePromptCost":0.000154,"provider":"Amazon Bedrock","responseID":"gen-1794001081-zuazVI6uaD1QJS8mbLFB","serviceTier":"default"}

            usage
            input 154 cached 0, output 311 reasoning 176, metadata: {"cacheWriteTokenCount":0,"cost":0.001709,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":0.001555,"openRouter.upstreamInferenceCost":0.001709,"openRouter.upstreamInferencePromptCost":0.000154}

            last snapshot
            "# 23 × 17\n\nI'll break this down:\n\n23 × 17 = 23 × (10 + 7)\n\n**Step 1:** 23 × 10 = 230\n\n**Step 2:** 23 × 7 = 161\n\n**Step 3:** 230 + 161 = **391**\n\nThe answer is **391**.\n\nThis is the same as before! This demonstrates the commutative property of multiplication: the order doesn't matter, so 17 × 23 = 23 × 17." ["reasoning [\"The user is asking for 23 times 17. This is actually the same as 17 times 23 due to the commutative property of multiplication. So the answer should be 391 as well.\\n\\nBut let me show the calculation to demonstrate:\\n\\n23 × 17 = 23 × (10 + 7)\\n= 23 × 10 + 23 × 7\\n= 230 + 161\\n= 391\\n\\nOr I could break it down differently:\\n23 × 17 = (20 + 3) × 17\\n= 20 × 17 + 3 × 17\\n= 340 + 51\\n= 391\\n\\nEither way, it\'s 391, same as before.\"] metadata: {\"model\":\"anthropic/claude-haiku-4.5\",\"reasoningOrigin\":\"openrouter\"} signature: \"[{\\\"format\\\":\\\"anthropic-claude-v1\\\",\\\"index\\\":0,\\\"text\\\":\\\"The user is asking for 23 times 17. This is actually the same as 17 times 23 due to the commutative property of multiplication. So the answer should be 391 as well.\\\\n\\\\nBut let me show the calculation to demonstrate:\\\\n\\\\n23 × 17 = 23 × (10 + 7)\\\\n= 23 × 10 + 23 × 7\\\\n= 230 + 161\\\\n= 391\\\\n\\\\nOr I could break it down differently:\\\\n23 × 17 = (20 + 3) × 17\\\\n= 20 × 17 + 3 × 17\\\\n= 340 + 51\\\\n= 391\\\\n\\\\nEither way, it\'s 391, same as before.\\\",\\\"type\\\":\\\"reasoning.text\\\",\\\"signature\\\":\\\"EqUFCpwBCBMQARgCKkB1oBCnSwxtkwk8KsGVdUHWIE6TSxX2/ySAuQSLljHLWs+BqfbM1W598w4mQyUma7VBl0iIt9Fk+w1wg/tkNtFFMhljbGF1ZGUtaGFpa3UtNC01LTIwMjUxMDAxOABCCHRoaW5raW5nWgw1MzY2OTcyNDk3MjhyENrkNIDPvK+G6yste9b7RhWIAQGoAbuRudcGsAECEgytfmKpOOHXlUkupDIaDHj3LYpVa5nLVBmDVyIw+iLDinJyV+rQLJ/kmWokbKFY2A9OOrDRYzp9BXW0LXPsB5NrkgIRbfjAxnXdpApEKrUD9vSd7BewQeq1zpQXk5Pa/59mEZSzdY0a4JJEtYmjEgHtPlfzhmHCPQp6Rp5JIewy3y7OJCibBzxUrSySHhGE6geQ/fplv/H6ZtvIIo7+EZavWOK+ZkbLQszQ9jjxGORpoaU+1/V0eKVF0UhN4mXQIfKI1y7hcRaQOs2k4goZnnMAsmTI2zxTbsw3Ls2xDwBp/+y324SEM78rhnsv6qZ7MmeHJfoPYKNFcD6Ca6d1xn9KQyOphL1pruqxeMSo6JsF6aub5FGAXn5r4ah+ZIdslJ6SMAfl5upXWuVbHpSboqdiW2CJ0OBJLlCjlubvRlmXG9RlSm9B4NQC9xwDidF7qobR6/mwfeJP4dG1OzlXM5AZIYZzRuWp0YDHcv7hLZ8SO3bpJeqZ7dLZM6uTLLprUO3j2xVkgcuvwKHFtY5VwQ+UYZA4FjswZ0jy/mmlxX6/p38uWQErSxLHt+cCGKKo1w8G5pyJlQGkaS9YpgeihT3F2/vnSd/uWMcHObp4BIIo0K+2PFi9dvHvsvGCLik01hgH6XZjL1w5OaI+7vqmvbNJBWs4okoMSCOHTUqcBoxrUhlszScYAQ==.eyJlbmRwb2ludF9zbHVnIjoiYW50aHJvcGljL2NsYXVkZS00LjUtaGFpa3UtMjAyNTEwMDF8YW1hem9uLWJlZHJvY2svZ2xvYmFsIn0\\\"}]\"", "response [\"# 23 × 17\\n\\nI\'ll break this down:\\n\\n23 × 17 = 23 × (10 + 7)\\n\\n**Step 1:** 23 × 10 = 230\\n\\n**Step 2:** 23 × 7 = 161\\n\\n**Step 3:** 230 + 161 = **391**\\n\\nThe answer is **391**.\\n\\nThis is the same as before! This demonstrates the commutative property of multiplication: the order doesn\'t matter, so 17 × 23 = 23 × 17.\"] metadata: {\"cacheWriteTokenCount\":0,\"cost\":0.001709,\"finishReason\":\"stop\",\"model\":\"anthropic/claude-haiku-4.5\",\"openRouter.isBYOK\":false,\"openRouter.upstreamInferenceCompletionCost\":0.001555,\"openRouter.upstreamInferenceCost\":0.001709,\"openRouter.upstreamInferencePromptCost\":0.000154,\"provider\":\"Amazon Bedrock\",\"responseID\":\"gen-1794001081-zuazVI6uaD1QJS8mbLFB\",\"serviceTier\":\"default\"}"]
            """#
        }
    }

    @Test func `real tool calls run, and the answer to their outputs reads as OpenRouter sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .tools)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "openai/gpt-5-nano",
              "messages": [
                {
                  "role": "user",
                  "content": "Use the tool to look up an egg and rice, both at once, then give both results."
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
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 800,
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
              "model": "openai/gpt-5-nano",
              "messages": [
                {
                  "role": "user",
                  "content": "Use the tool to look up an egg and rice, both at once, then give both results."
                },
                {
                  "role": "assistant",
                  "reasoning": "**Looking up food calories**\n\nI’m planning to use a parallel tool to check the calories for both eggs and rice. I’ll utilize the lookUpFood function for each of them. After I get the results, I’ll compile everything into a final answer. It sounds straightforward enough, so I’ll go ahead and execute this plan! Hopefully, the responses will shed light on the calorie content for these foods.",
                  "reasoning_details": [
                    {
                      "format": "openai-responses-v1",
                      "index": 0,
                      "summary": "**Looking up food calories**\n\nI’m planning to use a parallel tool to check the calories for both eggs and rice. I’ll utilize the lookUpFood function for each of them. After I get the results, I’ll compile everything into a final answer. It sounds straightforward enough, so I’ll go ahead and execute this plan! Hopefully, the responses will shed light on the calorie content for these foods.",
                      "type": "reasoning.summary"
                    },
                    {
                      "data": "gAAAAABq7kmLmDfqo-4tkd4bSDaYkQ9pKGg--_GQR7yj0S-MS24b0M8GHrX-xv1eomSwjSJLtOBb4pq3Z0Vz-9RC4tAwvWBLiNGQrPiaAJuj0JCkMjjfk7h2jZAOdKh1T9Unja2kRyfvMLuXcNGbR41IJTYGNLS3hn1pe4aX9OdHHMt1lYvYf0bbY5OGKl05lFq6ssGTlkmB7-97_035aBIDHa0JQYydhVfDIfh-cY4RWPn4pMbQY_IGdfVvyVGFtCMYmdguYc-Gm8OmT_UfVWqP4-UPxT8dH3JXhi3XKKg6eHyxllhIv2XqT2uLL7u5T8yuVASVFFm-YgmOuu3H8o6R-d5utTGkrz4xY1fzOhqceyMeYq7aDPt-2RRhG56aKdiXqKj-yaRd59w-oDxvL5JAEyDqxiWlAIXHeWvG9gu0fLgWYo8csmVPbXv1CB0o4mWBPkjuUZ_VnhGPv7df4m80an8URHMh8HDK5KUxmxAYn1biokd9L-eByEuFNjMn14Usy07sYJRH_YkFsAmv0yZwXL0_8NVzQz7tK827dpuW_rdixQGyO_OlHqzMMPVLgkV5jw6RuVlrY7MDii_v4milmyPGLgXaLLEV7fGHlxytfZSE7XO1Dgc4G8Fjxzp_EDQ7WMWoyjkqxslULJeuncXRKpzg9u9tzCvwyw72dKEYEGtJqe1E609Ax5f6pbtzJUGURqINL8DC9s99t1fCdAoah30ixfO4cRu3FdqaQom54xjHhi2Tozy1-EvJ80y1ZXoB99tLPd8tNtF2X_QTljY3YyP6jgujNeUInjxGRBB4pCK6myNLiFkAvrTzRI0QmzGyimDH6io656TOSDYd45-rbEg8Y62MQB8sdBqF8mEbl5qgN-sr7LqoOsRMZzrIVVoL8cl-x9-V96Hd9kHmyLtxqT50BY6lkhCFQ06IRsSyPuhw9oSYxjclVtJy-KY0RNYAF1OsKDaR5PRggTYP9pYlPJ1ZIdfVuZVq8uQu_V331HgmUe03fI7jQyyDXcvS7vpJdWen9VN1oYXCX40W81HLbVn4GLbVxi6xHGYrfwMLLrnCAO-Nh3HGukn-xtbNVh4qeHwqcLgLF2curSNSGSKYe32L8d63SWkvEzFLl0TZ2t7K1_j8NjnLBCF0L0FJgcCPBAk90CxsMBCV88u9393vL8F2mzu7BspitzFOC3w9aTFnXxJiucGKTrFyOa5LAum3R7jjKpHyEGfPB5IpoiHuAtb-qXXfXkMgJz2P4BwEoEUowNEtWlUYBuVLJZIQnRWInPQoGRzyO3t0CP3zn4Bws44PgNv5UlqElxq9Vfn-ejr61i_hfjFy07wfIMT88sA8L9wq_RyNv3WnOHANfOeISBeJFrFP0tVGGE5Xix5a4VxlbJpptJNqxFAUXHLELQvg4RESOlPXuqQcUl1emykoWAcH07MKFK2PwbjV4kp1iV8h8Zj513NqKJxMoeJFssh6jaxgBzlwYuXc4jCS9BG1Wk2efOdKev_NzVXGQkGa_9SO-Gl_QFFgYiNB6Aj3ZphReMpbRumrIPx5tyLjBIV38fKgnNGl9UzPQ6tjTT6K9x9YCxTHVYjhJyWYec2dsAACYfnERhsswYnxatDRPgW2eJhmfEK9MigIUUbC55XAoazzjoR4yrncaUzcikgLwx2hTA0DiRpTViVCqLNhPr8aH8X5n1W0c3gHz0A3NnMEJSwWy49GBPbVMTKluj1F_z2r8HspDBEFYzaHkbJ2B0QxCb-x0ZJAHORaHluGji4lCImddq3-WTXL9LVFxzLXekUloWxqJixcSuxwP0n04OPh4fskcUvxPRDZjXdrOH-TP-6Av2H-bF6kCq3haGy9Nuizrvmm_ZwYkQWQtJEnf2uno4ALzhN2cmqFz6ykQ__oHJmaZKAitq08SooTzrSd2taou-WKf9uugIF336K77wPuuGKqKGwwm69X0bTuMFF8Benz6Xyk6cSFiG8Otzb3y4TWgfsmBnmkSy04JHvDDklFWmCpUsg9U7MJKoC-4b6vvGhbv-KQCFhVHH5nA-j9j6oVTHgSJY7Rfp4msYInTPl0kCx3DZez-RVOr310lrgHDek2r2vtY7LL2qFWyeQoWiCVJe_ELfZqJDKnezTUZKUMve65cIQ7DsGhUSR6x7wlFEcgPzmRtdKCb7DOqxSeapMoNrWcmUXew0vOBjASQ211kLZb8olk3ZwdyKgWCdcVyM0daigFVDxOhmuAzYoRh_iSIJ0PQq6S7R7n5h84Wo3rhgmD0ifoCXgKvsqFe3ynM0JJcDPFJqziqcR8emRAEuH6eO1SaknPPZkqeu5W3LXwlshkB3B2UgCsosG-s_jJt84LCPtxWMnYAWHtLFo5QOvN2ezIoOgF8L2UpL9I6q-njXu2HdCMgHrY4YYKIID6VVZ-bcxXUWRN0ZlI7zg97HTI6YUXP25_6LJkSqB8U1NXTWstLL3W7S3nlJlkovArA2gLHVsvHGY=.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ",
                      "format": "openai-responses-v1",
                      "id": "rs_87f13c21743cab8537230a01fb4e9310a210517159d15176ce",
                      "index": 1,
                      "type": "reasoning.encrypted"
                    }
                  ],
                  "tool_calls": [
                    {
                      "id": "call_Rb4rQTObmjAeOBnvZgtCcy94",
                      "type": "function",
                      "function": {
                        "name": "lookUpFood",
                        "arguments": "{\"food\":\"egg\"}"
                      }
                    },
                    {
                      "id": "call_bo1gkWwjnWzXF8y3NF6PBAlN",
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
                  "tool_call_id": "call_Rb4rQTObmjAeOBnvZgtCcy94",
                  "content": "egg: 100 kcal"
                },
                {
                  "role": "tool",
                  "tool_call_id": "call_bo1gkWwjnWzXF8y3NF6PBAlN",
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
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 800,
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
            prompt ["Use the tool to look up an egg and rice, both at once, then give both results."] metadata: {}
            reasoning ["**Looking up food calories**\n\nI’m planning to use a parallel tool to check the calories for both eggs and rice. I’ll utilize the lookUpFood function for each of them. After I get the results, I’ll compile everything into a final answer. It sounds straightforward enough, so I’ll go ahead and execute this plan! Hopefully, the responses will shed light on the calorie content for these foods."] metadata: {"model":"openai/gpt-5-nano","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"openai-responses-v1\",\"index\":0,\"summary\":\"**Looking up food calories**\\n\\nI’m planning to use a parallel tool to check the calories for both eggs and rice. I’ll utilize the lookUpFood function for each of them. After I get the results, I’ll compile everything into a final answer. It sounds straightforward enough, so I’ll go ahead and execute this plan! Hopefully, the responses will shed light on the calorie content for these foods.\",\"type\":\"reasoning.summary\"},{\"data\":\"gAAAAABq7kmLmDfqo-4tkd4bSDaYkQ9pKGg--_GQR7yj0S-MS24b0M8GHrX-xv1eomSwjSJLtOBb4pq3Z0Vz-9RC4tAwvWBLiNGQrPiaAJuj0JCkMjjfk7h2jZAOdKh1T9Unja2kRyfvMLuXcNGbR41IJTYGNLS3hn1pe4aX9OdHHMt1lYvYf0bbY5OGKl05lFq6ssGTlkmB7-97_035aBIDHa0JQYydhVfDIfh-cY4RWPn4pMbQY_IGdfVvyVGFtCMYmdguYc-Gm8OmT_UfVWqP4-UPxT8dH3JXhi3XKKg6eHyxllhIv2XqT2uLL7u5T8yuVASVFFm-YgmOuu3H8o6R-d5utTGkrz4xY1fzOhqceyMeYq7aDPt-2RRhG56aKdiXqKj-yaRd59w-oDxvL5JAEyDqxiWlAIXHeWvG9gu0fLgWYo8csmVPbXv1CB0o4mWBPkjuUZ_VnhGPv7df4m80an8URHMh8HDK5KUxmxAYn1biokd9L-eByEuFNjMn14Usy07sYJRH_YkFsAmv0yZwXL0_8NVzQz7tK827dpuW_rdixQGyO_OlHqzMMPVLgkV5jw6RuVlrY7MDii_v4milmyPGLgXaLLEV7fGHlxytfZSE7XO1Dgc4G8Fjxzp_EDQ7WMWoyjkqxslULJeuncXRKpzg9u9tzCvwyw72dKEYEGtJqe1E609Ax5f6pbtzJUGURqINL8DC9s99t1fCdAoah30ixfO4cRu3FdqaQom54xjHhi2Tozy1-EvJ80y1ZXoB99tLPd8tNtF2X_QTljY3YyP6jgujNeUInjxGRBB4pCK6myNLiFkAvrTzRI0QmzGyimDH6io656TOSDYd45-rbEg8Y62MQB8sdBqF8mEbl5qgN-sr7LqoOsRMZzrIVVoL8cl-x9-V96Hd9kHmyLtxqT50BY6lkhCFQ06IRsSyPuhw9oSYxjclVtJy-KY0RNYAF1OsKDaR5PRggTYP9pYlPJ1ZIdfVuZVq8uQu_V331HgmUe03fI7jQyyDXcvS7vpJdWen9VN1oYXCX40W81HLbVn4GLbVxi6xHGYrfwMLLrnCAO-Nh3HGukn-xtbNVh4qeHwqcLgLF2curSNSGSKYe32L8d63SWkvEzFLl0TZ2t7K1_j8NjnLBCF0L0FJgcCPBAk90CxsMBCV88u9393vL8F2mzu7BspitzFOC3w9aTFnXxJiucGKTrFyOa5LAum3R7jjKpHyEGfPB5IpoiHuAtb-qXXfXkMgJz2P4BwEoEUowNEtWlUYBuVLJZIQnRWInPQoGRzyO3t0CP3zn4Bws44PgNv5UlqElxq9Vfn-ejr61i_hfjFy07wfIMT88sA8L9wq_RyNv3WnOHANfOeISBeJFrFP0tVGGE5Xix5a4VxlbJpptJNqxFAUXHLELQvg4RESOlPXuqQcUl1emykoWAcH07MKFK2PwbjV4kp1iV8h8Zj513NqKJxMoeJFssh6jaxgBzlwYuXc4jCS9BG1Wk2efOdKev_NzVXGQkGa_9SO-Gl_QFFgYiNB6Aj3ZphReMpbRumrIPx5tyLjBIV38fKgnNGl9UzPQ6tjTT6K9x9YCxTHVYjhJyWYec2dsAACYfnERhsswYnxatDRPgW2eJhmfEK9MigIUUbC55XAoazzjoR4yrncaUzcikgLwx2hTA0DiRpTViVCqLNhPr8aH8X5n1W0c3gHz0A3NnMEJSwWy49GBPbVMTKluj1F_z2r8HspDBEFYzaHkbJ2B0QxCb-x0ZJAHORaHluGji4lCImddq3-WTXL9LVFxzLXekUloWxqJixcSuxwP0n04OPh4fskcUvxPRDZjXdrOH-TP-6Av2H-bF6kCq3haGy9Nuizrvmm_ZwYkQWQtJEnf2uno4ALzhN2cmqFz6ykQ__oHJmaZKAitq08SooTzrSd2taou-WKf9uugIF336K77wPuuGKqKGwwm69X0bTuMFF8Benz6Xyk6cSFiG8Otzb3y4TWgfsmBnmkSy04JHvDDklFWmCpUsg9U7MJKoC-4b6vvGhbv-KQCFhVHH5nA-j9j6oVTHgSJY7Rfp4msYInTPl0kCx3DZez-RVOr310lrgHDek2r2vtY7LL2qFWyeQoWiCVJe_ELfZqJDKnezTUZKUMve65cIQ7DsGhUSR6x7wlFEcgPzmRtdKCb7DOqxSeapMoNrWcmUXew0vOBjASQ211kLZb8olk3ZwdyKgWCdcVyM0daigFVDxOhmuAzYoRh_iSIJ0PQq6S7R7n5h84Wo3rhgmD0ifoCXgKvsqFe3ynM0JJcDPFJqziqcR8emRAEuH6eO1SaknPPZkqeu5W3LXwlshkB3B2UgCsosG-s_jJt84LCPtxWMnYAWHtLFo5QOvN2ezIoOgF8L2UpL9I6q-njXu2HdCMgHrY4YYKIID6VVZ-bcxXUWRN0ZlI7zg97HTI6YUXP25_6LJkSqB8U1NXTWstLL3W7S3nlJlkovArA2gLHVsvHGY=.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\",\"format\":\"openai-responses-v1\",\"id\":\"rs_87f13c21743cab8537230a01fb4e9310a210517159d15176ce\",\"index\":1,\"type\":\"reasoning.encrypted\"}]"
            toolCalls ["call_Rb4rQTObmjAeOBnvZgtCcy94 lookUpFood {\"food\":\"egg\"} metadata: {\"cacheWriteTokenCount\":0,\"cost\":4.455e-05,\"finishReason\":\"tool_calls\",\"model\":\"openai/gpt-5-nano\",\"openRouter.isBYOK\":false,\"openRouter.upstreamInferenceCompletionCost\":4.12e-05,\"openRouter.upstreamInferenceCost\":4.455e-05,\"openRouter.upstreamInferencePromptCost\":3.35e-06,\"provider\":\"OpenAI\",\"responseID\":\"gen-1794001289-cdMEXQLlZCwGe1t3xrGe\",\"serviceTier\":\"default\"}", "call_bo1gkWwjnWzXF8y3NF6PBAlN lookUpFood {\"food\":\"rice\"} metadata: {}"]
            toolOutput call_Rb4rQTObmjAeOBnvZgtCcy94 lookUpFood ["egg: 100 kcal"]
            toolOutput call_bo1gkWwjnWzXF8y3NF6PBAlN lookUpFood ["rice: 100 kcal"]
            reasoning ["**Re-evaluating tool usage**\n\nI see that we got results by making sequential calls instead of using the multi_tool_use.parallel tool as the user requested. While individual calls are still valid, it would have been better to wrap them in parallel. We’ve already made two calls, so I think I can present the results now. Both show 100 kcal each for an egg and rice, but I should note that calorie counts can vary by portion size and these are generic servings."] metadata: {"model":"openai/gpt-5-nano","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"openai-responses-v1\",\"index\":0,\"summary\":\"**Re-evaluating tool usage**\\n\\nI see that we got results by making sequential calls instead of using the multi_tool_use.parallel tool as the user requested. While individual calls are still valid, it would have been better to wrap them in parallel. We’ve already made two calls, so I think I can present the results now. Both show 100 kcal each for an egg and rice, but I should note that calorie counts can vary by portion size and these are generic servings.\",\"type\":\"reasoning.summary\"},{\"data\":\"gAAAAABq7kmPKLH71B10P1aZHbupsutCPzM__gus_hghuTbSZols-G9Mt0lqtMCbQ0Zo_2WalmOdRVsxeJV5OiIh3sRKK6dy2xR0EryboRq_7fxRUqmM6Pj4myM-TW7SAZ8LHPBQc-q-ZRR6kV6I4IyNSz2_BFruuRbKlrXjBqMlQZI9Bo0ldmkYCivuBJPMyzHuctRypLP4GGVmYG41oJFM3cTtvyRx2LmTb3AizSscosNW65YMOG0f1J-AmvLJhDya7w8zMbl3nXneziO0YQBGA3Q9Vy_Tsujetbo0_VGt9wRny2dUkBYWIFUKwUq9SEfKdiKz6b7JhvYV_nPz9FzO7NjRPXd9l-bIf8KcTN_ESG__mKqN3Djz0xn9qljX_5agHLIn2lbQidzRK3E5gis5A75lKAOUTYjpcHAyD-V2B8snguAb7nk2Pj8HssniB_ZHPON-L5T-dgm7mMrlrvMyf3QYrvfluu3ryodtTkbCHeLxQCZ2xR6c0BdZa4_DIDGxHPvIWQ5W2LO9xuRo6CAg1dEHnKrHXHURVio5YwL5Owbqw-LTg7TizKpop7thVvIVN5qsFVabAylXVpaxuu6EMSApY71V4JGF8il92l8fYp58pmS0wB7Mgok7P1AJB30OLfxRZFCGwRApNMJN7gb1P_BXTjYLFsahZSIeG0vp3AiHnloOzcXyR5Z7wjuHgV7OgLuAQc7lkeW-weLwZWoH8L8VxgAjNh3N0CvoTuhILWW1aJva6VU6tXBpmvafMdH4W1ClLAH-bA_u1maXkEvU8EoByayoI4q_zjhvqF7YEyMiT-qhHRpyAzIBohxaa0F_DzhxEbYD8V1LNZOvqYmFHxU05oZ_BQeHsE8LefUqTTk4jeFjGvQi8pldoivoaqf9zlRgQTLL8ZpWeK8dPLgRxD7DKESSD0z2h4O47ERQC45W8SXR034wLRrmTlKVbSwWM4ZUCJYSiTGRzMu-r4Yi4awMBLcsya6iQNEq11ocQc_mohbNkXEZbFx9ElUAIwtmlYnUqTAZUa-aDZl68rHhYxIq2pyB3EH8SASOEC9ZS8EGqy2iqQqmq8vJdUnR0pKsYTLahNPWUZ222Dkv9DodabLMApiWrARPiX6bs8tFXZcqrdC34CuF5bk0A9N7cb8aqKE201ZogFeTXd12A5IKFybb289cv8sMScKAtcFwb1_19MNw5aTuRij_PF1iohoLjB0iEmSEz4buAuHB5bT6M_oqPujoHxxmtYRdJmlB93Kt-v5g2pTSgdYfOYIdPd8nlTqy-QDpAchMuol8XYGFbCHvVIt-x_oyjsZW94XCKruNje500Cjnoswxe6aR0zIGffumqZBOLY4GjsnA-PMuLW_zvA7WMOVdjn0Oh1O_YqNRU9clRbQ_w8wivWwmALAa68Klt3q_rBjMopK2R53igESof-_3tqTeIEDvWyDaD-TMqgXl2mFxaF7L1K19Lr18eKFDbZ9gClQNEMTA569T_YtCj7Kz7--iA8itR1uZ4EZorDTdQx37t7UykPf1luThwN64kRf8OQgNjyr2Ljj1w6OhsSDF9GlcWH9GmwhwAHXAzy0ujgAvyDf7B7Gxm5FSrdgiMIE1G0wJbCaeyxTKddnAuEwmjKZF-sx4RL3Nq42veJeUdLB0KO8kbYKY1G9Thy2KZ_LZEffkISwyI_UjhDHd-VifzSC2ZN6pH4fKeIS9jDHtjNSNfyRYlyONuSu2TI2RGYMlbkKOdPcrvVL87uemjL5WplUKPbbz3akOEQZtikv1NidRu7pl2UJe3P7o6uYH2fEuM7sV3OurtwPqnz8WIvc6LwoRPObmBnTgNmtNZhAUc0KkyyvARmeqo4ZEG735CJqkYdUv-OgV5YRkdsPwuasanaz8SBUmoqJ38bgSFtl-CjR94-AdOKYx-KZzyAGuzTQyx6iePNe6LWfRXEx6RxCXqaoVHaWOhMMlmUx2IZp08juFRGcSmcooqTTFK-ZoljIcI1f754knC7BSKlTgAXmETKDkjPse2lZuP-8zrB3UqAStea06_ErUvOqc0MIA7Xm34z1KN533l-T_Kk3vSSkVsi7hAo_64h9omZ41OfSelv6o-di3v0RBas6q4TAXzkxQt-6UNG97NVmFnirIUVTm-HJ4f58kJMW5rSBC4XO5cGOqapgKGer37hUXILCH7D4iJIGyn1pEuppMlteH63ZI92FS4O1jzVa5GsNF9azxEkAcvI-1jNNHA14FjFsRLGrd1FTm6aY-fC2mFGK00XRmlZYkvBgRirVc9yLZnjW8S0iugX-pMa27kBrZzI9zkAOkGlgLOFmcfwioil5p8kar7dcghSXQVZBq-K3fyU5pla2PBQgP1btqaWpHF53pAWsE8p_0vExa_O2qlYCTO9MXXfB9HDChGGrv1-BeGx_5mo5UiOsDrOw7wiaVbwK0RcAg8J2ECPnf-5Wp1oGgsPn8W0N4YHhKKVG4ObngyWkw9HOB81rUv-NnGPaqC8ORBi0GQvJpIi0RGbm_LRLMynTuEZOTuZM0JGVes_sgqyz1imbEhusm_R-37AtNEKqVdGEVj7Go9yIb2RkqrjYDLmqWIE2IF_Wp6RMdM2LT_MKBO-pYaPUgcAByA36mMqwyM1qVjyGxf07WxWRSEG5euMaBQw1ovR8IWiA2eDvoN-Wb9xYXssB5UKC7lMErtjhYtC3kmvnoLzFoRmoASqJ1eSk7-_gDqgYkdxMCMxaII2eyzvY85zhYTpSkSO8lbQKNYAN1szO4voZeYC4hh3cdu29_KEoz0n1AhOfOXWnQTSG2Y6Yt3ldQiO8r2nmo9LW3cuGrNu8Q6svdaSNWudrXBKcaxgT6QCRm1VMnSWblU0A_EB4IrlulpIrTKdSFleeDiKFBbQXorAbQz5GNIIlzhGsufeYTjXaIJ_NzMOy-A7eF2gTBdxUFxnPPNvt6LQWrzXS-0GQlq08qPDf2saXRX8jk0fgT5nJ9mVsEVvg64GVkPbM-EN6gU_-hshmeuLNHLrmEd84VDANbAJeASXWSu5nh6IoChmeW4kxahGQc2yJuQp-kQrN9IiC3Yaj7ZC6ZDKkrzeA5SEHTVIWVwtp_kRq93nEI2UvvLZm6c1wRuFaqY6c=.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\",\"format\":\"openai-responses-v1\",\"id\":\"rs_9158c81460e2e7c23e3a3d78f8cc41d4900be1ed720abe653b\",\"index\":1,\"type\":\"reasoning.encrypted\"}]"
            response ["Here are the lookup results for egg and rice:\n\n- Egg: 100 kcal\n- Rice: 100 kcal\n\nNote: These values are typical estimates per common serving sizes (e.g., one large egg and about 1 cup cooked rice). Actual calories can vary with portion size and preparation. If you want, I can look up specific serving sizes (e.g., 1 large egg, 1 cup cooked rice) or different types of rice."] metadata: {"cacheWriteTokenCount":0,"cost":9.53e-05,"finishReason":"stop","model":"openai/gpt-5-nano","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":8.6e-05,"openRouter.upstreamInferenceCost":9.53e-05,"openRouter.upstreamInferencePromptCost":9.3e-06,"provider":"OpenAI","responseID":"gen-1794001292-LlcHyJ5MLAMAugdNvdT5","serviceTier":"default"}

            usage
            input 186 cached 0, output 215 reasoning 64, metadata: {"cacheWriteTokenCount":0,"cost":9.53e-05,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":8.6e-05,"openRouter.upstreamInferenceCost":9.53e-05,"openRouter.upstreamInferencePromptCost":9.3e-06}
            """#
        }
    }

    @Test func `a real guided answer reads as OpenRouter sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .guided)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "openai/gpt-5-nano",
              "messages": [
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "text",
                      "text": "Rate a tomato soup."
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
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 800,
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
            prompt ["Rate a tomato soup."] metadata: {}
            reasoning ["**Generating JSON rating**\n\nI need to create JSON that matches the schema specified. Since the task is to rate a generic tomato soup, I'll rate it four stars. My reasoning will focus on its balanced tanginess and creamy texture while noting it could use more depth.\n\nSo, my output will be: {\"stars\":4,\"reason\":\"Rich tomato flavor with bright acidity and a creamy base; well-balanced seasoning; could be slightly thicker for some preferences.\"} I’ll make sure it’s valid JSON without any extra properties."] metadata: {"model":"openai/gpt-5-nano","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"openai-responses-v1\",\"index\":0,\"summary\":\"**Generating JSON rating**\\n\\nI need to create JSON that matches the schema specified. Since the task is to rate a generic tomato soup, I'll rate it four stars. My reasoning will focus on its balanced tanginess and creamy texture while noting it could use more depth.\\n\\nSo, my output will be: {\\\"stars\\\":4,\\\"reason\\\":\\\"Rich tomato flavor with bright acidity and a creamy base; well-balanced seasoning; could be slightly thicker for some preferences.\\\"} I’ll make sure it’s valid JSON without any extra properties.\",\"type\":\"reasoning.summary\"},{\"data\":\"gAAAAABq7kjCSUD0Whd5VcZrPKGO2PByQNdCnNuHr9VlSgy8QW-oh5_WFwn5jdOG-hDHdJ5GIsJV7wslXXEc0Urlkvk5Di_U-7His64r8VzIJKdk8iICIAT_b250hCqEbcwykOiyohcQauqNsLWNklnUE0ffphKGtUCZnes6IUDF3XiiDE58MbDrDqAqNDIotAEk28Z_ZwTAP6lWzGIZ6o0u375MgdBbFcxDY5ubfXEajRojhYigb7jArSnYzg5empFhRQ2qJDtDI9NefwxICKnkWPJapZCz21X0Aw8EuIyNA-lUfaL5d1a2-mPdx2SiDEOnfdNpUY5_iD8-QiyKUyJcV2c9q-xu3reoTdpqEffw10NOkFCCteyM5wKP1IaHnNpgt_3uzlIzCslvsaum1y69f8_EtsZN1jPtD6Dn5Pk8oOrukRsZxXA3b8MAsKuIK4KdjfMhhPB8lJZomRGdWEJLKdGHWL5m9Mx6wy1LIbssToeDXc672zn3B0lcxVyfqx_ZPRzwxmtHhgpbGx17bpnbvBztgorEh5eVjt3jbIuou6c0IgQXDlAbTl-SbMZLbaJJr_dBKlAbsn3jgg5-GDsvb5cHyRJpPHB5SUdtJ6BSUhEIi8lNoIVmZcf0PKvSgTQqfATXN9xK4Iw6c9UIslqNt3T68Z3-ci6PVhmlLfBIz8jVhd1upy8BcgSO5zTBkdvwFrpYtzl291pcGX0J5KDr3ukx9c_guVGKj6iBmFLUofvPMMhZS91WQC_VfU930wqj6TVP3p78Sk1MXGfttGLo0F4N0zBWguBKxbXdk-L1y9jcoIjIp39wvMDdBtS521nMTGcrRoy5zf9V80RAy8BlVA4Hedp5n41wHToU8q4l200HDbvHCyRzYt4orpqrE-gPq8SCA_ubmjfedxJUc7---MFFOQghDdzUGOG8TUg4c8wBmuYH7UZPuF6U1KlS-HtnP9BZx5XyH3oRTHfRWvCBJWophXA1MmnW0yUoxbi6rlhN1k7RI_8pJY_DBFkmuQ0vA6BA-fx4luHsBMd6KjrKZb_UCG_HHB7MwokIbKORFUUj_203lswopvhIemNcDE2jSkrnoPL5pXyCGGDQ8Jezvac_AFwPp2e_ChjEHYMvfDZ69O9CygHFG2vMFOsGISZzru8FREk6FfGOmeFDHB0DQo8IhFgnLxlirX_eBJm9nS4TjPDOoK7J8WAR1nNUgkUhectgMmnnxpaepcPcIKBHTpR_311eIa4lIpST0I7JzRUs5k-HQ5JAeIs8iPIsRcnPGBDSMN9Nw9Xer11POKhvz2RvaQKZ3NSyaf4QFy_3g150v7fLl90rPotbiTteCcs8_dP9JCsHtcl3uCPqz-Ff2gwXJ-rvfX1nVEa8tUnixmC16LzXhLqRCx77cVQUSdo2RQY72tz-68k-gGbQSYXJoTRj4E01_hbkeNPLVW8GFG0Zeps-3JfXdJFWO79zT0y4oXj8wiMO2apGTQQuV9JHAFnxDh-viGtOyp186DhTimVoiM5Z2GZRB45u3iZ50YLWsgM_raNK_GwN4m8VdBZKJ22k14_0qLEAJKHSLi7655iY-IkjWGRfLhm5dyPhBHDxBqAad0ZLtwI5TYJFmIectptiRDI8BMnJOG11hRILTgASL0nbL_qME9Fehsn331dzwmaGC8x2FxQ-Cc_LLi51exbdqYUU9FaaW1ysRiaiB1EF0YIVsmY_Win9-9dv4wRdydthBL1q9yz-Pt6K5Kv-h5Oc4RK7bjzLDchTfjeiYICFt6fN9mDVH8nQIax1KZN90pU1pJ4VshcG7fNUPnvpOJCUpn36KsqiBTQY9EVpFEfa8x2EcOoc6PiuK9tShG0nzDn-kiErN5W_m2HwI-yvPk_vD3OoDcpzMxcEkP_Tih8XyzbdR91oAt6-5pYWOK0WINHLFvnvRJcdQIcKR62ylnI5H3FGq_JNngOT4Aw9eczGHoTQupJ8FyCVeoC6W6pj1In7ixOIicPQSKkUMebf4ZVxF3-fle2AP0ip2rLPSY3fgnyCXDQVRLFhzHTTGNDWvO-jsF32oH0a3tuI1quzSg_ODqRb8OMUhOwtRzsdHDQArh3lKtBmUPA755IMhgZqSbh3OWz36XfE8wdtpIsyHeJZIwcbcTSFjaPLhaWYmk0hfIxkSoVonPlgxbhcsz1gELvPfs3vR_2tG8Bjl2mfXe9rLtw1ER0x_se9Ufspb0ocr3oh9CgDiNheoJaih3IkRFzhi02SmehoomcKau_sFl7AWQE7iAh7FHpdKVfy9JiXTC-2qnOoZ3QCYXWQRdjQU6R0Uu91wVkiZCvJgae0LL9xb_B3s-y-wQDb8srecVPSRaL2dmN9j7DKnI3OwHYaDw_XCuoAP9OT-vDpSafdkDoMhuD3zl9_c9Bri5c-RCYDaEU7J6UIWCJtZLU9A7cTvCIiqehNfsVwn-JZiGEhLeDjuvfzTEUGw_TxokRvLG-Y5BKTYpeMrF8Gc5QuBTt0HYKPJdaebtv_Xeyal4LD6SCsUVQyvtmNtIoKvdjEc5HFP2xEX-KS3fQ4Dlvw2FDYHTI8iRC3FdItSGxY8G6bXNyxOf5yMV8F2RiQOJ-n868MLh1Tq8DhaWzH02L8LyDMQRNdWDtov0UvVlis62OGW7YEHN4POaAP9Fc38I-R9u-yOZRYT8IP48GmumwwpQbYk5OBDD-ZkoniGo02Zcdeo4orNJj_TxrhOHgdP5Oz1a7y3DCk4IIA4ZADcdfLs6Ue5eZpqyLW0DqDMGLCHC-M6NO4C7o7FJ1ADUg6Awbpg0oVw9m-JkZUZ0AiEduQjBmyz0er2-Lxvj6g-EoZWBCPCScTI255aEg6QF2aQKpW-qbR9H0YECCH1zozmH61oFJT9ghm1LMGXjd8r-7Uy-6swI5RqJQisPmSfV9C4apwhDV3Pl1tbFnJz5ehI1NQLE0QhtMH0fY1tzWLScWc0YBVMOg9JXnFA2SitwKtTk325BItLo9XACsGXegkys2yBzvgM-FTdN94Pd0-FMKlxKaaj81uEW4TyKrjQWCnW54m45Acy8ikYVjmvPMKc07_Wh3029ZrDR-JG0-jll72Goj9VPP5PERPQxOXjWkS0nEiWwnoDg5InUeWxtnbAsYVURSIc8GJI_8F_pDkWoKWKup6se79UKEhYdTWgXzNXmdaIqQUJscTlcryxG3rWKoJS2GQKfEXI2SLC2MxzqOjSF2X0r0WOLcwANAIzzX0WkN6IS7K50T2_1V-46xKgi8x5PeahBgy544T.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\",\"format\":\"openai-responses-v1\",\"id\":\"rs_0b1e704050930be50bf28cce6a987cf7eb5a5b92fc001a361a\",\"index\":1,\"type\":\"reasoning.encrypted\"}]"
            response [{"reason":"Bright tomato flavor with pleasant acidity and a creamy, smooth texture. Well-seasoned with a gentle balance of salt and herbs; could be a touch thicker for those who prefer heartier soups.","stars":4}] metadata: {"cacheWriteTokenCount":0,"cost":7.31e-05,"finishReason":"stop","model":"openai/gpt-5-nano","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":6.72e-05,"openRouter.upstreamInferenceCost":7.31e-05,"openRouter.upstreamInferencePromptCost":5.9e-06,"provider":"OpenAI","responseID":"gen-1794001086-c5uAMBtz7tuchUdsLPAG","serviceTier":"default"}

            usage
            input 118 cached 0, output 168 reasoning 64, metadata: {"cacheWriteTokenCount":0,"cost":7.31e-05,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":6.72e-05,"openRouter.upstreamInferenceCost":7.31e-05,"openRouter.upstreamInferencePromptCost":5.9e-06}
            """#
        }
    }

    @Test func `a host that really failed in the stream ends the answer after its tool calls`() async throws {
        let exchange = try await ExactExchange(replaying: .providerFailure)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "openai/gpt-5-nano",
              "messages": [
                {
                  "role": "user",
                  "content": "Use the tool to look up an egg and rice, both at once, then give both results."
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
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 800,
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
              "model": "openai/gpt-5-nano",
              "messages": [
                {
                  "role": "user",
                  "content": "Use the tool to look up an egg and rice, both at once, then give both results."
                },
                {
                  "role": "assistant",
                  "reasoning": "**Looking up food information**\n\nI’m considering how to use the tools we have to look up food details. I can use the multi_tool_use.parallel wrapper to run queries for both \"egg\" and \"rice\" at the same time. This seems efficient! I think I’ll call functions.lookUpFood for each item and then respond with the results. It’s all about providing the user with the information they want quickly, and I’m excited to get this done!",
                  "reasoning_details": [
                    {
                      "format": "openai-responses-v1",
                      "index": 0,
                      "summary": "**Looking up food information**\n\nI’m considering how to use the tools we have to look up food details. I can use the multi_tool_use.parallel wrapper to run queries for both \"egg\" and \"rice\" at the same time. This seems efficient! I think I’ll call functions.lookUpFood for each item and then respond with the results. It’s all about providing the user with the information they want quickly, and I’m excited to get this done!",
                      "type": "reasoning.summary"
                    },
                    {
                      "data": "gAAAAABq7ki9bBd6NFE8HKzKD-On4l_UlIMiO7FmBR7fWWLp2gehH6u8u7pFOdy1BdCaGAoCIZnvTZ6hgmimPwl_ftEXdEHZBwxt1X_Kv9Bim9zeUU8zKYkLm-eOPD68Iq3cpTQh3XIhNDJRGv17auj34sSvqc9cpaP9-2moYIcblUW03jb9zYsUupB3puynEDS8UyhEim5XeOtTH3IdQdE1HAocmumznFppENldU9Ke-qU1f-A9E9x4ST7uMpXuPzhsssSMaq82TztQ7X3fOIxANc7q9A1JWoL31VbzULAQDSTwferKEbJuY7pIcIQReS_BXFC7ckjIdT9JUlytA4NsUd3bXKNpbvORoIxvI3ct3xpVH3fXoBiv27GBJGRJcKvuFRnwmYkiAT1TC26AB67TkRoEm_5r8JP5mWZzfwXPAWpVzmxtaPL6-91gf_UD2OQHIxcXZ09BDJvfEpKj-PopB5xF3GydKm7VLPofNzKqf8xQxGqm8OVQv4aQK4mNwV2vxRTIXlECsXzxFSYJVjqGoJc004W6CdKB_JYgVij7U0_D5L2ZBiIJyevMziDghiYnCQPVAfcH-XSIQEx4Bjx9PIPy-WxdzWN7KR4Piar2xtvX9LJ8TszjubXwyO0mP60k_qBPw4zqZQ6Gbox_U40wU_dxo3wxv1r9Xlggx1HjTs0DwFhWz_QuykCwBoqFPs1k9ncJRvlScg9vwwYelRcMIHpJhV3A3CgvariJ3KCZmI93kzkVANL126qPgn8Fh7pKN760AJZjzdDyRWsCTlnawYApZ_b_sbDcz7dwfy12B2pcB3LDHeTj_0bfw6QMs0wUhjp_hSdHUM2Yi5S4fA5Q5ZClh80W27RxIGXKfvzPAO5GyTctC_tlbpjxopNfUXc-U02a_0aHh5Wu2-xBjowUPJtwfKGSDOzonIzWVsl1uW1iwO1R7dxRLSsEMHL7fVTMlAS7MEyKWQ9J8Psk16scyoBA3NY6movI0kE2EdVzZPZskL3IsEo9_3cBbxvY-627hm0uKin30HespjuWQQlKoBqA-K1S8ePxclDS47DvlxtDn4uCwhu-d_rgDp9aZd0vCSOfGmjUZvUmFMaU2Yu6lqPuodzrKwXCZAj5BEorWdMkNhCl0dGANpguRCz2IqoGKExQTJsfp2_f074PiVuxBUCsYAm7OBqURrRl4rC6LT8cQiEfnyCT65ilKk4FdPORXRshNUJI4n11b3d2ZRtYowbdsKWpYsWH4yLEw6aLAuXTTo3_HAshaLf8EEsGbXByy2JoFRI_dzdmlQGrCCjEr1Rrv6XaXkz83pMXGuMR85NjgFq34YSksjo18klaTqWEa5Mokg6IyuOX6m9a6juqcb-IwqnyGvWxPJVePHj-DOPEXffSRPU8YqAwli0aMMneDfn6dWyUhUpkHH7yo-tjH-NnFOSPL5SxJCDdF75bpgsyxTa6gwvmhoHs_ef636Ji7-Ufp9HzmvCrcFNnc7HQ3SzqjQ4lr0dFgV4b7u3UyvhXkc_vHirarj279L0hKcVCRCR40KmhenG41QwL1JzP2A4m1_Nx4WyeDuA-yHlaW30X82WDeewb0tT-DGDD-r5LqWLXFyq6va5YuZL4izQGmZwM83L85EjELX71jisasHY1jkY4R4WGXSBe2o5zGB_T_YZZQnAO2zmx0ETUkLMRxOaFNj4V9X0qMwGZbzrK9vIakGtA7b-XqAm-sPeKgiDAu7vGuV5MiXSIIi4Dlfk45LVQHW5VmK6RTOE10IIeUy0rni7PuWw-iscMx3vb98hzHfMGSOwwn-7SF0NdDCcMz9PfpLkcR6yVECnCvxpc4pm5X90O4UMj4fumU4K7XIMELztVg4t6oyqfU1ndhehZYpT72TIZzDFbT3y26HRgzFb-0DVvoLwLuTOEsxKIJXFBHIuN5qpKjY8Gvd4QtXMG5VeiSOFo8pwqThjBs9NRI2q6r31xC7tHpv3cxXt1kw0V5XK7GGDg24AUKm7jGKfJGKZZd8skZ9P8OpEZVpFMJtcBxbAi6e3pz5w_OOtjbuup8-QPsAQ1-kR1k6hSbKCFpHJWgV8uxNVeFIrUCqLR6UdIsin0nOBFxkZap_k-9de6CGjsyQy8hW3egcVEf_9IslV0MZdmtcutdi5Q3nzEPtMrwyiUMHe6VixBU1uhW-JDFgSOZ0kIz_PobK6jcOlPziPbLuaJzIkTo0Pf2bVo1_8IwRoYwI03KK7EvgSAJA4FignZrww-da4wC9OqrBZzH0apx3YbDvf-1L64kpVP5qcRTcOYAweOB-1X0qA4RSfLRpul4gw4Inx_5UyUDsE-_9DJwiIZTVmw10CnuS3SvZH6EROVqwWXoTxsc6_-3MVQ7DbckOtve2KxxaHEEUszvNFn12nA0qGygnLjC_2lFlx3-YUY2v6IrUOm6NqCz5VhcQEJfk6qIxWgYntMRRcYAYgZESheIamH8fOLtppsHxsuNsFY8bv0pE-cM7KVlK7KuE5IhBLouns2SOyf-qW95NMhE1WiRlGLdv9zxG-RYNtWoLiwCNiIGTj3gEX4Tv_YzyCLdj-Ydn2Lg2ZL4dzgRq0hzLOUvQ==.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ",
                      "format": "openai-responses-v1",
                      "id": "rs_a74edf414bbbb63c63f3d90a3c3a48a87f263e8c0743c08b50",
                      "index": 1,
                      "type": "reasoning.encrypted"
                    }
                  ],
                  "tool_calls": [
                    {
                      "id": "call_YhZ5J85qQXCCv9HFdFPcjX1I",
                      "type": "function",
                      "function": {
                        "name": "lookUpFood",
                        "arguments": "{\"food\":\"egg\"}"
                      }
                    },
                    {
                      "id": "call_nCEt77KYp3JxMIf5PNJqCrmP",
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
                  "tool_call_id": "call_YhZ5J85qQXCCv9HFdFPcjX1I",
                  "content": "egg: 100 kcal"
                },
                {
                  "role": "tool",
                  "tool_call_id": "call_nCEt77KYp3JxMIf5PNJqCrmP",
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
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 800,
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

            error
            OpenRouterError(status: Optional(502), message: "Sorry, something went wrong.", code: provider_unavailable, provider: Optional(OpenAI), retryAfter: nil)
            """#
        }
    }

    @Test func `a real answer with instructions, metadata and sampling settings reads as OpenRouter sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .options)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "openai/gpt-4o-mini",
              "messages": [
                {
                  "role": "system",
                  "content": "Be brief."
                },
                {
                  "role": "user",
                  "content": "Plan the week in one line."
                }
              ],
              "stream": true,
              "temperature": 0.5,
              "top_p": 0.9,
              "seed": 7,
              "max_completion_tokens": 60,
              "frequency_penalty": 0.5,
              "presence_penalty": 0.2,
              "stop": [
                "END"
              ],
              "logit_bias": {
                "13": 2.5,
                "50256": -100
              },
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
              }
            }

            transcript
            instructions ["Be brief."] tools: []
            prompt ["Plan the week in one line."] metadata: {"count":3,"team":"coach"}
            response ["Focus on work projects, schedule workouts, prioritize family time, and set aside moments for relaxation and hobbies."] metadata: {"cacheWriteTokenCount":0,"cost":1.575e-05,"finishReason":"stop","model":"openai/gpt-4o-mini","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":1.26e-05,"openRouter.upstreamInferenceCost":1.575e-05,"openRouter.upstreamInferencePromptCost":3.15e-06,"provider":"OpenAI","responseID":"gen-1794002503-FK3d9nqCDcOIIojtNbnL","serviceTier":"default"}

            usage
            input 21 cached 0, output 21 reasoning 0, metadata: {"cacheWriteTokenCount":0,"cost":1.575e-05,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":1.26e-05,"openRouter.upstreamInferenceCost":1.575e-05,"openRouter.upstreamInferencePromptCost":3.15e-06}

            last snapshot
            "Focus on work projects, schedule workouts, prioritize family time, and set aside moments for relaxation and hobbies." ["response [\"Focus on work projects, schedule workouts, prioritize family time, and set aside moments for relaxation and hobbies.\"] metadata: {\"cacheWriteTokenCount\":0,\"cost\":1.575e-05,\"finishReason\":\"stop\",\"model\":\"openai/gpt-4o-mini\",\"openRouter.isBYOK\":false,\"openRouter.upstreamInferenceCompletionCost\":1.26e-05,\"openRouter.upstreamInferenceCost\":1.575e-05,\"openRouter.upstreamInferencePromptCost\":3.15e-06,\"provider\":\"OpenAI\",\"responseID\":\"gen-1794002503-FK3d9nqCDcOIIojtNbnL\",\"serviceTier\":\"default\"}"]
            """#
        }
    }

    @Test func `a real answer from the flex tier reads as OpenRouter sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .serviceTier)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "openai/gpt-5-nano",
              "messages": [
                {
                  "role": "user",
                  "content": "Name one color of the sea."
                }
              ],
              "stream": true,
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 300,
              "verbosity": "low",
              "service_tier": "flex",
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            prompt ["Name one color of the sea."] metadata: {}
            reasoning ["**Deciding on sea color**\n\nI'm thinking we just need to choose one color to describe the sea. The most common choice is blue, but other options could be green or turquoise. It seems like going with \"blue\" would be the simplest and most straightforward response. I'll just keep it brief and straightforward, so I can respond with \"Blue.\" That's definitely an easy one!"] metadata: {"model":"openai/gpt-5-nano","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"openai-responses-v1\",\"index\":0,\"summary\":\"**Deciding on sea color**\\n\\nI'm thinking we just need to choose one color to describe the sea. The most common choice is blue, but other options could be green or turquoise. It seems like going with \\\"blue\\\" would be the simplest and most straightforward response. I'll just keep it brief and straightforward, so I can respond with \\\"Blue.\\\" That's definitely an easy one!\",\"type\":\"reasoning.summary\"},{\"data\":\"gAAAAABq7k5MVh6E-HO7BNPo_T64UZvERrenzDy9_xCSdVYw2N14GGal_t2i247-Hz7BFlSFaYkEpfpVhcXpeV6dJ5DEjBDKU-qwwQRvP5iHTYxCmo3gzys4riOsMc6ExTnjWL2SyEmO4-hxTGWcTsx0NYpQoL6S0RgUnOFlv9kOIYj58yLSamj3Pii6ADbUHGPEDUsFOrj17ljBYUCWYFK1oEiNGoh33caBp23cv3KZVwuGD2-goR9Zl5nHHnGhuLNuJxAYQW7WC-fRvDpj8p6PYhv9QHG_Dv7xefV2HAbHLs54A_s_fbauQSx8gx36GfYQVsI7X47AnCNMUj0kG2x4kJkPObkljbvj9Vwvs0W7nyX4iL_KDxVwk76QuePD4IpzCBVCkVpn05jsCUFujy4CMcC0IkSiM3I431tQc_BPCJgemNk_jEB3-T6G8i8PYtwRISHqKdszV4Vp5OuUMRimvn2mXQQrqdgnQK-Rd0yeZj6VsMAIKBKe1iCrbuBfpJPAJFKa86USURViAlCbTySED7AnmrDvuuVYaPvWPC4y3zTKX_xWEkcLmKiaXWPD69GsyT82_Z3LQU_NZQqp04LRgJ0ICTJ-j05m0z2_aWT0c7kpBvu7Ugyxf0WahLjhyKEjdUcGkQtmI4Qv8-HTccsEyBI58VYuDBhD84Zmj6B-QZs_3amEV_SvrUlg8iRtbNb5WHdFhLuS2c1MzGb9E0FNAfPeS5De4ggg4Cs0vNc3ogLjKIqUHyKr-2qUea-fe5GnIbBNSaXyWkGnE_qck7oxCpFondWYMu2BWP9nbmAFu2jTYvTPlJLIDF1Vlba_BdTQ0ZFXSrEebKknwTmzA2bd1WA7geA1RON1lAAhRzJW1ZKy1aamTvlpLYP9N2aAfxCqBWU0SJw7mzlK4yz1yt_qGfR1ltVYMPnHY1dWgwTdkpZFyCbG64XLwzZkLrlUKdLU5c7wShS4S3Mg7XxTr4XMmN8GURADsbd8w_s62YuOCWUmmx8tq7LqsNlOZkSUt_FoOLCp_Xrr9SLo4Nl-g8pv7vXjsUTTjGE4_QZ5yjFa6I-PbQ_QLapAg8myXbb6kSsRO0YUOJqGH-cyxdQcq93R-Dr-PgBTrX6v6OV_5XwqlBOeBK9k_PmZz6Cd4OrG37Hd5vC587D5mbBXcnaHAJGblX8Bu2oPeH2RxBOKOPBN-7ZeCUqjuWYsrorH5ZYVBu-6l7NBjXXRJXoPMVeMZG8gawDDAM6UxqWJ1ZSeIz1q1Srl9AhwqMNe9n7lXcSlMfImNcIPnu8V7XA2FWouxPguRNUvJsn1EYX5fm7-3Ydeyy51pJK9vDR7gykJYwmO30-HnVjSFomw_Y9xyjq15bPGuqxhBF6CfVLyxUtD1EN6LeD-OQKFk8qvIkAD7VFqMRN_z0SwXVF8KKpR-dUzJXlIKXoM-z67BwVg1q4PBooO6EYpVc7r1aP9GKPGATXEtmD8sL2YFZg2zSdtoUJLvYkaC2ebvWq_ctpT1kFUGy2U0w8-LzoFClbh69LlA-Ei8kSKOeeAEYB43NKEaesonxW27FB4vNs7aLTGDqef4ifi6upkNg7KPgqKcKUIEDyM5U1k3NaxiGJXxYZ1MTmBksy1lnYpPYFjHmYWbBHMqXE84hJf5nn0CRb2bfVSDDrjvSXXb1BdpDY7Q63oG8Txf1JXtt-edu9bmo0TAu0kg3WUt-ru_IhT2z0ETD7NL_B_PUIplVrpAPDgCmlJzMhgy-wcuxmE_8zsQaWbXMdtugx3fRGFd3qM-MplagXizVmdzbs-Hq5c4Zwa7dOzwbVYNb4NFrr-FXV-0OSG9v0BNDNvcjv_gjJUlGKbkKM8l2HHZ4KI2PdYzGD2rk5P81B4AeY67uDEpQ1Dm5QHhQKj555T8XTiiOcpqNUIgwtwpOGTjadgAx6b1cfXqiy70kaiuUwDOIKgtsU5uBtpUzoYf4XSqfZLiIex9ZSK7gnJXzdwYzYvgDIb9bwTCc7l0doDUMqgP39ihfA5PRjZG_JMgnsQ6eAaboTqPwLMMYHr-A-SUgmQ2dT9CXBu3amNcd3Yji-Z5dozxl8RWCvHtyr-4KH7MfADPtAkrnXl5s5qgWg_lOnwXsEUKkN1PZy2eU2rfbE-y5Gp4jiIhG6D7yskcyfz49T5kd2H8p-hS_i5npKAF4mcpOR6jdQ24V_5ucxsHPHc3sjgbPhKhzPDmhUmgUjKxJS0hyLs3SNMKJ4Ert9WMcPMdJaB36Yz.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\",\"format\":\"openai-responses-v1\",\"id\":\"rs_3cac72c44885d205184ebb8b2d658af2f59fbf95c4403be931\",\"index\":1,\"type\":\"reasoning.encrypted\"}]"
            response ["Blue."] metadata: {"cacheWriteTokenCount":0,"cost":8.725e-06,"finishReason":"stop","model":"openai/gpt-5-nano","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":8.4e-06,"openRouter.upstreamInferenceCost":8.725e-06,"openRouter.upstreamInferencePromptCost":3.25e-07,"provider":"OpenAI","responseID":"gen-1794002505-xg5TZ448CsoD2SNZVUzH","serviceTier":"flex"}

            usage
            input 13 cached 0, output 42 reasoning 93, metadata: {"cacheWriteTokenCount":0,"cost":8.725e-06,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":8.4e-06,"openRouter.upstreamInferenceCost":8.725e-06,"openRouter.upstreamInferencePromptCost":3.25e-07}
            """#
        }
    }

    @Test func `a real answer with a fallback and routing keeps the router's report`() async throws {
        let exchange = try await ExactExchange(replaying: .routing)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "openai/gpt-5-nano",
              "models": [
                "mistralai/mistral-nemo"
              ],
              "messages": [
                {
                  "role": "user",
                  "content": "Name one color of the sea."
                }
              ],
              "stream": true,
              "max_tokens": 300,
              "provider": {
                "order": [
                  "OpenAI"
                ],
                "allow_fallbacks": false,
                "sort": "price"
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
            prompt ["Name one color of the sea."] metadata: {}
            reasoning [] metadata: {"model":"openai/gpt-5-nano","reasoningOrigin":"openrouter"} signature: "[{\"data\":\"gAAAAABq7k5QlhQSXf2pYrQFebnSnOL3fF3SIha5wrKakAhjIgS4Yuqz2nHP0jwdhjO2QA3iOyd1lWx0VQ2RmwxhPhRoaa7tZcut2npqt5stgkivGHZmSqPwN97z5shVDhG373OF5gv02eFl5rxjomYES_PJ-1WW4N3WlbIfmLa1k4tQVTvLgX_nMMb52teimKypUG2I0ArObD7LuDqZD8MxQy-2VZ5ifljUj13UhMnOAhkde_4uFED6fOx3eZUytqOD6MRx0B-hUsE7tZC2ptpdlBmivQ91NEk_6nxXhn4LyC5OEaBOhdRpJ_yao7dLVquf22KgUHSN-ZIw-BPb0foiWAhFX-bFKuwph2qQqP2_6DpHwomluoXTxdLtoNxtpLxn3Ns9w5wFvT6NTDwwksiPwpIoMKPHHaGpnfpUdE3srx39OI_1292yevUC2MF4K5bKNzYWl0vu0le4kBAaf31EaDYsCvt3v7SKTXBn6J0t17Ihjg-HGxhePhmDrHuicSgpcCvrxMlYFJuOCkdz_fvVxi6lvPxQDf5odFO1EUUiAdLU6ZpCN60OBgLOURCWhpkNCrGy_HqRIH4Fkv1GnvO2GH33fp4cA5yL-wnHiPz7gtEDiiPjcEUwcFbsIi3BJRwp0WDzZyLZQWy6yVzG3Vr7aop46l9ymUihufcUAjKF4BxXOu44b2l6UWavAkVXkjtxHXw3Ovez5gc0jT5_af4LEOFOkXvDYCAhPY4e13jhr5xrn-YPk8694t3a0WqeTnPmCmKIKQokvyRt6qkgbLc9g0-YhMEAJGqYZYO0OWG7Irotqjnzo7rSdj8NYPnT9zXa8vQkUl9nOsm1P7Pf5buFcWzg7hbKYwAoCyDoujjYfC-CVLiEWvoMm57wbrh6kEmyPShz--fdNMOwbFnclw_A4gE04QEkFfWV4X6Hr65CdqD2xp1IWXVLhTCi1CX-LNNz1EEQ22575WI7NsZ-0jPVImJiWwB_gULJhaZ431OXCLY3D4Es7DdTWPky_byuEjwiD2E-v760-cFgSz2pyzv5JYC6dslEs1KWMdn8054RQKz9TOaqzs2CM2jFTjNol7xjARNfYK7liPA8UeTVFko-6kfzGqqXImVtN9snfhEHPfBpdypG5HqJK9Fhjhlta21YGkEzPd7qzrUmOuC2w_4avU3GqB_yJ8XSPTaJuxD9k3CqjOdwPuUdAgeVxHpICvbqm_S6EDxkrDgEfms9OxSX1Dg--a1m3WnnT5A1rUnbSQcukk9KLNJP4UmB98XUsVSVPFta3FnV1pfgNrQmLHUEtd43ezMj_2IAj209lhMVwvozBDdpi1FTR8lCOxafwzymONs9jH1Fd1uU4fCfRAwEIiFMt2emksxzHQAcaq_pkVbRUP83FhW5OEiwOPZSMjXdB0a9x8Oqydpv63upoQx0sbLcaZxXW0Vhg_tybXToE-JUvDcgE4vmI2DHfzBYGS_iU-AgbCFrzuVXSPGTJOtK3FOymhDnSVLEGhVLRQdF3JlQGv7j2PlMoqLGKV1JL1hMcxLCjTCQKmV737DjeAX428PDM-Z7qjRewPiWTXHN6RtsPOhcUwVTmXJCAOcHvvmTEFzCS5uP96jAfnrq7K4lQs575z2PGNOrS8gULkn5CKF-g95J7UvnJtxceCNha-GeclM783Os0TsWh_DSX9zSRJBHDlARPLWnBYH3MukqY2xTFxCYWywj7V1Zkrf3ruBzWpHT7zk7v2pma4wj6TtAzyl2UI5vApenyVzv4auDxuak8meiaVgXIWWndnFnpqDPoIapTnfQHW9RVDypx7sXIoQIlHiII9IE3GbewBwUVKLJtd4IcvmVMRl0yDF2lONlTRMmPkpxxf3w8EGcssIl4JZIK4CcyKqiAT8VV_wTvxBuneQhly4k0W_Db2nu8Ry1hpVXWUF7qSO1tdpxwOLgrTIBnyikGdBdpQnfKhHoMdbAkRf4aboT0dM2xD0uUB-1h8U3nKaBAq-XJ0tnXGSiUu8XKgF_XA-GFr2fndthBiTqUslg9PXeJrkzsmnr1PKO5gHaFokUHUIm_-TydykEsCzOSyKn6TAdl3BqkbTfG9ZsqMPhk8j2fbs6la09gpPHyw3E-ol17U5QiL-InDVrRYJKJMBw--rKevt2eEW9R0-GEfGl0mxw0_dtX2VixgdjIWn3V012iD5mrgEaVq-1p11mHwF-SZ-emLtQzJAEGVWGj725DLqR8N0pbYi42EzvCBF9HgYRZS6RbOboi7eD9PIBV1Z96xQsQPwVbKYfwwKovZbuCFYuYfyGha_3QhpTSxUV-4wEhmirh2_x8sOIZ24WCBOWcASntSFXkKXjVUt587-Dt7mWIV9yfv7y6DA-Oj3FmLSMJBS_UsdKxLhuBv__26g_wo-x2tCDcks0QYABegW9kVsXdy5TpGDfW96-WYi6JMur1MCFaXBPRIF0J0yjQecB1Q03UNYuK5gEv4U3p_y4k6NsVUBnA8jIMtBiPUMKkiUakxEzhya1UjTC8Ow766ZSiFRCVuL-bQEPqahew19hcdcTwEJmCC7D-QJsE8aI5oe3n8mc-DylRWWjtfYa9tW9GmZxwsvYoAzt8wkC7jJWA6mH7v1rxxD4vxzE-8QWD0Ki20fyEAtJZRzG7rcsMpKSknl2pojGWOS3l60QqfcI15GvHGcZPcXtcsCz0vHWOL0z4_JV5JWmVJJbeSGjYAzFnxesV2LEKuKtzTFIUj8VktEgr7MvWtybV6o3n-VbtAcg5V68oNCIuukGHTRalb1J0wAT8iDTmtr3GvCAEcvM7-om6JsMhcLLxQYNA8k-ac-w52D4q-439u9UmSl4PJ8rEKbMbmSaeah1gr1Ab9yvYBzNBTTgE1Gyy2-Y4bEcwiHMxlj1uggoAPEEzvHQBzKdgOsR26wdbg4HsryaapNDkBMQl2HsjsIgLWinEqETgYM19B4YUHhvf6HO-MDQdEPdJZO9ylRBP27ZSMNMlEGu5mjGc1vS9CHTEPG9MpjyA7AxrEX8RF-RtqAuLyA1u2hEO4hTFpiSPUqg3xP7DGcyQ5nwS-A5pcUezJvaMntQTpWnq5YjwA-LOq6JYNS2X8oHujwmgRe2niqbdGnkBhYCkI_ZTbkKt-l09IBPMx8D8WCmPvuKfEEntlvfTgOjt-3DqyiOfUV-RIqyNMsTNvRl8mCZVElueOGRHoVCzJCHzwbmrXcXPhijz_w8i_lkxfUp3Wa_PuHDEr2NGYQltyI2zCnRbcBcaE-F7HuxPXSSs_gFY5ikg9H4c84WASnWif9B7ErZHIv23vvTEQr1ZZJZHE2cnp6sCaMLhO0_0r9udZS3-FRzznAOBbwhShl1hOWzWkBx8-A-FUXdMtuvCC7QoAxtSlMzjiy_ht0gybNTOjCHUPH2AQPAvuDgANOLdxi_5jurxNlPL01haG6zNZls_oERZF2Ln8_lwaY-Hh-s7RAaltL2Qtd_i2753lCIENihYVnBtqEac6kqjtwY9IoLUd60m75ESHSXpEY_4P6wEMTLgAgIwbO4kM7FS6BrbRS0WxCIasT2-pD0-L7IvApzqWGVRsD2O3gBIHkcaKVDZQt6DLxH4PtTMuLT8sCKbklpB6uWtA_AxJeqdJQ9ogBJvGOv88JciyGR8XokmkFqlHENvI-tL_FjN62rcdNyWANOA6DPPKHwCzQ9Ew6u6DW3o-pU4rboGEZB4rCGm_hMHoWe9-D-24kfQZwhKTvYCt2Wm6kwydEXOYqKTlSYvnbBTA_k7f9FP9KZeHGocmZ_a45y1sLsgQvedln-coKHDjN_c0QXvAEz-6nfUdz3jUpN98hj_ljJLz8NyB47hi4oNvtOmVcsLeMnLnS0AaHMviL-Fc1P-CBM1ldnrvDFkEVJTe3CilFFzqz1IMFpwvuZLo__y6R7cWoIp1LlR0b2rS2u8T5Zt_FPV2SSXqNJMmPecAOrToiILZ_WggZkXLC40-znQ9_ODZnYObnQgPQW7dWXaSxAAgrBcOWX_aY9sbhpW4TxCouvUjlChtjqPWheA1MDPhCQ82Kd8dv3Meb03LC7juiDQdwQ-5YoImmu3IYaTAwFH3NnlcwLFsMze0Jc4czSWz9RYik_StiLbQ-G1JKiSJ3Mj8n2Z0ZDB9g72xPYY4QW1TXhpk5_g4qlkZFLKhrIpB-npf90fgFzj_b0pumdGy2WCXWR73b-hD0hSTeg3xeYDetqsO3-tmEBJI05XNEUy3yQ0YU8VFuOE86cPxSLH5GjlXIPRz1EGrMcbGxNOnXjPr9-6U7SLVnhwWLHkUrY3TpG83TF4fJuFeD9zoxBTGKI2Y-hsS0CsGXEJ20h5ONPfLQQuizsDyjNztQSJ7WS.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\",\"format\":\"openai-responses-v1\",\"id\":\"rs_89a77bb46074646e9ad9e72b34eedd0a9bf31f5e341f1667db\",\"index\":0,\"type\":\"reasoning.encrypted\"}]"
            response ["Blue."] metadata: {"cacheWriteTokenCount":0,"cost":8.785e-05,"finishReason":"stop","model":"openai/gpt-5-nano","openRouter.generationTime":2.314,"openRouter.isBYOK":false,"openRouter.region":"IAD","openRouter.routingAttempt":1,"openRouter.routingEndpoints":[{"model":"openai/gpt-5-nano-2025-08-07","provider":"OpenAI","selected":true}],"openRouter.routingPipeline":[{"name":"content-filter","summary":"No PII detected (regex)","type":"guardrail"}],"openRouter.routingStrategy":"fallback","openRouter.upstreamInferenceCompletionCost":8.72e-05,"openRouter.upstreamInferenceCost":8.785e-05,"openRouter.upstreamInferencePromptCost":6.5e-07,"provider":"OpenAI","responseID":"gen-1794002510-nWI8pfYxvs55wOoCi8CU","serviceTier":"default"}

            usage
            input 13 cached 0, output 218 reasoning 192, metadata: {"cacheWriteTokenCount":0,"cost":8.785e-05,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":8.72e-05,"openRouter.upstreamInferenceCost":8.785e-05,"openRouter.upstreamInferencePromptCost":6.5e-07}
            """#
        }
    }

    @Test func `a real answer with web search keeps its citations`() async throws {
        let exchange = try await ExactExchange(replaying: .webSearch)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "openai/gpt-5-nano",
              "messages": [
                {
                  "role": "user",
                  "content": "Who won the 2022 FIFA World Cup? Cite a source."
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
              "reasoning": {
                "effort": "low"
              },
              "max_tokens": 800,
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
            prompt ["Who won the 2022 FIFA World Cup? Cite a source."] metadata: {}
            reasoning ["**Searching for World Cup winner**\n\nI want to answer that the winner of the 2022 FIFA World Cup was Argentina. It’s essential to provide a citation, even though it’s a past event. I’m planning to use the web.run function to gather any necessary details or updates that could be insightful. So, I’ll go ahead and search for this information to confirm and prepare a reliable response!"] metadata: {"model":"openai/gpt-5-nano","reasoningOrigin":"openrouter"} signature: "[{\"format\":\"openai-responses-v1\",\"index\":0,\"summary\":\"**Searching for World Cup winner**\\n\\nI want to answer that the winner of the 2022 FIFA World Cup was Argentina. It’s essential to provide a citation, even though it’s a past event. I’m planning to use the web.run function to gather any necessary details or updates that could be insightful. So, I’ll go ahead and search for this information to confirm and prepare a reliable response!\",\"type\":\"reasoning.summary\"},{\"data\":\"gAAAAABq7k5UlfLL29FheOquG_Jw1eh-odrPJKHoA9QBtccwijpyEjstyre1KBLzOC0d8vKXnlpyZ0s56MfIc50rdZ6K5IaYiL-2zd2z1dm0umLx4UWr9NGJWSCtZICSJ6LhR_K2mqfLBDe4wm32MU4Gim6BI1jCF-cSUAVxoAB1y-ZdsiFM40PBtevpxp5W2QrCSOorwClzeLjo6E7ja8n3RyHA1tUf-Yt42PPM2PapZVasaCpi4YmlT0o_07dQXSNYJGbQeUOKiyLwwa0JlD6_6qWcbraSSXFdY8Nr11tU8V58O7U1urrL3IxMLmHsRXDEPEgXZjmYd7ux1evwoN_QrHkRmgEjWNFztM2ZbRrGbHNbeo8HmZR6i-n4R0QGSOd-Amw60ZIUHv5h6vkRD04f-PfA9ob3csSTpeis09ZjCtxpA17XAgBa0p7G5KDyORCTyVcSl62aU4aW-PDkyZzYEwQg__GzINOU5h1OAb7ilEFnxSHGZJSg-dFCtybwrsOQ5CqmXAAVPtndzqH3QzZ3rTrGTt0R-4_KXQrxX6gNhBVH8PiMr6ANWOGoiYwz4hlUFe5a8slKLW7JUK24Kdl6vBGVmoDTRAnupVc9Ml-aQMRRh2jjIC8VN2Gk7fwQv0XihMvVfBLrwIJ8YYRnchpAy0vwyPOjyar5uASolOLUsA1VnCkv80zjKg8F4ejci3Ckx2lhB5hS7wMG31sLCvPozhsHjyKsbh0Lr4DDZnM7ZYCo2K-tUiQ2V77mlYTRHv0U8VHpzaRNo0Bm4lWkKS5OLWjoDKkZj4PObiVXzOhsGgxWs3ggx4t2RjUO73K40CJNbYolqxHrCZeWxQkn9fPWRBqFf0rK_m5n9FURDH8yXM4D9vRtm2z72A-FKSyOGz0oa6KxmNOnK84aC0wf0IftIf8BE_GuUTyZRttt5NAAYn12MK6zfMk0tzSfSQbVA-EmgN6X5i6Cj1rV0YYZWiBFTr5tCjDw0lHM5BjOB0rB_jepX0ZxFFdSzA5rU3r8SXGaHYK0mWnJdXtejFw4mR6EqH963F8WoclVo95P27nTgrq1rvF-a1WsyL4CyfQ6Kty-CfuAL-wqgl9HxHKXVxCO_oY3IV2LIHc1ww-6ybf_MwotjRdJcB_x5LilPcls--i19N9ea3xeoBZU5p1KGU7zu8cK3-OPKuSxgJsaefNQ8UaDJFt5PAF8p_98BVvjdI9WmQ_HNGu5S5kkn3nKOzFP83QOaMzu6Bqvh57FBYC8pnpObWpYgr81M_AWCezdqb4mBYeJX4djZRotKloXeySOuKqgNnQoeowa4JPkU7hvdt1IjRWwVcDhgKEmYSZ-JpwKceJH_zmQ-BMz9SehevYMleLvguXRMiShO_dTxcSJZPZw-Cmc5UJfe5zpaOc-sdwOeDHOd8cimhBmq-dZB9GgR_OGDaOSMZNMfS4-Ocj_OO2M8fg_UmcS-WOAwpNYNkUkzZ0qt7TBgVUiAU5UnK5g621AW8jhWySGdtB5aBHLg0SdvLMCcxkZNUDNaNt50RlW328Y_NMlXN17iRtybIrOW0RXdTNaI1SrWUMFeN9BExcToj651bXumhej3cGKDf2VsMQJVel3TLtiRAszXBgApKCBeCqe7D8N6zPBZLyp5jFFpA5yEHJ9T9KbTkMFuzHbf-XA8qmPnVaxMEBaOM2S2nZ4cY0N9KkyOdWl_s2lYJJi3rwoWDr7h_68HC0xoHyVmYfGndLv5DNLAkynAfXeWSMGLBCpV-0O4Nu5UZVfWEGa0_CSiZ7LSatrkHrXofIV7hax-9GsDbREQ1MobPWxLqdkWfCLMcAAuWNcICNslZxvhpn07C9i03O1I1Up8IqaVRxHg-h6kE9E474V4kYbZiYdAQqSSxW007IwvsudbYcxPd-iGFT1xD2omzmZ4Vum8u7rgmdmpjfsNA3vZJDK4GxcEx3krZvO9AUANSjF887R5JlT6C42cIcn69isEpM62jgH60GJ21GiW9CbFTi8O1sXNLGtYNheTptOuc9DQaJtEhWJzMRWki-_dZMyfodVxnKahsVXrxmBwve5I9ITFqd9kVJRg56KTB3tngbJAD3-N5KTH71fiO88q6fzm3jZQHSIFm2wiQE_T7DRLhFQ7v5DDD5DfWttieZjignOSd9dvovH0hRUOkL_iBjkyWooQ-pvwextbJfZr38esePx4G5zIftv6sJDTbpr1M-WN71XfBv5aJLwqQ6CnGQkUB76myxqi6YhCUMyw9Q70NoasPF9piAmmmgNiMyY1XYknFSTPb4qWl9C7bW_Q8sZZy5AZkojqNN872AZvgVhwUdbIoVvAFm5H5A4sdWYE1cP8mZ88YLgwci-ASQq5YCMC9SDf8zKhRDDv-V5bRWCedLqUNwWCz55WErcDqiXLgcYjX9tgqZUjFvrBgyIdbfq36-C2651z47xIap07ePM6o-VBkGiJ_hRUA==.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\",\"format\":\"openai-responses-v1\",\"id\":\"rs_b3ec308ff3852dde5a19b612028676c06bdb12a4b1845f3355\",\"index\":1,\"type\":\"reasoning.encrypted\"},{\"data\":\"gAAAAABq7k50MvtCbT6yqMWHYScTMvBbfnhT1NsC1fdvXF0Z47lJ_wdxZpgIKlDwZMuaAvfSMJTWNgKoJlLT9OMmvA0PubhZRbLuRLVIjLRW-A82F4yoZf5Z_FhkK4IlaDESulcTqOwLcogzq3Mr-QSm54GzAI45IL8tlAq6U99MN5L901NVOKlOsgFfFRRjj5mB4O4ClGVrYhz_XID0spdU-BbSJSJTxpLWLPGimv9mmg3n45TiJq_F0l-29tpnhTkAPdfJrepXGP0Xjok6y_W_PrSS6SkdDa585hVRMV8iQ9moL69ayGo99-Q9zXMYnyw7figOi85p3QAB5xqupMAs3RR-6jwPkMldD4YTeDZRBcue-VjtHF2S3SH8z2Gfuc4pQ_EcrO9e8VaFvMiw89wpBqGUUcb5GaWWWXcr6afPA6-iwHXsMrs9USfNkvrj77lvc8KqNbe66_XNy5fWCX10VsafiLQFNFBbwiUOwjudFIffLyZUh41OQ8Lbdcrw5Xy8gqUT67G7-br98FB1UKbMhRwZ7d5XvnmngtWykohvWR8J7CwYIKHNQ0OZr96q8if52rMieKDjIsgMvfOXl0zwtb2RVHTsUlb5iKBSlCQGcyAY2CI52lINc3VlHML2aqTB3EhPov-p_sgVPR9CXcRXMq6a-Kqg0VM_9yBI7VJKA9k9_M1BqGWNT70SQHtv5kP_KUb29YGzvRxhYzsbpFfTMHJtBnS8WxWpdpyUAzrZgTpvYNRQFddfQ8uyuSOCKumxA0fp0cAPEPV1AZbm4YjswfTprjGUK5usX93ugz271OS1bSXbM_PchZqQKTvy9uOUsDxc7fla4LJH5VXFcPQwTLeYTrNgN1IQoCXq4ShvPoDjQcnjLig2XevzM0pxIHRIFa9GTZa5jpoIzSWGtKObRxD05PrV6EpQmwCwUXyDX4RkeHMOuztC1elVDFmeAsK5CCFG9SOzlb0ya4tEUcrnhAzevrnJSpYsbH0Wg9U04C_i1KHUIi1_MPmYkeWpJCPYbKMYFXOdDlNph4tr-Caff9QkdHscsa_6ohp2ERC2Gfp4fB7I2dzC26rCrwGLkbTZFHOIBCb6QJ3lsQ1A7tiO-hOqcW-Q-z-OI2P-cNyf9jBoP1_RPUp8MsMp3hpzyy1RVlSBGcX7HcUjqhlFFyGzSZgOih88ETDEZI7V8kJ56PYT1PJP8EdNeNyG9209YOVU8a0mWk7nYnbA71dH9pSkRtLbqk3YXvfXuyx9J7121oOByFBo4jPunTcyvZ25lSRPNGZo_7eW17aTs64aJjeB6n3oGi_B1g3pD9xURrF9TnFjYcXn4YLRd_II5O0mbjfMVxorxo_bvIzY0dZDYrQZUEhoIsyEqCVUUQym8KhqY6dnnNqz6X4dDntz-gl22aMuI0juo63fIMfQjpUKe-TSxLmFpgt7tTcSbYjDwWZdSC1jRJ--hF2S4pAvdquK48bCYhdb8Wt-cZcU4Rod_hGpIQZjO4UkxbV4X8FJA5p4cJBq80OO-MGO-1Qgoq0sw4tgOGxi-Vt0AQFycvBJXQrYsx7EuVz4nzg4a0y90sTZ420iFf6H7zG4dcIffoHX7J1yza4_LHk8Pvzp-qgbP5VfdhDa3eDrfbUpP4W-GsP45oFLbZ4Ip8AQYsBVUzMZ9NdnetnL4T8rSyd8ufB6rkWSDSqSmkdHLulw8pe4flmsZAx34xUtzvz728LuNDXaIQlVibto8VV2CqvbIX0cNrGLEck-4dJYlzg1S-A133sfV4Xfe-72AnaGyhp-_faXZpOieKBnUyuv1cQenIjzZ39TCZhT3x9FScCRbYNdJHhfJ9uC6d9U6Hfc3PUS4q2uO4a5uT-qXgzgAxuRg2ZSgcI0sDJw_FH5VwMnzV5k9Hlixj2dVn97Fya-6AJCUtbcxTtlPtthq1L0CNBv3XDbWe77JK4RNkZfHqbzQ6RjJf5IQF-XKaf9cyllAnKKeCoqDPnehZuBVMy0a7Jl3gAePl3y0BP3YQCDVS1Ck9LaRMj6aWapsrdYkuRY8qqo-uXjQn-sD-TRkq0XJry3d4OMcJu7XHcxpwW9JT9dJ7RQa3bD3aTMKPD6kIF8NaFWcYRIbXztDNewxOmgn5wcrnI7tmKMMHAX-lTB1iAqcFKKqj90Af03XUlOdg8RUU8gYjMmS8kuhWFtWv3aqlEObIgc9ArX3zvS4JL7ZsZK-qrOfUVpt_6M9hyD99UeBgjcWUzNmYdSwbc04Xi6piJZNZPuV4NAE0QKZ6GgRZSheHMcuI-FZmRey5yinUucRhy4sQsT5gkib9SHbCqDOy3bEssDx-qVnlE82N77WagRl39VbkpTqZynhCqVZC7Xh9qG227MhbgSDxb4NRhSZ7qumTyHKYY_bjgAjL0nScXcnYjHhPDTKT156-ExM2UHSKTYbzT46R5CGDDxJ9NDiVQ6estuEriGMo8h0julRhRYI9kpNlMmc4xzD-hKzDMnqlgE9YnOW3r9mAOkAtQIZhp93OMHUaZjfxTfNHtyKCB1sLAbU7wX6Tyxc54X0M8GyL3ZyL5RpfhF4Q18uRTTZMPCSwbz-RSqXo0fjQHJObaw07dB1mNrRA-hIpdhvOOAt9VRXL31iiAxnpDUvOtv1uM6nudCAHTcOXjNeRid1d1N4VnN_0TQbOV0gJjrc57OIMZnPdVE6fa9PpdO3hXh0qZ7pOhI1zGigcrsi-D0mFQJKm4zY2a99KWRBiVz2BxRfwqgDRbdcDGlvq9caUTsHzZxNHEpuJx8-pArTNwTsrPPnp-2Eb5wbmYF2yrTXCZNJcW7EOgrYu8yIHjArr58W9v4bJ83KVPycK4POplP7vW3oWqj5P04Br5GN0dnWUwgtz107teLuSF3zcCE98NlE-vzjNeHr2NIDj6PCf7MIlVhxDXVMKq8ndJf0R46O5DELr7DjZaUyVIS6Z1SIPc4RsvYuM-t578cG63BjV1gvLIlDovLzdWLOuc4WdWxwTLeRgib1ma7oedpfdQC757CW84UPBfEiCvsfrch67NThk4fKg8DhuPLJyRuYXzUeBpw7ezv41l2QV4qxA6KuNNRscbw1B5aCff4RpSpw1log7cJTNG-YCyogfrw4sr4qGwokzpCltEhjG5VJ5CnSznWFE-HT8fihVIxHoTRZgvzyQ==.eyJlbmRwb2ludF9zbHVnIjoib3BlbmFpL2dwdC01LW5hbm8tMjAyNS0wOC0wN3xvcGVuYWkifQ\",\"format\":\"openai-responses-v1\",\"id\":\"rs_6ad7b4c93c74edaa61f8f6d2f1c22bd0d0a6d9c6557c3da398\",\"index\":2,\"type\":\"reasoning.encrypted\"}]"
            response ["Argentina won the 2022 FIFA World Cup. They defeated France in the final, 3-3 after extra time and 4-2 in the penalty shootout. ([bbc.co.uk](https://www.bbc.co.uk/sport/football/63932622))"] metadata: {"cacheWriteTokenCount":0,"citations":[{"endOffset":188,"excerpt":null,"startOffset":128,"title":"https://www.bbc.co.uk/sport/football/63932622","url":"https://www.bbc.co.uk/sport/football/63932622"}],"cost":0.0105357,"finishReason":"stop","model":"openai/gpt-5-nano","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":9.16e-05,"openRouter.upstreamInferenceCost":0.0105357,"openRouter.upstreamInferencePromptCost":0.0004441,"provider":"OpenAI","responseID":"gen-1794002513-bqtPHYwdQSw74BsQuOA8","serviceTier":"default","webSearchCount":1}

            usage
            input 8882 cached 0, output 229 reasoning 64, metadata: {"cacheWriteTokenCount":0,"cost":0.0105357,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":9.16e-05,"openRouter.upstreamInferenceCost":0.0105357,"openRouter.upstreamInferencePromptCost":0.0004441,"webSearchCount":1}
            """#
        }
    }

    @Test func `a real response cache misses, with its status`() async throws {
        let exchange = try await ExactExchange(replaying: .responseCacheMiss)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            X-OpenRouter-Cache-TTL: 600
            X-OpenRouter-Cache: true
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            X-Session-Id: <generated id>
            {
              "model": "mistralai/mistral-nemo",
              "messages": [
                {
                  "role": "user",
                  "content": "Name one color of the sea."
                },
                {
                  "role": "assistant",
                  "content": "Blue."
                },
                {
                  "role": "user",
                  "content": "And one of the sky?"
                }
              ],
              "stream": true,
              "max_tokens": 30,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ]
            }

            transcript
            prompt ["Name one color of the sea."] metadata: {}
            response ["Blue."] metadata: {"assetIDs":[]}
            prompt ["And one of the sky?"] metadata: {}
            response ["Blue."] metadata: {"cacheWriteTokenCount":0,"cost":4.68e-07,"finishReason":"stop","model":"mistralai/mistral-nemo","openRouter.isBYOK":false,"openRouter.responseCacheStatus":"MISS","openRouter.upstreamInferenceCompletionCost":9e-08,"openRouter.upstreamInferenceCost":4.68e-07,"openRouter.upstreamInferencePromptCost":3.78e-07,"provider":"DekaLLM","responseID":"gen-1794002549-QLw1cQ1xeyskTRlQZUJV"}

            usage
            input 21 cached 0, output 3 reasoning 0, metadata: {"cacheWriteTokenCount":0,"cost":4.68e-07,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":9e-08,"openRouter.upstreamInferenceCost":4.68e-07,"openRouter.upstreamInferencePromptCost":3.78e-07}
            """
        }
    }

    @Test func `a real response cache hits, with its status, age and source`() async throws {
        let exchange = try await ExactExchange(replaying: .responseCacheHit)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            X-OpenRouter-Cache-TTL: 600
            X-OpenRouter-Cache: true
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            X-Session-Id: <generated id>
            {
              "model": "mistralai/mistral-nemo",
              "messages": [
                {
                  "role": "user",
                  "content": "Name one color of the sea."
                },
                {
                  "role": "assistant",
                  "content": "Blue."
                },
                {
                  "role": "user",
                  "content": "And one of the sky?"
                }
              ],
              "stream": true,
              "max_tokens": 30,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ]
            }

            transcript
            prompt ["Name one color of the sea."] metadata: {}
            response ["Blue."] metadata: {"assetIDs":[]}
            prompt ["And one of the sky?"] metadata: {}
            response ["Blue."] metadata: {"cacheWriteTokenCount":0,"cost":0,"finishReason":"stop","model":"mistralai/mistral-nemo","openRouter.isBYOK":false,"openRouter.responseCacheAge":1,"openRouter.responseCacheSourceID":"gen-1794002549-Xq7RkT2mZpLw9VbN4sYc","openRouter.responseCacheStatus":"HIT","openRouter.upstreamInferenceCompletionCost":0,"openRouter.upstreamInferenceCost":0,"openRouter.upstreamInferencePromptCost":0,"provider":"DekaLLM","responseID":"gen-1794002551-C6lD5ZoBnHGYsT3mUeWV"}

            usage
            input 0 cached 0, output 0 reasoning 0, metadata: {"cacheWriteTokenCount":0,"cost":0,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":0,"openRouter.upstreamInferenceCost":0,"openRouter.upstreamInferencePromptCost":0}
            """
        }
    }

    @Test func `a real second turn reads the prompt cache the first wrote`() async throws {
        let exchange = try await ExactExchange(replaying: .promptCache)

        assertInlineSnapshot(of: exchange.usage ?? "no usage", as: .lines) {
            """
            input 5429 cached 5402, output 5 reasoning 0, metadata: {"cacheWriteTokenCount":0,"cost":0.0005922,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":2.5e-05,"openRouter.upstreamInferenceCost":0.0005922,"openRouter.upstreamInferencePromptCost":0.0005672}
            """
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a real answer about earlier attachments reads as OpenRouter sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .attachments)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            X-OpenRouter-Metadata: enabled
            X-OpenRouter-Title: Coach
            {
              "model": "google/gemini-2.5-flash-lite",
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
                        "data": "UklGRpazAABXQVZFSlVOSxwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAZm10IBAAAAABAAEAgD4AAAB9AAACABAARkxMUqgPAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA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tQCyAKoApACZAJEAiQB3AGsAYwBZAFEARAA5ACwAIwAaABMABwD9//n/8v/q/+b/3//Y/9b/0P/M/8n/xP/G/8f/xP/F/8f/xv/O/9T/1v/a/9n/3f/h/+T/5f/l/+j/5//p/+z/8P/0//v/AQAAAAcABwAIAAUA/f/9//n//v8CAP3/8//x//b/+v/8//z//v/8//j/+v/4//z///8AAAAA/f/6//3/BAACAP7//P/7//z//v//////AwADAAcACgAHAAgACQADAAIAAQD8//v//P/4//n//P/7//7//v8BAAUABQADAAEAAQAAAAAA+v/5//v/+//6//z//P8AAAYACAAKAAgAAwACAAAA///5//X/9//6//r/+P/7////AAAEAAUABQD///v/+v/3//f/9f/2//n//P///wQACAAJAAkABQABAAEAAAD///r/+P/3//v/AAADAAkACgAKAAsACwAJAAQAAAD8//j/9f/1//j//f/+//v//v8AAP//AAAAAP7//P/8//r/+v/8//n/+//7//3/AQAAAAIAAQD//wEA/f/+//7//v///wAAAwABAAMAAgAFAAgAAwAFAAQAAQAAAP///P/8//z//P/7//j//P8BAP7/AQACAAIABQAEAAUA///7//r/+v/4//T/+f/6//v//P/9////AQAGAAMA/v////7//f////3/+//9/wAAAAADAAUABwAHAAMAAgABAP////////7/+//6//v/+/8AAAIAAwAFAAQABAABAAIA///9//3/+P/5//z/+//8//z//P/+/wEAAgACAAMAAQD///3//v/9//z/+//6//r/+v/6//v//v/+//3//v8DAAYABAAFAAQABQAEAAMAAgAAAAAAAQD//wAAAwACAAIAAgABAP///P/9//z/+//2//f/+v/5//7/AAACAAEAAgAEAAEAAAD9//v//P/6//j/+f/8////AgAFAAUABAADAAQAAwABAP///f/7//v/+//8/wEAAwAEAAYABAAEAAMA//8AAPr/9f/1//T/9v/4//3//v8CAAYAAgAFAAMAAAD///r/+//7//z//P/8/wEAAwAHAAcACAAIAAUAAwD+//n/+P/5//v//P///wAAAQAEAAQAAwADAAIAAAD9//v//f/5//f/+f/7//z//v8BAAEAAAAAAP/////9//z//v/9//3//v///wEAAgACAAIAAgABAP///////////f/9//3//f/9/////////wIAAgD//wEAAwAAAP3//P/8//3////+////AQABAAQABAAEAAUAAgACAAAA/f/6//n/+//7//r/+P/6////AAACAAIAAAAAAP7//P/7//v//v/8//7/AQAAAAMABAAGAAUAAgAAAP3//f/8//z/+//7//3//f8CAAUABAAFAAQAAwAAAAAA//8AAP///P/+//7//v/+/wAAAQD///7/+//7//3//f/+//7///8AAP///v/+//7////8//z////9////AAAAAAIAAwADAAIAAgAAAPz/+//6//v//P/+/wEAAwADAAYABwAHAAUAAwD///7//P/7//v/+f/7//v///8AAAEAAgABAAEA///8//3//P/6//v/+f/7////AAACAAEAAwAEAAIAAQD//////f/6//z/+//9//7///8AAAEAAgACAAIAAQABAAAA/v//////////////AAAAAP7//v/////////+/wAAAgD//wAAAAD//wAA//8AAAAA/v/+//3//P/+//////8BAAAA///+//3//f/6//n/+P/6//v//P8BAAIAAwAEAAYABQAEAAUABAAAAPz//P/6//v//v///wEAAQAEAAUABAADAP///v/9//v/+//6//r//P/9/wAAAgACAAMAAwAAAP7//v/7//r/+v/6//v//f/+/wAAAwADAAIAAAABAAAA/f/9//v//f////7///8AAAQABAAEAAQAAQD///z//v/8//n//f/9////AQABAAIABAADAAEAAAD9//v//P/8//n/+v/9////AQAAAAEAAAD//////f/+//3//v/9//3///8AAAEAAwAEAAQAAgACAAEA///+//3//f/8//3//v/9/wAAAAAAAAEA/////////v/+//7//f/8//z//f//////AAAAAAAA//8AAAEAAAD//////////wAAAAAAAAAAAAABAAAAAgACAAEAAQD///z//f////3/+//8//z////+/wAAAQABAAMAAQD9//3//v/9//z/+v/5//v//P///wEAAAACAAQABAADAAIAAAD///7//f/7//z//////wAAAQACAAMAAQABAAEA///+//z//f/9//z//P/+//////8BAAMABQAEAAMAAQD+//z//P/8//z/+//7//3//v/+/wAAAwAEAAEAAgACAP///f/5//r//f/7//z//f///wEAAgACAAEAAAD+//3//f/8//3//f/9/wAAAQAAAAMABQAGAAUAAwABAP///v/9//z/+//8//v//f//////AQADAAIAAgACAP///v/+//7/+//7//z//P/+////AQABAP//AAD//wAA///+//z//P/9//3//f/+//7///8BAAEAAQADAAMAAwAAAP/////+//7//v/8//z//v////7/AAAAAAEAAQABAAIAAgAAAP/////+//7//v/9////AQD//wEA/////////v/9//3//v/8//v//f/8/////f/8/wEAAAD//wAAAAADAAAAAAAAAP7//v/+//7//v/9//7///8AAP////8AAAMAAQABAAEAAQABAP//AAAAAP//AAAAAP7/AAAAAP//AAD///7//v/9//3//v///////f/9////AgAAAP7///////7//P/8//7//v/+//v//v8BAP7///8BAAIAAQD8//3//f/8//7//////wAABAACAAMAAwABAP//AAD+//z//v/8/////v/9/wAAAQAFAAQABAADAAEAAgD//////P/6//z/+f/7//3//v8AAAEA///+//3/+//+//3/+//9//3/////////AgACAAIAAwACAAAA///9//3//f/8//7///8CAAIAAgAEAAUABAACAAAA//////7//P/8//z//v/+//7/AgAAAAMABAD///7//v/8//n/+v/8//z//v/+/wIABAADAAIA///9//7/+//3//v/+v/5//z//v8EAAQABQAFAAQABAACAAAA/v////v/+v/7//z//f8AAAMABAACAAIAAQACAAAA/f/+//v//v/+//7/AAAAAAIAAgAEAAAA/v/+//z//f/8//v//f/9//////8BAAMAAQD///7//v/+//7//P/7//v/+//9/wAAAAD//wIAAwABAAAA/////wAA/f/+//7//v8BAAIAAAACAAMABAACAAMAAgD//wAA/f/6//v//P/9//7///8BAAEAAQD//////v/+//z/+v/8//3//P/8//z/AAABAAAABAAEAAQAAQAAAAAA/v/9//z//v///////v/8/wAAAQABAAEAAQABAP7//v////3//f/9//7//P/7//z//v/+/wAAAAD9/wEAAQD//wEAAQD//wAAAAABAAAAAAACAAEAAAD///7///8AAAAA/f///wEA/v/9/wEAAAD8//7////+//7//v/+///////+//z//P/9//z/+//7//v//f8AAP//AQACAAEAAAABAAEA//8AAAAAAQACAAAAAQAEAAIAAQAFAAMAAQABAP7//f/9//z/+v/8//n/+/////7///8AAAEAAAD///z/+v/9//z/+P/6//7//v///wQABgAHAAUABQADAPz//P/9//v/+//6//v///8AAAMACAAIAAYABwD///3/AAD9//3/+//5//z//////wEAAAAAAP//AAD//////v/9//z/+/////z//f8DAAIAAAAAAAAA/v8AAP7////9//3////9//////8AAAIAAgADAAAA/v////7//P/+//7///////////8BAAIAAQAEAAIA///9//7/AAD9//z//f/+/wAAAwACAAIAAwABAP//AgAAAP7//f/8//3/+//5//z//v/+/wAA//8AAP/////9//v/+P/7//z/+/////7/AQAFAAQAAgAFAAQAAgABAP///v/7//3//v/+/wIAAAABAAMAAwAFAAMA/v/7//7/+//8//////8BAAEAAQD//wEA///8//v/+f/6//r/+//+//3//v8CAAEAAgADAAAAAAD///7/+v/6//3//v///wIABAADAP//AAADAAAA/v/7//z//P/+/////v///wIABAAGAAUABwAFAAMAAwD9//z/+f/6//v/+P///////v8BAP////8CAP7/+//+//7/+//5//z//P/7/wAABQAEAAIABAACAP//AAD///7//P/6//v//P/9/wAAAgACAAMAAAADAAMAAAAAAP3//P/8//7//P/9////AQABAAEABAADAAIABAADAAEA/v/+//7/+//8//7//P/9/wEAAAD//wAA/P/7/wAA+v/8//7/+v/9//7///8BAAAAAQACAAMAAAD+/////v/7//3//f////7///8CAAEAAgADAAUAAgABAAEA/////////v/9/wAA/v/8/wEAAwADAAAA/v/9//v//P/8//v//f/9/////v/9/wAA/////wAAAQABAP//AAAAAAEAAwD/////AAD8//3///////3//f/9/wEAAQD//wEAAAD9//z/+//8//z//f/7//z//////wAAAwAFAAMAAgD//wEA///6//z//P/+/////////wEAAQABAAYABQAEAAIAAQAAAAAAAAD7//v////+/wAAAAD+//7//v////3//P/7//z//P/5//v/+////wAAAAD//wAAAQABAAMAAQAAAAIAAQD///3///8AAP3//f/9//v//v/9//3///8AAAAAAAADAAEAAwACAP//AQAAAP7///8BAAEAAQACAAIAAAD+///////9//z//f/7//z//P/8////AQD/////AgABAAIA/v/8/////P/6//v/+//7//z/+//+/wEAAQACAAMAAgACAAAAAQACAAAA/f//////AAACAAMAAgABAAAA//8AAAEA///9//7//f/9//7//P////3//P/+//7///8AAP//AAD+//7//f/9////AAD9//3////9/////v////7//P8AAAAAAgABAAAAAQAAAAEAAgACAAIAAgACAAIAAwAAAAEAAAD9//3/+f/7//v//f/9//v//f/+/wAA/v/+/wEAAQAAAP3///8AAP7//v/+//3//f/+/wAA/v8AAAAAAAAAAAAA//8AAP//AAAAAP//AAD+/wAAAQAAAAEAAAABAAIAAAD+//z/+//6//r/+v/8//3//f8AAAIAAgADAAMAAgAAAAIAAAD+/wAAAAD+//7///8BAAEAAgADAAMAAAD+//z//f/7//v//P/8//7///8CAAIAAQACAAAA/v/+//3/+v/7//v/9v/6//3//f8BAAMAAwADAAQAAgABAAAAAQABAP7//f///wAAAAABAAIAAgADAAIAAgACAP7//P/8//v/+//8//z//f8AAAAAAAAAAP//AQABAP///v/+//3/+v/6//z//P/9//7//v8CAAEAAQADAAAA/v////z/+//7//r//f/+/wAAAgAEAAIABAAFAAQAAwD///7//P/8//7/+////wAA//8CAAMAAwACAAMAAgD+//7/+v/6//z/+v/7//v//v8AAP3//v8AAP3//v/+/////v/9/////v///wAAAAAAAAIAAwABAAMAAwABAAIAAQD+/////f/8//7//////wEAAAD//wAAAQACAP///f/+//3//v/9//z//v/+//7//v8AAAAA///+/wAA/v/6//z//f/+//3//v8BAAAAAgACAAMABAACAAIAAAD//wAA/v8AAP//AAACAP3///8BAAEAAAD+/////v/+/////P////3//v8AAP3////9//7//////////f/9//z//v////7//v///wAA//8AAP////8AAP7/AAABAAAAAQAAAP//AAD///7//f/////////+////AAACAAMAAQACAAIAAQAAAP/////9//z//f/+//7//v////7//v////3//v////7//v/9//7//f/+//7//v////7///8AAAEAAQABAAAAAAAAAP///////////f///wAAAQABAAIAAQABAAAAAAABAP///v/9//3//v/9//3//v////7////////////+//7//v/+//7//v8AAAEAAAABAAIAAgACAAEA///+//z//f/9//z/AAAAAAAAAQAAAAEAAQD+//3//f/8//v//P/9//3///8AAAAAAgADAAIAAAD+//3//P/7//v//P/7//7/AQABAAMABQADAAIAAgAAAAAAAAD9//3//v/9//7/AAAAAAEAAgD/////AQD///7//f/9//7//f///wAAAAD//wAAAAAAAP7//v/+//7//v/8//3//v/9//////////7///8AAP7//v/////////+////AAAAAAEAAQABAAAAAAABAAAA/v/+//7//v////7//v///////////wAAAQAAAAEAAAD//////////////v/9//3//v///////////wAA/////////v/8//3//v/+//7//v///wAAAQACAAAAAQABAAEA///+//7//P/9//3//f///wAAAgABAAIAAQD//////v/+//3//P/7//3//f/+/wAAAQABAAAAAQABAAAA//////7//v/+//7//v///wAAAQAAAAEAAgAAAAAAAAD9//3//v/+/////v/+/wAAAAAAAAAA//8AAP///v/9//3//f/8//3//v/+//////8AAAEAAQABAAAAAAAAAAAA///+//7////+////AAD//wAAAAAAAAAA///////////+//3//v/+//7///////////8AAAAA//8AAAAA/v/+//7//v/+//7//////wAA//8BAAEAAAAAAP//AAAAAP///v/+/////v////////8AAP//AAAAAP///v/+/////f/9//z//P/9//3///////////8AAP//AAD/////AAAAAP///////wAA///+//7/AAABAAEAAAAAAAAAAAAAAP///////////////wAA//8AAAAA//////7//f/+//3//P/9//z//f////////8AAAAA//8AAP///v/+//7///////7///8AAAEAAAABAAAAAAAAAP////////7//////wAAAQABAAEAAQD///7////9//3//f/8//z//v8AAP//AQABAP//AAAAAP///f/8//3//v/8//3//////wEAAAABAAIAAQABAAAAAAD///7//f/9/wAAAAAAAAAAAQACAAEAAAD////////9//7//f/9//3//f////7//v//////AAAAAAAA///+/////////////////wAAAAAAAP///////wAAAQAAAP////////7//v/+/////////////////wAAAAD//wAAAAAAAAIAAQAAAP7//P/9//v//P/7//z//v/+/wAAAAACAAIAAQABAP//AAD///7//f/+//3//v///wEAAgACAAIAAQAAAAAA///9//z//P/8//z//P/+/wAAAAABAAIAAgABAAAA/v/+//3//P/7//z//v/+////AAABAAIAAQABAAIA///+//3//f/+//7//////wEAAgACAAMAAgACAAAA//////z//P/8//z//P/8////AAABAAAA//8AAAAA///+//7//v/+//7//f8AAAAAAAABAAAAAAABAAAA///+//3//v///////v8AAAAA//8BAAAAAQABAP7////+//3//v/+//7//////////////wAAAAD+//7//v/+/////////wAAAAABAAEAAAABAAAA/v/+/////v/+//////8AAAEAAAAAAAAA//8AAAAA///+//7//v/+//3//f/+//3//v/+/////////wAA/////wAAAAD////////+//////8BAAAA//8BAAEAAAD//wAA/////wAA/f/+//7///8AAAAA//////////8AAAAA///+//7//v///////v8AAAAA///////////+//7////+////AAD/////AAAAAP//AAD///3//v/9//z//P/9//7//v8AAAIAAwACAAIAAwAAAP///v/9//7//f/9//7/AAAAAAEAAgABAAIAAQAAAP///f/9//z//f/9//3//////wEAAQD//wAA///+/////f/9//z//P/+//7//////wAAAAABAP////8AAP////////7//v8AAP//AAAAAP///////wAAAAD///////8AAAAAAAAAAAEAAAD+/wAA///+//3//f/+//7//////////////wAA//////7//v////7//v/9//7//v/+//////8AAAAAAQABAP//AAD///7/AAD///7//v/+////AAABAAAAAAABAAEAAgABAP/////+//7//f/8//3//////wAAAQABAAEAAQAAAAAA///7//z/+//7//3//f/+/wAAAAAAAAIAAQAAAAAA///+//3//f/+//7///8AAAAAAQACAAMAAgACAAEA///9//3//P/8//3//v8AAAAAAgABAAAAAQAAAAAA/v/9//7//P/8//7//v////7//v8AAP7//v/+//7////+//3/AAAAAP//AAD/////AAAAAAAAAAABAP///////wAA/////wAAAAAAAP//////////AAD//wAAAAD///////////7//v/+//7//v/+//3//f/+//////////////////7////+////AAAAAAAAAQABAAAA//////7//v/+/wAA/f/+//////8AAAEAAQACAAEAAAABAP///v8AAP///f/+//7///8BAP3///////3//v/+//7//v/+//3//v/+////AQAAAAEAAQAAAAAA//////7//v/+//7//v//////AAAAAAAAAQAAAP//AAD+//7//////////v///wAA////////AAD////////+////AQAAAAAAAAAAAP//AAD///7//v/8//3//v/+/////f/////////+////AAAAAP///v///////v8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
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
              "max_tokens": 200,
              "plugins": [
                {
                  "id": "context-compression",
                  "enabled": false
                }
              ],
              "session_id": "<generated id>"
            }

            transcript
            prompt ["Keep these.", attachment Photo, attachment Menu, attachment unlabeled] metadata: {}
            response ["Kept."] metadata: {"assetIDs":[]}
            prompt ["What's in these?"] metadata: {}
            response ["Based on the text provided, the only item mentioned is \"Soup of the day.\""] metadata: {"cacheWriteTokenCount":0,"cost":7.27e-05,"finishReason":"stop","model":"google/gemini-2.5-flash-lite","openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":6.8e-06,"openRouter.upstreamInferenceCost":7.27e-05,"openRouter.upstreamInferencePromptCost":6.59e-05,"provider":"Google AI Studio","responseID":"gen-1794002556-XPHC6H5L5U7DUY0UHW61","serviceTier":"default"}

            usage
            input 575 cached 0, output 17 reasoning 0, metadata: {"cacheWriteTokenCount":0,"cost":7.27e-05,"openRouter.isBYOK":false,"openRouter.upstreamInferenceCompletionCost":6.8e-06,"openRouter.upstreamInferenceCost":7.27e-05,"openRouter.upstreamInferencePromptCost":6.59e-05}
            """#
        }
    }
    #endif

    @Test func `a real key OpenRouter doesn't know ends in its error`() async throws {
        let exchange = try await ExactExchange(replaying: .unknownKey)

        assertInlineSnapshot(of: exchange.error ?? "no error", as: .lines) {
            """
            OpenRouterError(status: Optional(401), message: "User not found.", code: authentication, provider: nil, retryAfter: nil)
            """
        }
    }

    @Test func `every recorded failure ends in the error it maps to`() async throws {
        let failures = try await [
            ("invalid key", ExactExchange(replaying: .invalidKey).error),
            ("unknown model", ExactExchange(replaying: .unknownModel).error),
            ("context overflow", ExactExchange(replaying: .contextOverflow).error),
            ("guardrail block", ExactExchange(replaying: .guardrailBlock).error),
        ]

        assertInlineSnapshot(of: failures.map { "\($0.0)\n\($0.1 ?? "no error")" }.joined(separator: "\n\n"), as: .lines) {
            """
            invalid key
            OpenRouterError(status: Optional(401), message: "Missing Authentication header", code: authentication, provider: nil, retryAfter: nil)

            unknown model
            OpenRouterError(status: Optional(400), message: "vendor/no-such-model is not a valid model ID", code: invalid_request, provider: nil, retryAfter: nil)

            context overflow
            LanguageModelError.contextSizeExceeded contextSize: 131072 tokenCount: 175000 "This endpoint's maximum context length is 131072 tokens. However, you requested about 175000 tokens (175000 of text input). Please reduce the length of either one, or use the context-compression plugin to compress your prompt automatically." metadata: [errorCode: context_length_exceeded, status: 400]

            guardrail block
            LanguageModelError.guardrailViolation "Request blocked by content filter: [BLOCKED]" metadata: [errorCode: permission_denied, status: 403]
            """
        }
    }
}
