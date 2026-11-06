import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

/// Exchanges replayed from what OpenAI really sent, so these pin how real streams and failures read. Ids and what shows
/// the account or its location are swapped for fake values; encrypted reasoning stays as it came. The streams and
/// failures a real host can't be made to send stay hand-built, in the other suites.
@Suite("Executor: recorded exchanges")
struct ExecutorRecordedExchangeTests {
    @Test func `a real streamed answer reads as OpenAI sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .text)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-5-nano",
              "input": [
                {
                  "role": "user",
                  "content": "Name one color of the sea."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "reasoning": {
                "effort": "minimal"
              },
              "max_output_tokens": 300
            }

            transcript
            prompt ["Name one color of the sea."] metadata: {}
            reasoning [] metadata: {"model":"gpt-5-nano-2025-08-07","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq7kmR9Yglnh4-5SC_iknJQHaAOALzIG3iSYSl4_mULav75lVpYEnjEe1tetAYM6MOsfRw6iABjYc71563B9o0n1AZBXqAB3Nc_BgIm1RcyXgT824MaCQKypZraFiFI3sVe95CTSH21_hOYUY5OGkaSVUHAljmg353lBiyze_9sV5ahq0yfsU9cv13psym6r-f8Pbp2qpfPy-6ZXxcAbsWkvYeaH7nWMFPxtKpMykuy5M6Uh5nKlwcRQYLU9mXL7nV_5IDGFgjpLi4AnLnOr5bA0RdqHSzbVLSTI2VWZB5vVG_ZrmygrYl97FaFuoL4UtcUgV77st-lI_NKr91GbI_P6ocy3nSjHs5E0b2GmtVrjDMsWQv25vV5xbuOrrOPibypXnDaIOJIw7iCsgNZoC11C2uQOYotznQ31kJWbPhGNo30sbFTre5Z25nfp-8utUct2tWJmQY6pWkMnQRhS-csaS1OvadpcU50y1-K3uIlGuDx4VoFjVi1dm3MYDI5AYI9Y2PNz3ixjZLg6_K4irQv66mk85WXKAu-1_T1XkM1w9iTkYzukscUdmKUOpFUBnTQD5hXRgvxzhpofc-0XImq4x6nDHM3KsxmNNLBKsDVMLB3aO9YM4X5viR6-M1V-8siS5fCeVqZRC-is1BpZJe5JcZiQkbZmXH8nqOYBfULDhd3ja-goKzsvVYHU4M4wE499qIPMuPTvOmvQAZrpJHIiTMp84za6HOWpYdE76lNBvsHr9TEw99t5rp8OTynW40G5U2AVnyVGgj6M1cW4FeiIMAsFe_0YQD7TnwY_O_7Ss0sjeNtanyzDgRgK8rV9ds5TwiQ3LIv7ZyHa3q3V4yGNv6iF-PLfl6Z61gY7GaXimaWnSFG_8QiUznLXrcvp4RQLN6QAyJxrVqP4961umC90YofNmitw1uixS1MZKHDUilPv_4pcf6jEzfhQEBUJA6X5yxyuqwokEu1QZKIrcCgvKRysylwyI31pAc-m-zxYKvP29A2yu2G0syqREx623Zz572PVxd_PSI_rmRU6_IOZJ6cqrNtKQjM6EMume2_m8QIrtkvsiHBVMX03EeS1NAHZw293TlOiRcHdKAcnA93H0DISPe693k5pQoMO2FST_TAwoDnzY0PDQ6l-m5nR6wZpz6kyuteZu5iEFKK6Bdaq9uMCSBfKqQqAr3_YOzSlSpGBSVH8DInPCLjMH7ud22J42bGHc-59-8tRVhOsOo7fg8OFDZ1b9xfV_Y6cSZ9LtMwX7q503xD9Fhd6FSi3y6XjeFfv4p2WfB9QA6BGnyZ4z81E06ZpriruwYpYZu4Kw6H9eDsdSnvZ2lhF7gqOLUSzGK9Vh0GBSWUyG4x8pCHe4WnoOpq0sqCzZf8kwuDigT8DXjQy-wczUeiJFuQqY5TqFTKKZAIAhr9GJv5SuRrwc4H3oWYHD8JweCx2cPK5Y9XxffyV55Joqs-m7G61yM_sWHQiRKFyM0-hvyaBdkWbKZqYDaWX1Zl2DKJ5VO8vCxQffHRm-GIyL3l1_n5TtNakNfetzwngyIRzWNlJOUJ6-KyDNDdv4UlvLl95HgxutrnJ0oZ997e4Oz9veXU_zv1ograLs5DKF0nB5Gi9Y-SYym1mqXcxh1b4j3b35BYpySiZJmACcWWnIokfuAyxb8GBIOswCwm79kpKi1T2Tx2a2uciUhbHnNIPaZX27xD3oBoSzhirCqEN2DhNv59M9iKpDYmHcS31elilgim14LHWXnMompVrzYpTTs5pvr6ZU5M1ivPYNoytgTSzwf7enUnoHmtyCek-9arMVg7ivpDbkkWg==\",\"id\":\"rs_d1ed60f47298485d3b4ba768d06166f4132dfd8c441144a790\",\"summary\":[],\"type\":\"reasoning\"}]"
            response ["Blue."] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-5-nano-2025-08-07","requestID":"req_1","responseID":"resp_3cba0b7f18ac52680254e110b223921e34b858ee1d3be7f9bd","serviceTier":"default"}

            usage
            input 13 cached 0, output 20 reasoning 0, metadata: {"cacheWriteTokenCount":0}

            last snapshot
            "Blue." ["reasoning [] metadata: {\"model\":\"gpt-5-nano-2025-08-07\",\"reasoningOrigin\":\"openai-responses\"} signature: \"[{\\\"content\\\":[],\\\"encrypted_content\\\":\\\"gAAAAABq7kmR9Yglnh4-5SC_iknJQHaAOALzIG3iSYSl4_mULav75lVpYEnjEe1tetAYM6MOsfRw6iABjYc71563B9o0n1AZBXqAB3Nc_BgIm1RcyXgT824MaCQKypZraFiFI3sVe95CTSH21_hOYUY5OGkaSVUHAljmg353lBiyze_9sV5ahq0yfsU9cv13psym6r-f8Pbp2qpfPy-6ZXxcAbsWkvYeaH7nWMFPxtKpMykuy5M6Uh5nKlwcRQYLU9mXL7nV_5IDGFgjpLi4AnLnOr5bA0RdqHSzbVLSTI2VWZB5vVG_ZrmygrYl97FaFuoL4UtcUgV77st-lI_NKr91GbI_P6ocy3nSjHs5E0b2GmtVrjDMsWQv25vV5xbuOrrOPibypXnDaIOJIw7iCsgNZoC11C2uQOYotznQ31kJWbPhGNo30sbFTre5Z25nfp-8utUct2tWJmQY6pWkMnQRhS-csaS1OvadpcU50y1-K3uIlGuDx4VoFjVi1dm3MYDI5AYI9Y2PNz3ixjZLg6_K4irQv66mk85WXKAu-1_T1XkM1w9iTkYzukscUdmKUOpFUBnTQD5hXRgvxzhpofc-0XImq4x6nDHM3KsxmNNLBKsDVMLB3aO9YM4X5viR6-M1V-8siS5fCeVqZRC-is1BpZJe5JcZiQkbZmXH8nqOYBfULDhd3ja-goKzsvVYHU4M4wE499qIPMuPTvOmvQAZrpJHIiTMp84za6HOWpYdE76lNBvsHr9TEw99t5rp8OTynW40G5U2AVnyVGgj6M1cW4FeiIMAsFe_0YQD7TnwY_O_7Ss0sjeNtanyzDgRgK8rV9ds5TwiQ3LIv7ZyHa3q3V4yGNv6iF-PLfl6Z61gY7GaXimaWnSFG_8QiUznLXrcvp4RQLN6QAyJxrVqP4961umC90YofNmitw1uixS1MZKHDUilPv_4pcf6jEzfhQEBUJA6X5yxyuqwokEu1QZKIrcCgvKRysylwyI31pAc-m-zxYKvP29A2yu2G0syqREx623Zz572PVxd_PSI_rmRU6_IOZJ6cqrNtKQjM6EMume2_m8QIrtkvsiHBVMX03EeS1NAHZw293TlOiRcHdKAcnA93H0DISPe693k5pQoMO2FST_TAwoDnzY0PDQ6l-m5nR6wZpz6kyuteZu5iEFKK6Bdaq9uMCSBfKqQqAr3_YOzSlSpGBSVH8DInPCLjMH7ud22J42bGHc-59-8tRVhOsOo7fg8OFDZ1b9xfV_Y6cSZ9LtMwX7q503xD9Fhd6FSi3y6XjeFfv4p2WfB9QA6BGnyZ4z81E06ZpriruwYpYZu4Kw6H9eDsdSnvZ2lhF7gqOLUSzGK9Vh0GBSWUyG4x8pCHe4WnoOpq0sqCzZf8kwuDigT8DXjQy-wczUeiJFuQqY5TqFTKKZAIAhr9GJv5SuRrwc4H3oWYHD8JweCx2cPK5Y9XxffyV55Joqs-m7G61yM_sWHQiRKFyM0-hvyaBdkWbKZqYDaWX1Zl2DKJ5VO8vCxQffHRm-GIyL3l1_n5TtNakNfetzwngyIRzWNlJOUJ6-KyDNDdv4UlvLl95HgxutrnJ0oZ997e4Oz9veXU_zv1ograLs5DKF0nB5Gi9Y-SYym1mqXcxh1b4j3b35BYpySiZJmACcWWnIokfuAyxb8GBIOswCwm79kpKi1T2Tx2a2uciUhbHnNIPaZX27xD3oBoSzhirCqEN2DhNv59M9iKpDYmHcS31elilgim14LHWXnMompVrzYpTTs5pvr6ZU5M1ivPYNoytgTSzwf7enUnoHmtyCek-9arMVg7ivpDbkkWg==\\\",\\\"id\\\":\\\"rs_d1ed60f47298485d3b4ba768d06166f4132dfd8c441144a790\\\",\\\"summary\\\":[],\\\"type\\\":\\\"reasoning\\\"}]\"", "response [\"Blue.\"] metadata: {\"cacheWriteTokenCount\":0,\"finishReason\":\"stop\",\"model\":\"gpt-5-nano-2025-08-07\",\"requestID\":\"req_1\",\"responseID\":\"resp_3cba0b7f18ac52680254e110b223921e34b858ee1d3be7f9bd\",\"serviceTier\":\"default\"}"]
            """#
        }
    }

    @Test func `a real answer with a reasoning summary keeps its reasoning`() async throws {
        let exchange = try await ExactExchange(replaying: .reasoning)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-5-nano",
              "input": [
                {
                  "role": "user",
                  "content": "What is 17 times 23? Think it through."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "reasoning": {
                "effort": "low",
                "summary": "auto"
              },
              "max_output_tokens": 1200
            }

            transcript
            prompt ["What is 17 times 23? Think it through."] metadata: {}
            reasoning ["**Reviewing multiplication approach**\n\nI need to calculate 17 times 23, which equals 391. The user suggests I explain the reasoning. I can break it down: first, 23 times 17 can also be seen as 23 times (20 minus 3), giving 460 minus 69, which equals 391. Alternatively, I can think of it as 17 times 20 plus 17 times 3, or 340 plus 51, which also results in 391. I'll present this clearly in my response."] metadata: {"model":"gpt-5-nano-2025-08-07","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq7kmWl61sNXIhWmqIhH0eJTTUuo1FGj1uosmfWLdcY6jG8TIwu8I84Bi-Vfw9oSh94rOoM58b524j8pS-UmXp9P2vXoqnIcT-Hpjd5d7Ny8EqAFncwniKEymTh4HFuzREsqKOra4T3tp14lc9LJP9LGaiFTwu4mvfZV7SWCa7Es3lLQcUDn7KCLF-kinm-s96g2ab-QpAFBJ4OdfNMds5yjNXiUXJencaYRxE43gW_86IKaKhlWMd8Dxli9HqdAwzL_CZO4ldt-m8BwfS8ZsgpSbY1Tni9U0s2QgFri2UvarbLcgSNxuFmYQPqsbn0rZOeNHil8-kc2Bygs8-XRrVYY_seDFfaN-FVTwmQ-Sqo_vBVPYFOU0HijhvHgT3wiYQlBejex3zSDRPiN3GSpvGUM4YEcMBZmJYeNetJQYV_CFdwuhypTYQDoF03j-XGZKEcCiQel1xlLPRzqoZCNfjlMfevIbsute06aFuzLJgqX39bquYeB4aLZvdX5cmCazP15drJuF3U9Vn8EWXYIL4-GD5NMwkb70_Lqr0GL-JWdLZ6iuHeUjjsG2T1OjG_fZrKrMdTNSyzdeCt31Ru95a4eAyIxiBO3H4K46t64gHzzmZLSgi7Ob8LZfzHBpUw0yAt6bVdyWd4Z5f5Ptl1HTTXTBqODW4QWT2bemn2nR6kRsWbvDf7_EKq8jvSUxKU1L50o9A7n8qiDHZl0LlaL4GL0W0ARJp202VaJDamp999-JsDPPnShmlTcKfldqImeRNjSJfBZHVtH1Mk_eg1KwmGqePqszW02PEQfeZlG9-GD9zXdvGt1VgQhzxq1CSK0C8q0JQ8lVFAq2vAKCPjuOClM8pZBxgMG_KJEH4QSKa6SkV80z2f9_SejPxjd3eIaexnauJaMTsoQOelfM5DT9wBOCfeS2jUK4mMPP6nS2IVd9b8lsuNkOLewPzeon_6dkCSjE7wlKdS5RavoD0DCiUaS1h1CKuCeH_-uNBkYQj0VyIn1n9pDXUIO80hQlPrJ-PaFCQz4r4PUWK2X5eSYzUkok5GrBDAK4jhuoR91BN9KE8FIV7THvy9ps5imUgAKR5Www_wbrk8pjglqLUwG3VNoROVqRZV-IlAzOcNld1aUkRqWxvtSL8O6YR2KMK5vE6Zo75pyxE3rPEtj4DrMevLlMGsN1eNX4ZMf40Swhf4hQNc9_8qVTM_lf3b_hBZ7JQI__R4dWZDsPcaQvh-lBykCYNu1ATHSYrIj-StJa3iXSGgriLACIGixbPGrGwE7OS0mlLpNsIxAN42Xfn-YTh7y6dvAirlaol_m4efDQHqpDoLstFwqlNdRrPmv7nE1HP_CgZCcXID_F-2qaPcIJNAykWrIR7fbYYLe85lAfmy8SBOnbxbQK9g6bQpHIj1zqb4dJXiQQ4nDlwQMFDTRQkfRIE6ubfS__H9CbyZtToGkCdYll-6Xa7Wa6ig2HDPSwONRYFCBr4gxGFzposxp1JuhGc-ortYXykVkVlq_MJ7jdqJmv3lXCJLRjLIuTICZ1DTaWbjDUoU5c9Z2QhiYkYci_f_XEkY0orAOx28FoJYS3yshPnZOx4DN_Ee-RjElC8HPjf8VZNxUryiE8DW9b38aV47eeSY2jkBKsDPB9ENjE6t6UR4RjNfIjoySxZAWioEdoDTFTwFFzeo5FV2lK2xOQ3bB0uSsqu7O_jnVNoxrwIQO3B7tKVZ64DiKtJaEqUf5VjneveH6RV0puTCgsMvv8sz9ZW6igEunF6-l2K_5zO_T5xrIiMNcEPbAAi61AIMl3VFb_JBcQeSdCtp8LEPlER6GwALYPsCojs9-AqNfAVdFVSAxM8_PL9mx-g0hST6lHC4eAKiFuchslCnAFNCuoNHAgTL6Ga6YPMyukyx0H6KIX9Yr-OASDH7633xyBqN03EGObzvMvMsUomqSTZgBO-yaaREzew-BriTaQ0Fv6DEH68v8C_UfMlYzsU3295Ff7EKEApPNmeXb4o6HlPWOI0vCVraieDTYbuE0D__ZrT6pmyCgpfR6-jzfl9JWskoBjYIPHhevv1DYVreYXTyF76Qf0H9AXyjyjQjVKwIz4jKDrnVB1bZzXa_ePBCNel9cZAaOLSa2ago8jtKqPo2gES5aj8avDknIZOivw_2w94H8POTveTcz-KaS4O0AgNLaJYzYrnUCAC5rPMjFl7TgQDKIrT5FsHpmN_5KDVUmTrVlMKc6b078ALnuo-WC5lWccbWva-xhegSQEaWxSCe7hWvqyklgwIZYJFlc2oI0qS1bH3CtSqAKmzoN6ZhH34patR3tweOiGz5cKJxp5tS1Hy3oyLBsIwlPGh8cAfnFCOszynLi2BzGBaGQLBl76nt5W70UtmW3KOTtcQLItueiqFqsunECyt3nuBR4zHqUGOAQ_C7dEwbAB9YlefNwWcShYoW7mR42OMeM3UPFWjxf8yNd5YrD7xp0Ke2Ime5QU6vIhWQ9KgtQByzsk_mvg8ueMHOLZlkdEGD1i-Y0-m7rc4q4zYeNwjNk9ZxWPLI9I58PDwGYLAtxTNBsnnbdz5m5es\",\"id\":\"rs_af630fb07c838bed937afe44f27d296283c7e0a8225c804338\",\"summary\":[{\"text\":\"**Reviewing multiplication approach**\\n\\nI need to calculate 17 times 23, which equals 391. The user suggests I explain the reasoning. I can break it down: first, 23 times 17 can also be seen as 23 times (20 minus 3), giving 460 minus 69, which equals 391. Alternatively, I can think of it as 17 times 20 plus 17 times 3, or 340 plus 51, which also results in 391. I'll present this clearly in my response.\",\"type\":\"summary_text\"}],\"type\":\"reasoning\"}]"
            response ["391.\n\nThink it through:\n- 17 × 23 = 17 × (20 + 3) = 17×20 + 17×3 = 340 + 51 = 391\n- or 23 × (17) = 23 × (10 + 7) = 230 + 161 = 391\n\nSo, 17 × 23 = 391."] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-5-nano-2025-08-07","requestID":"req_1","responseID":"resp_7a90aec18ffbe3cfe9235fbf72359ce57f052b047abd003de2","serviceTier":"default"}

            usage
            input 18 cached 0, output 174 reasoning 64, metadata: {"cacheWriteTokenCount":0}

            last snapshot
            "391.\n\nThink it through:\n- 17 × 23 = 17 × (20 + 3) = 17×20 + 17×3 = 340 + 51 = 391\n- or 23 × (17) = 23 × (10 + 7) = 230 + 161 = 391\n\nSo, 17 × 23 = 391." ["reasoning [\"**Reviewing multiplication approach**\\n\\nI need to calculate 17 times 23, which equals 391. The user suggests I explain the reasoning. I can break it down: first, 23 times 17 can also be seen as 23 times (20 minus 3), giving 460 minus 69, which equals 391. Alternatively, I can think of it as 17 times 20 plus 17 times 3, or 340 plus 51, which also results in 391. I\'ll present this clearly in my response.\"] metadata: {\"model\":\"gpt-5-nano-2025-08-07\",\"reasoningOrigin\":\"openai-responses\"} signature: \"[{\\\"content\\\":[],\\\"encrypted_content\\\":\\\"gAAAAABq7kmWl61sNXIhWmqIhH0eJTTUuo1FGj1uosmfWLdcY6jG8TIwu8I84Bi-Vfw9oSh94rOoM58b524j8pS-UmXp9P2vXoqnIcT-Hpjd5d7Ny8EqAFncwniKEymTh4HFuzREsqKOra4T3tp14lc9LJP9LGaiFTwu4mvfZV7SWCa7Es3lLQcUDn7KCLF-kinm-s96g2ab-QpAFBJ4OdfNMds5yjNXiUXJencaYRxE43gW_86IKaKhlWMd8Dxli9HqdAwzL_CZO4ldt-m8BwfS8ZsgpSbY1Tni9U0s2QgFri2UvarbLcgSNxuFmYQPqsbn0rZOeNHil8-kc2Bygs8-XRrVYY_seDFfaN-FVTwmQ-Sqo_vBVPYFOU0HijhvHgT3wiYQlBejex3zSDRPiN3GSpvGUM4YEcMBZmJYeNetJQYV_CFdwuhypTYQDoF03j-XGZKEcCiQel1xlLPRzqoZCNfjlMfevIbsute06aFuzLJgqX39bquYeB4aLZvdX5cmCazP15drJuF3U9Vn8EWXYIL4-GD5NMwkb70_Lqr0GL-JWdLZ6iuHeUjjsG2T1OjG_fZrKrMdTNSyzdeCt31Ru95a4eAyIxiBO3H4K46t64gHzzmZLSgi7Ob8LZfzHBpUw0yAt6bVdyWd4Z5f5Ptl1HTTXTBqODW4QWT2bemn2nR6kRsWbvDf7_EKq8jvSUxKU1L50o9A7n8qiDHZl0LlaL4GL0W0ARJp202VaJDamp999-JsDPPnShmlTcKfldqImeRNjSJfBZHVtH1Mk_eg1KwmGqePqszW02PEQfeZlG9-GD9zXdvGt1VgQhzxq1CSK0C8q0JQ8lVFAq2vAKCPjuOClM8pZBxgMG_KJEH4QSKa6SkV80z2f9_SejPxjd3eIaexnauJaMTsoQOelfM5DT9wBOCfeS2jUK4mMPP6nS2IVd9b8lsuNkOLewPzeon_6dkCSjE7wlKdS5RavoD0DCiUaS1h1CKuCeH_-uNBkYQj0VyIn1n9pDXUIO80hQlPrJ-PaFCQz4r4PUWK2X5eSYzUkok5GrBDAK4jhuoR91BN9KE8FIV7THvy9ps5imUgAKR5Www_wbrk8pjglqLUwG3VNoROVqRZV-IlAzOcNld1aUkRqWxvtSL8O6YR2KMK5vE6Zo75pyxE3rPEtj4DrMevLlMGsN1eNX4ZMf40Swhf4hQNc9_8qVTM_lf3b_hBZ7JQI__R4dWZDsPcaQvh-lBykCYNu1ATHSYrIj-StJa3iXSGgriLACIGixbPGrGwE7OS0mlLpNsIxAN42Xfn-YTh7y6dvAirlaol_m4efDQHqpDoLstFwqlNdRrPmv7nE1HP_CgZCcXID_F-2qaPcIJNAykWrIR7fbYYLe85lAfmy8SBOnbxbQK9g6bQpHIj1zqb4dJXiQQ4nDlwQMFDTRQkfRIE6ubfS__H9CbyZtToGkCdYll-6Xa7Wa6ig2HDPSwONRYFCBr4gxGFzposxp1JuhGc-ortYXykVkVlq_MJ7jdqJmv3lXCJLRjLIuTICZ1DTaWbjDUoU5c9Z2QhiYkYci_f_XEkY0orAOx28FoJYS3yshPnZOx4DN_Ee-RjElC8HPjf8VZNxUryiE8DW9b38aV47eeSY2jkBKsDPB9ENjE6t6UR4RjNfIjoySxZAWioEdoDTFTwFFzeo5FV2lK2xOQ3bB0uSsqu7O_jnVNoxrwIQO3B7tKVZ64DiKtJaEqUf5VjneveH6RV0puTCgsMvv8sz9ZW6igEunF6-l2K_5zO_T5xrIiMNcEPbAAi61AIMl3VFb_JBcQeSdCtp8LEPlER6GwALYPsCojs9-AqNfAVdFVSAxM8_PL9mx-g0hST6lHC4eAKiFuchslCnAFNCuoNHAgTL6Ga6YPMyukyx0H6KIX9Yr-OASDH7633xyBqN03EGObzvMvMsUomqSTZgBO-yaaREzew-BriTaQ0Fv6DEH68v8C_UfMlYzsU3295Ff7EKEApPNmeXb4o6HlPWOI0vCVraieDTYbuE0D__ZrT6pmyCgpfR6-jzfl9JWskoBjYIPHhevv1DYVreYXTyF76Qf0H9AXyjyjQjVKwIz4jKDrnVB1bZzXa_ePBCNel9cZAaOLSa2ago8jtKqPo2gES5aj8avDknIZOivw_2w94H8POTveTcz-KaS4O0AgNLaJYzYrnUCAC5rPMjFl7TgQDKIrT5FsHpmN_5KDVUmTrVlMKc6b078ALnuo-WC5lWccbWva-xhegSQEaWxSCe7hWvqyklgwIZYJFlc2oI0qS1bH3CtSqAKmzoN6ZhH34patR3tweOiGz5cKJxp5tS1Hy3oyLBsIwlPGh8cAfnFCOszynLi2BzGBaGQLBl76nt5W70UtmW3KOTtcQLItueiqFqsunECyt3nuBR4zHqUGOAQ_C7dEwbAB9YlefNwWcShYoW7mR42OMeM3UPFWjxf8yNd5YrD7xp0Ke2Ime5QU6vIhWQ9KgtQByzsk_mvg8ueMHOLZlkdEGD1i-Y0-m7rc4q4zYeNwjNk9ZxWPLI9I58PDwGYLAtxTNBsnnbdz5m5es\\\",\\\"id\\\":\\\"rs_af630fb07c838bed937afe44f27d296283c7e0a8225c804338\\\",\\\"summary\\\":[{\\\"text\\\":\\\"**Reviewing multiplication approach**\\\\n\\\\nI need to calculate 17 times 23, which equals 391. The user suggests I explain the reasoning. I can break it down: first, 23 times 17 can also be seen as 23 times (20 minus 3), giving 460 minus 69, which equals 391. Alternatively, I can think of it as 17 times 20 plus 17 times 3, or 340 plus 51, which also results in 391. I\'ll present this clearly in my response.\\\",\\\"type\\\":\\\"summary_text\\\"}],\\\"type\\\":\\\"reasoning\\\"}]\"", "response [\"391.\\n\\nThink it through:\\n- 17 × 23 = 17 × (20 + 3) = 17×20 + 17×3 = 340 + 51 = 391\\n- or 23 × (17) = 23 × (10 + 7) = 230 + 161 = 391\\n\\nSo, 17 × 23 = 391.\"] metadata: {\"cacheWriteTokenCount\":0,\"finishReason\":\"stop\",\"model\":\"gpt-5-nano-2025-08-07\",\"requestID\":\"req_1\",\"responseID\":\"resp_7a90aec18ffbe3cfe9235fbf72359ce57f052b047abd003de2\",\"serviceTier\":\"default\"}"]
            """#
        }
    }

    @Test func `real tool calls run, and the answer to their outputs reads as OpenAI sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .tools)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-5-nano",
              "input": [
                {
                  "role": "user",
                  "content": "Use the tool to look up an egg and rice, both at once, then give both results."
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
              "reasoning": {
                "effort": "minimal"
              },
              "max_output_tokens": 800,
              "parallel_tool_calls": true
            }

            request 2
            {
              "model": "gpt-5-nano",
              "input": [
                {
                  "role": "user",
                  "content": "Use the tool to look up an egg and rice, both at once, then give both results."
                },
                {
                  "content": [],
                  "encrypted_content": "gAAAAABq7kmZ8ZcsE41KXD8w_vZC4Yx0cSJICl8NaBKDTHv84CAImJrAcj3A5icSXFwtnWa7hD7x1K8eYJyRZUZhLOqFtHGxg1DAeCo0z1uZK_ycGhMj8e8oXG1D-UKk-nmlpVNN6YfZc33GzU8PQ4fqU5h_iL7v0-i9JPJNSB24ZZw6HCjfkJvkzF133yIjr7uU9lnCzvaMvvotvfPahwNuFjvc3sIut-ckDSoK3SZshMRK-lSjv2cEADfars3ZGiP4qjjlSTfYLOSWcAnxZxwAzzp7WKzUpPMfmHR538qu_C2wXYrhxWBK4gmhG5WRmFqFFD1TlzJojH2Y5L8Wlma6mKrKBe8bENeEo6JyWOlC-0i9GfJGN0KjvP0W91mMGa7DOgmvsU6qdZFSy7RFnweDsEM1Zrm9vkP0yuPpnjZO0pOwPV-oJOOQWoiCloBWsVQwzdVN2zANtu-8WsQIcbdISAkfylDXYXtvh1xQ0DppAhZpno8RWWDeF3gw9cA1mHN9gkWbBwUNmon6RDkC06U9KsDwSK4rI5uQOObJOgesaC57OmyxJTzTRF2VNMGrdZHNqfkNLBNbOumY3GPXWwlQXmLP93JwP9ggO6wUdnpAxA8Fp_eM6qlyP5D3iCRXSX_fcAsrQg9hPl0UflsYjwQMCNoWkLcIK4j6gB65Gr4i8_Y2_b1dkcjAUhIMGfKIaP7KDaUscgXAfAcpXdL8Rlqx2om-jy3lZfaSjQdEO2ZWhsJw2Lv6szjdaOuC7fklKeUOg8K3p2BhR4EiD-sA15bETaUaFuXij9wNKRD_U_ZS0jcowlYJTlaJi30n-E2PizCTPiAZH_dbDEm19NQVkKwqqswQqczmo4dmy7_7C_rEh6Zg9GfPCOqnIEkpA_NPCPzRAvSovd87N-eC-_0yk4FT2c9HYB9NMDHeENQmb-ZhRRf_bkmD_akvSPPIZskpYgwum-DDcS5tKGb9jANRbKP8d56Er4CMSUApVQh_viXvWKgvK_Bze6-ceVZ_thDJIX2m-bTl1NJb7ivnPIJR8ANuzzvyw9s61TKWvsgofjja92P5EsQjxwiUst6GxdlTKRfaqQdhaT4tFSq4SzSzVdehL_0a4LTzxNyQGDGc7g_nVy5DU7LoeblSLh5t3mQ-HhdmoqP8rlzeBRFI0JEyNwsUh0I2P27bp0SlF6G1a_joWBYMP6k_Uj6zq9UVKMQOFGfMhlIpyli4mSSUUYRPNQs8CRottSlFiw5kKA1kcWlvpqJcuskyYyqB251l_8nGRtVTXIsqvSTUJQf2-4TPtY8VNulrTiQ6s_UncGgndih4V5TMvkBLC7AHd2nf4zOSs7yb3HlCyuseIxaW2Vh_4nw7KwDdhRfS5vahzGAyV4pIxtSKS8vxd20BV3OqSBC59MNY8ZC5lIRd8jTOEVecwOr6tKLsLfUEPlkrN7x_HRQEhSTLK1Pr7mSqda348R_LAJcqsXstqWDDjSfMjyQKWikLJsARK7aWBAVZyrG9CBJJaMCQ-xZ8dgsJAsH2debq6XXU2FcPuR0NGQxWClTI-hFvyn_nT9OoUkh3WSqS3vhpwuoy0gcgb_MtT_x6uWzT45PlGni712__smpQ33gMkkFpqqFv2jndHiHS_K0sxDb6qcY1yIBBuMFXAZRFDtaUfJ74Pp2dfLbefbLZg666AjwpUWdVL6jH14AKbMtHlYJ1p0xw5tHFwKdri1SM3Ng8t2jYqE8wOIaBYfAMJL-Epw-nVWYtAO0afv2aRcS5Ur7B4R2WNPsgIqTUsr6FkGkx3dnxy17EHcCGBBowf9-m-s0kNw1GkMf-fFRMECPQRkOp9bzmGeZcvPY=",
                  "id": "rs_c955672ba9b7e4e89a77bb46074646e9ad9e72b34eedd0a9bf",
                  "summary": [],
                  "type": "reasoning"
                },
                {
                  "type": "function_call",
                  "call_id": "call_qvEeFlsExQUF9sP6RSkVyPjj",
                  "name": "lookUpFood",
                  "arguments": "{\"food\":\"egg\"}"
                },
                {
                  "type": "function_call",
                  "call_id": "call_SMWH33wAL1wKdeujwcqj5kQE",
                  "name": "lookUpFood",
                  "arguments": "{\"food\":\"rice\"}"
                },
                {
                  "type": "function_call_output",
                  "call_id": "call_qvEeFlsExQUF9sP6RSkVyPjj",
                  "output": "egg: 100 kcal"
                },
                {
                  "type": "function_call_output",
                  "call_id": "call_SMWH33wAL1wKdeujwcqj5kQE",
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
              "reasoning": {
                "effort": "minimal"
              },
              "max_output_tokens": 800,
              "parallel_tool_calls": true
            }

            transcript
            instructions [] tools: ["lookUpFood"]
            prompt ["Use the tool to look up an egg and rice, both at once, then give both results."] metadata: {}
            reasoning [] metadata: {"model":"gpt-5-nano-2025-08-07","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq7kmZ8ZcsE41KXD8w_vZC4Yx0cSJICl8NaBKDTHv84CAImJrAcj3A5icSXFwtnWa7hD7x1K8eYJyRZUZhLOqFtHGxg1DAeCo0z1uZK_ycGhMj8e8oXG1D-UKk-nmlpVNN6YfZc33GzU8PQ4fqU5h_iL7v0-i9JPJNSB24ZZw6HCjfkJvkzF133yIjr7uU9lnCzvaMvvotvfPahwNuFjvc3sIut-ckDSoK3SZshMRK-lSjv2cEADfars3ZGiP4qjjlSTfYLOSWcAnxZxwAzzp7WKzUpPMfmHR538qu_C2wXYrhxWBK4gmhG5WRmFqFFD1TlzJojH2Y5L8Wlma6mKrKBe8bENeEo6JyWOlC-0i9GfJGN0KjvP0W91mMGa7DOgmvsU6qdZFSy7RFnweDsEM1Zrm9vkP0yuPpnjZO0pOwPV-oJOOQWoiCloBWsVQwzdVN2zANtu-8WsQIcbdISAkfylDXYXtvh1xQ0DppAhZpno8RWWDeF3gw9cA1mHN9gkWbBwUNmon6RDkC06U9KsDwSK4rI5uQOObJOgesaC57OmyxJTzTRF2VNMGrdZHNqfkNLBNbOumY3GPXWwlQXmLP93JwP9ggO6wUdnpAxA8Fp_eM6qlyP5D3iCRXSX_fcAsrQg9hPl0UflsYjwQMCNoWkLcIK4j6gB65Gr4i8_Y2_b1dkcjAUhIMGfKIaP7KDaUscgXAfAcpXdL8Rlqx2om-jy3lZfaSjQdEO2ZWhsJw2Lv6szjdaOuC7fklKeUOg8K3p2BhR4EiD-sA15bETaUaFuXij9wNKRD_U_ZS0jcowlYJTlaJi30n-E2PizCTPiAZH_dbDEm19NQVkKwqqswQqczmo4dmy7_7C_rEh6Zg9GfPCOqnIEkpA_NPCPzRAvSovd87N-eC-_0yk4FT2c9HYB9NMDHeENQmb-ZhRRf_bkmD_akvSPPIZskpYgwum-DDcS5tKGb9jANRbKP8d56Er4CMSUApVQh_viXvWKgvK_Bze6-ceVZ_thDJIX2m-bTl1NJb7ivnPIJR8ANuzzvyw9s61TKWvsgofjja92P5EsQjxwiUst6GxdlTKRfaqQdhaT4tFSq4SzSzVdehL_0a4LTzxNyQGDGc7g_nVy5DU7LoeblSLh5t3mQ-HhdmoqP8rlzeBRFI0JEyNwsUh0I2P27bp0SlF6G1a_joWBYMP6k_Uj6zq9UVKMQOFGfMhlIpyli4mSSUUYRPNQs8CRottSlFiw5kKA1kcWlvpqJcuskyYyqB251l_8nGRtVTXIsqvSTUJQf2-4TPtY8VNulrTiQ6s_UncGgndih4V5TMvkBLC7AHd2nf4zOSs7yb3HlCyuseIxaW2Vh_4nw7KwDdhRfS5vahzGAyV4pIxtSKS8vxd20BV3OqSBC59MNY8ZC5lIRd8jTOEVecwOr6tKLsLfUEPlkrN7x_HRQEhSTLK1Pr7mSqda348R_LAJcqsXstqWDDjSfMjyQKWikLJsARK7aWBAVZyrG9CBJJaMCQ-xZ8dgsJAsH2debq6XXU2FcPuR0NGQxWClTI-hFvyn_nT9OoUkh3WSqS3vhpwuoy0gcgb_MtT_x6uWzT45PlGni712__smpQ33gMkkFpqqFv2jndHiHS_K0sxDb6qcY1yIBBuMFXAZRFDtaUfJ74Pp2dfLbefbLZg666AjwpUWdVL6jH14AKbMtHlYJ1p0xw5tHFwKdri1SM3Ng8t2jYqE8wOIaBYfAMJL-Epw-nVWYtAO0afv2aRcS5Ur7B4R2WNPsgIqTUsr6FkGkx3dnxy17EHcCGBBowf9-m-s0kNw1GkMf-fFRMECPQRkOp9bzmGeZcvPY=\",\"id\":\"rs_c955672ba9b7e4e89a77bb46074646e9ad9e72b34eedd0a9bf\",\"summary\":[],\"type\":\"reasoning\"}]"
            toolCalls ["call_qvEeFlsExQUF9sP6RSkVyPjj lookUpFood {\"food\":\"egg\"} metadata: {\"cacheWriteTokenCount\":0,\"finishReason\":\"tool_calls\",\"model\":\"gpt-5-nano-2025-08-07\",\"requestID\":\"req_1\",\"responseID\":\"resp_eef168ee174906a270b14c6cf7d778e0867bae5e7d6962b1b2\",\"serviceTier\":\"default\"}", "call_SMWH33wAL1wKdeujwcqj5kQE lookUpFood {\"food\":\"rice\"} metadata: {}"]
            toolOutput call_qvEeFlsExQUF9sP6RSkVyPjj lookUpFood ["egg: 100 kcal"]
            toolOutput call_SMWH33wAL1wKdeujwcqj5kQE lookUpFood ["rice: 100 kcal"]
            reasoning [] metadata: {"model":"gpt-5-nano-2025-08-07","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq7kmao-cFHt52yaWIVAAErjl41OKYb71ra4LR3eInh32NS6FjDfbqVfvJL439j-8y4cD17h9Ovapn081yQpQsxYllaBfC0ZsvlXZfdIntssvqon6ipvrmmQNTjAcp4FPb-Z-6GkQJ650nLScL1BH2kKQeObmCbkGtOimmF3zRlYdtldDlpHnRt28C0ehfKH--cumJM-iuLO4zLA36zDGqGa5GqFfuSQH0GhJOs9DJcpmQgTmRlscfYqjmGSDahai5QgaHplNZeydRT_jHvlD_i6Mj-xyZg1T_4fXNEh_0pVVkj-M1sTe1WqgTMUDmaUCZLFZdUCqIvryaRYrOiGCGHBWJac4-957L5rdZvazeyNtvwrufTk4qT8UWyx_kcv6LBKlpitZA7EvYDXe7ZaYHhEDgxtXYsQE6hOPCO3eu4hAwq_BZCb-SkRj3_-oRk3ZDIZ8rN3RHLM6QtsYj5IQd4N5z9iOJpr7giU6b9qmL0R8WRO6s8v2rvJoD3CPD5S3WpsyPSmzbYWWRA7YHQaqO290I-PJXkiBr6EneyH3lcBIRhUPctD5T7O8z0cLzZ3UxRhneNIQ-RuBC_BkEBIljBdt9D9wVwdCIcHogt1kEAzkh4_qEaOrLW62KrZX6H2PjlTGcd2X87VUGNH0DFZnni3CUFyoQ_eRDRZr3WOKQmzVL917TYc7XWdw8l2jiV-xpJ4zKGOoqO1tFdmF9HccNqd69x1m51pyD_4drduAKCM5b5tmEjs4_zzM7DyJdkyxrPzO6b_kSr35DpN7Utntq9_xJ_-otlYu1Q7rZ1aL_gavWewOVkjcA-EnUTzESDx4a3yuDT0geRHncjUpkPFQR5_tN3Zvh0j9o-CTKmHa1ALNhN0LJ8cANb_eJEJg4iU-5wQxQMe1w_1BXS-XxyroeKaaNvlGbBT75uImf3E0AJZqh_AboZMloFfmDV8PyC9OT_GdNni_PcicxsJPrQSt5f_ndFiaNStkJvr9hRVpAwxnHUFA89wGuWtaZ7slC27SC4ORl0ljH81WD2gG1eo2BoL040AU6fgtJKFz_O4bYV4Ytr1FsrO5YYDF_tLfr1k9I9sNQ0V_NtnZB6Y6G9x-kJhB15TjRcSNU_KQIXlU0SCvWpuBRzPPQl4FLVvss1H-J6VElUB6yUOwEbwj9lE5Xrewab2aCQl6sj1xN55v1l6oZnri-5R0R8bhczWrWqe1S0AUMFlWagxjJj-7nqwSJ07Czf4wXLGmUwGoDyhKfM5EvhUNDC8TNCREodHasJXnp3G4T5X3GDqvmRclhSWhmoCRsnfCbM-SscTiN2wCRnlF0K6pYSIFRKMz3FOuvRqp3tEAYk3_IcwFVxoJD6NxinBcV3vQrL0_81BiS5qhQdLnYsXwaM1qOq-3mfutwHRn4Hyi0unOuHaIBhqZx-XfZEIu-LnJrjbWRCX734Njb_rdFbeZPJhXemJ6qn4XLD-Ui7dOMviiCt7z26Fue2YOK2b1llBNVr1hZ0YV_Jbm6N43R9xm3FkeJzbH-mKioFzqv1hYoeGzMecDTe3aNCrJDr7DkjI9131UlRjfFkd20f2GT-Q2MBPGHh-aog42iEauPThRtme7kqj4UYKXP0BAe_gebNDjAy-n01w47wQvxjzuQzNURyn7YUhQTWq7BqZriNdN4P0KbTOZeeh2MN1-itRWOvo_2ZoAA65QBJn2QO3Ov6bSNf1r7WDVNkVYz51vZUsL6QnREkTwLq96CUZceOPhLHCX46i5Je0VVj2OHT2BRWFbqXWgBYOFzuMAuMgUWu58waQ4UMHdG0N1oVT1TIwROrtF4mR7P486lp7C1MWVghTM=\",\"id\":\"rs_a398b237f6df6d5dd28191dfe4779b8a55437a5e768e879809\",\"summary\":[],\"type\":\"reasoning\"}]"
            response ["Here are the results:\n\n- Egg: 100 kcal\n- Rice: 100 kcal\n\nIf you’d like, I can look up more details (per-serving size, calories for cooked vs. raw, etc.)."] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-5-nano-2025-08-07","requestID":"req_1","responseID":"resp_33556ad7b4c93c74edaa61f8f6d2f1c22bd0d0a6d9c6557c3d","serviceTier":"default"}

            usage
            input 147 cached 0, output 62 reasoning 0, metadata: {"cacheWriteTokenCount":0}
            """#
        }
    }

    @Test func `a real guided answer reads as OpenAI sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .guided)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-5-nano",
              "input": [
                {
                  "role": "user",
                  "content": [
                    {
                      "type": "input_text",
                      "text": "Name a food."
                    },
                    {
                      "type": "input_text",
                      "text": "Respond with JSON that matches this JSON Schema:\n{\"additionalProperties\":false,\"properties\":{\"food\":{\"type\":\"string\"}},\"required\":[\"food\"],\"title\":\"Arguments\",\"type\":\"object\"}"
                    }
                  ]
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "text": {
                "format": {
                  "type": "json_schema",
                  "name": "Arguments",
                  "schema": {
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
                  "strict": true
                }
              },
              "reasoning": {
                "effort": "minimal"
              },
              "max_output_tokens": 300
            }

            transcript
            prompt ["Name a food."] metadata: {}
            reasoning [] metadata: {"model":"gpt-5-nano-2025-08-07","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq7kmcOy4uKWscy2lWQVQRkSSeyigBf8c5M4Q6oAla1ju_-FwHk-b81377R76stIZaS4cep4hoLDP3Xp8mLnsWJC-qnJktocg1BRNL4fChAhUw46pM7hrvHmxOlc1ZDdYKBzDYdRp-1iQSgB-0SKNVGovbyJ6gwVkYLMvVGqg5JQwbsHVUKbGZaVDLdarLcM_sb436lPdQLMYMZ8AGdZaucafM0O-uroNBCgjqmdwL1ckeP38GjF52_s33tbUubzwkKxG5BUvkL0yqHgOYsgmTXqLzOwEmwm_56kfz9qsH5cxOjjIDn7HA6OzZlowPLSZBKwfEGwCgcPUXeTU-UhBfYYMMuQeBYRTgYNOynrFZTJNRztF0664Zrp8XDxeMzpJU_R14uhmR3-DsKjejOJSpGWgrJYb-B26keIpVf_HwyUvOn_to-9hzxW6XjHEIiFKCcefkNbzuRjwKXMfiL3-HVQ4u_lChFffYDzpdLhFH44HSTHu_FiRxb8H3nv8kE-7LXdlZ_Zs__8kPvzgE2sfxO9KF3Nqr-HOlbiw0Ws0RKDQ5cf3Ibv5q8cLA49B1cYluJ-AhMTXzVUHHE3aeTrowekW9ufaNw7AWg0_Hjg7y86OVhb6FWNctNsRWBBfoQ-kunZDrTP3sfrUKlNz2zvF4ZOHM-KYbf3BkBDnXI-h_hZFgrbokrR8v5Vn9Lk7d2X8Bzgwfqvq5pzG7U-Ce8Z4ZYVoJVFQRSHT88xPvNOEuC0Ykn3rBPtZoMkiHeU8DBHTyHd7yS9SCKRqz80Hu9EsUiHEaWpa2NAve3alxPiK_l5s09NCC_Q7wvbDfhIZc44et57JJZwoYKJq-qZ_aJGqVoMdLjpfLISG5HSe5L8OCtmGcTZgxAK1uzexkiBa2bK_ratMX3j6Zb2ns2AmYxK8096657s0X5HPNfUuwu_KmvBmAjnkPdW1XUJOLh72cCJZHQdmyDntafKT0oyiHcELnGjo3LK69F1y2owYU8BkV_TdB-ecjPejDEBT5KLEBnKPosxAJabjncOtidR9wFLR9g9qFzVbP8lWixA2N4zIHHgOvdSEXOVv5rzjii9dvt9XqsElNAYVjL3vsHyPdxAWiHSxHy-pqvRwtMVroT9JIClt560xSP7XsIZYgyd3OFUwjZQ_HCx-vk5XCQ_ZaUOooqhVvqfvTLHZ-ff1v_oJwegfgPEBc_x05tWir3osgTu_il9-3EIwrr92YtupkVUsY-MkXNc7kYtno-_e8b_KgswMaB66-UcgTGEGONb-MXck_kln6fVbLq9mo4TXv9aXqhXWxR3BtPvWK-75ISLN0aqJ7avCj2VwAK_xBGlXGZevo0eJnptr-Fp-yh_ArcRnFJXXwQ4uxgvVLK94t--OC-YjaDVqz7A-HWzw9WkldK7TL8helBYouAmVbZznsMeDpQOq3Zu-NqyAX_AdLLxbeGQ4L-2xcauNsp_cQZrZDivPuqIsuPkS8--Jdp43uos__V2zCwf0_rHrk8fBssFqOX7eKYfGyF36H_BVRbQs-G-zB6q55dNxSuoYMANCYrWQhuS_xcIGzkdZjv5LnjXOmbdJnVxhj0xiTgcNOwD2TQq9JgD_aNPYiXlrGMbebuIg9vZIJni9lOnNlRp-wh9u2l8sd6cPG4ohvmcslWb-WQ1AZbT1OFUoTjEUXVxjGVfsHlpgvmowGs3iLYUDWNh34qNzLn3tKGXjer_aCPSul7qaOEeABfJhc1BgvRGqJ-2DOpP-W5WYRnWibP9qdD4F5p-TaLeLemPTEsJNNFi6I8IYDgdC8onOCpN7nVYf9yYdORigg1Q==\",\"id\":\"rs_ecd476dad5a4b28770a53102bbe994beff81df4f8dae65de59\",\"summary\":[],\"type\":\"reasoning\"}]"
            response [{"food":"Pizza"}] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-5-nano-2025-08-07","requestID":"req_1","responseID":"resp_3f970c12be062f690f8bbb90ce6389fbfb0ecb3b7b21b9ecef","serviceTier":"default"}

            usage
            input 72 cached 0, output 26 reasoning 0, metadata: {"cacheWriteTokenCount":0}
            """#
        }
    }

    @Test func `a real answer from a model that doesn't reason reads as OpenAI sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .plain)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-4o-mini",
              "input": [
                {
                  "role": "user",
                  "content": "Name one color of the sea."
                }
              ],
              "stream": true,
              "max_output_tokens": 30
            }

            transcript
            prompt ["Name one color of the sea."] metadata: {}
            response ["One color of the sea is turquoise."] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-4o-mini-2024-07-18","requestID":"req_1","responseID":"resp_bed7e9c7c4ccb46d8bc8fe3ab44e0c906dc39821b53ba4e5ba","serviceTier":"default"}

            usage
            input 14 cached 0, output 9 reasoning 0, metadata: {"cacheWriteTokenCount":0}

            last snapshot
            "One color of the sea is turquoise." ["response [\"One color of the sea is turquoise.\"] metadata: {\"cacheWriteTokenCount\":0,\"finishReason\":\"stop\",\"model\":\"gpt-4o-mini-2024-07-18\",\"requestID\":\"req_1\",\"responseID\":\"resp_bed7e9c7c4ccb46d8bc8fe3ab44e0c906dc39821b53ba4e5ba\",\"serviceTier\":\"default\"}"]
            """#
        }
    }

    @Test func `a real answer with instructions, metadata and OpenAI's options reads as OpenAI sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .options)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-5-nano",
              "input": [
                {
                  "role": "developer",
                  "content": "Be brief."
                },
                {
                  "role": "user",
                  "content": "Plan the week in one line."
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
              "max_output_tokens": 600,
              "metadata": {
                "team": "coach"
              },
              "service_tier": "flex",
              "prompt_cache_key": "<generated id>",
              "safety_identifier": "user-1"
            }

            transcript
            instructions ["Be brief."] tools: []
            prompt ["Plan the week in one line."] metadata: {"team":"coach"}
            reasoning ["**Crafting a weekly plan**\n\nI need to plan the week in a concise way. I could start with something generic like \"Mon–Fri: 9–11 deep work on Priority A and 11–12 for meetings.\" I'm considering stating that \"Tue/Thu are for admin and emails, while Wednesday is for review and planning.\" But wait, I need to make sure it really is one line! I’ll finalize it as: \"Mon–Fri: 9–11 deep work on Priority A, 11–12 meetings; 1–4 admin; Wed: review; Fri: wrap-up; Sat/Sun: rest.\""] metadata: {"model":"gpt-5-nano-2025-08-07","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq7k6WjVYlJsiIx4-LzQP273cEW3kPo3pG2ZBdoRDB89QiOrEXQra7kD2lMqS5gKL5G_fP9YxY1zZdut9B5xhBlnnujsoUpPR_Zov5VxQYRVZ4h7jNasATfOqrevuPgMrWlH2BcZ_rtVvJZBMHqMMjta4VYow9odmvrMyNHnWMZHX8BEQJJZ2JGRMRVjWZNBH6YKeLqyqWlgVzNwhLYZ3J2Mxtnq8uMNKSoRl23KuNyPbNWidAOiZhPgwByhaJnL9Hz-81IBT4mnmgR6hxt3T8ZUD5QvqWFcakfKryvHx6CDqQNXNQmuelRtdUWw5FTWGyS9iZAwZzLLyaiHQxgMdBcbf7RqWaa1PGZxoxOqdN4aaFfBWZ1BXyR429-YtYK6UaEELfZ6mNGWkO4zCF4t4uwOwfRies45gM9zmyo3OZOGlYqOWxbUE8WkOec-rRvy8vG_MVjn62tgfAVHc7zlUpAhpkWgK11aI2Zk5j7QI3hou-P_a9nUN3PoDFs-_SJumODqxDzocpxyzIQTIOli4Km1RIAF0UmQoM9fELU_1hbUBQzVxjGtdRV901J3i0K9YA-RqzZifJwVC9UB1CZSKL0-j0WkKbFs8fZzCxurFdJ28FbVemP_ELUDwDhe-F75WOHSQgvL4uZBTHq3hP6VxkJTUoar1V9X5LV7SK7KE1n3lfUTGkiyp2PsfFwEj2uBKCm_tHNfwurcR6r6Vo_viIZbQv94aOvZZaN9b-pz6Gm8eiU_8gjIyUJ4MQvHFY9bNMT4p7_-h7BIMKAIaH0PQTdDVj6Wtmar6kc89fLSsIEXWeeheeo0L_6HLEWgym9axcQNEd1-ZvGYkinedMQApdloFEAFCQ79G-2AphmE7_cRHRI87pgIachbeQpWKhfBllWCRU1eCatrAjY1hllEdhOnBxEPD3L1kKSX7YWegxu9ZXruw7kcy3Ad0iyd0-2qcumiF6NHqTx164BQ3go11iXCglws9N0aL5iaXtt_ODAxGtg2qJGhoFxSOZw2EPgzlgQhlR8ohKbUxCqvgNoBZQwi1gpkD8hQ7Z3U4VUyWe50cZ8Qk1h0cT-04C96t2hane3ajTEu0fXiBYiZUAI_qCoYPE88iDPNe6aVVccCQwU0xy6bb3WM7DJgUcX1i_ovD-u8VF4BF15lVAohACfpb4IVBDUTtkKYwdApFsEX0dExW7Bg4qTWqsnQS9wtYSBunwMZWyV1PJOsKOpiwov7mkepzUxReX6OYOjETpoqfbp1t_s0vlfa1fY0715kpMPkh9Whf9Zbq-WKnqGurh530zC3U1aEpWrF_9JIe5UNEcFcZVf4Ep8RMxEi4NwzlwGC9iGuZieCJo0KJTHubWlkL_WHO6mIFuRTvyP62l8rsVshl3v6SQOBlxMPn60h1cTHfPGKnEsnlWS8DMCXmZTfpimOXGNdV5ufdP-_0JVaiLcbx9zi24uPPUYiPGpsdrFhksJVGufFsWMLOVr5rLkD6FMwlAfnJoXtZsXTXTdx15LGRPEyy0rAHmJ6DMpKPCwri1OlhweblnZEWz0WepBmNPClhqCTfqSOs2N2yyJCB-FF9hCopQhe2Q0b5wLFOsucqVJhRoPAzuGYSMF7y7sjtNq1e-9ZNjRCcCV5JC1IVy8QnlVk_6TedhFs9xQFUjozeUsnI2mcbAaywWW3E195XwjfWPca3M2yFyWgVjliDlD5v3Kgg5ZYpkAM2laMxAIizYJqNuWNkAC57exW6PEizT9hRhtyIZcLTwKhmb3pQhdLcI3SQ6L_L1YiBmf9Gmjf5dlMNrCwsnvrB245ToS3qvZO3tUvxO3gcjG78BvS79iu4fiQVnYll_d8LEPV0invi1lH9sCy2LN7RmHv735yZQ9XRWO-WtXxyFBsjCBaFYILf7OhjFqAuHVi9gTHFVDAd_r877i9-YG10jyV4jeZkz8vhMRaQPqT-8mk7mHQ-W-qyA8yIQ3MuEQpcXXiCR3TwJIOXqYD4M3RjVh7oXHIPn4oI9bxechH6uuG3GpH3rmYrF8ARTTJ-o8sJTLzMTQTraTArKtkjXKjN4wqDRoE4GqtdVF3pD9C73AH-W8aK4jR-NvdtsRRJNL_Qj7Vq93NeN_5tKcMgKk0HDkvbuEVaskk3_nkBjsG2H6UTiBiKIUcYh_MGABOz4ibec6fFw0JMrehl6NdobqJI1q7X_a-_09e6QbaOv3r6I_sAkp9dIUM_3CUAUwNQ76WNL5VbJY6Fm8gq0Fk_Y0OUPfYKXqzP99IRTPEO1uC94N5e_WQq35CXIhfXPcZ8CkxVLXbC-xG64DMvpSvsWCwRnEaQvJi7p3ROEj3GlWD4h_fB2H8lDPS7R0DXspqh9xj9MduqFJshRdNBThJrMHDxlxrZ8YsERDNdIRjzXbv3dJY9tepKTNO59-SPpgDITQ1nzugMorgYCz0mHjPrDX7k21p_mAZcS_AFHDzgIOWKs-rVd9g06PYtMMKEaE3F7g2_leOxMekQn9mUz0GnuuOgu0sSIb-984186HwxclGyDR_McW997oGquUAnkbQUVcVomGO-4HfsINnU6_34wgbcQkdZU4LlXTtenOq8aL4rPEWeryTEYoAG4X1c9lAi4zjEYp550Ez2M-8npUDjAZ3IeC-R_H5DltHlz-lSGcNlmagX1g8CUEFb7UrXZ-Z9bn1Zn3Bp6M_5VrFIcPyBG375o8WpPkWW55buB7CdK2K7jgF_Xuecd4rN3GyK9nj81x0BIs0jPmq2KIOGTsiaTs5rJvjToNBMcosjaSEst61TABIoFuvy9grYszNWarnEfKHdf5gvtZYMwi0wdAE3ahpMG92-K12O8RmAYqi0ceCJOh8OIk28NGYDES8fDh13H4De7oIq7_e23JKHm67Zd5hOl8-tuPwHP4RSTOSCjlzyR0lIU-ZKeOAmq_nO6AEMw9APibzu6BLfY-qzFBpYKtbzdqYfdLiQ2GX6zGaXzc-TKJki1JkLLM5C2PdudS1fRfpmQrgLMZkfjRmqhpEvZMR82Gp4cVOqzjdf36kxNiD0Znv5ApUasjk982ZZ09lEu0slz9rkJOW-PKlUrMJFc47STGKAz7mhMyjdqG4B2oGZ6C_C6fYAp__Bdh7FhFmijAZmw7EQZPY98AOse6nYd3jSo7NB74cOk5GXCzm2BrLGOSNqsVGKkcZpinI9kQLZ9-q_jmaGWWBWVqlylBBsS7w4TkafDzw2KEMtnowzHqKNW0Y1KWTUAmt5bssSY1p-JPdeVqIP43S4RoLoauZPBvXvBs2Sm-kpCAjeqCxvW1lTO7R775ixtastwy0kROE2F9y8kWM0Hl7pmjXVsozmTMwtZOQNQ5etxG3SKZRanBILc9377vEYrB2uzRJScdv-v0Xi0neGhXg6lda_2i8kfLkTUFhaMR6qXl5q5Bz704dzOylCy4kOaZpqagywJ9Gic4ftnHx2Pa_AjL20ups6yXMX4NXSDgKmUZk_qV1zr-2SjqdkYGZ4fGo7A335MRdVjsD1If3NIWz0zhcbsoqD9n6v1E6D9GSEyB2HxTWFGBKL_SImoUspQ0rGL2sAhxLh1v9SWbcOxCmSDCs0lt36MpS4gRDhtqf-Gyi-RYgBR5GRWQ8sYb6Up09QA7Oeq-lYf3dYmIWDM0yaRWM1QbvesV7yw7uEdhrgFDvvbU139HTbLlX3X7X3MsQ1Pq93_xoyirziTWHmvJCai5QizcU-yUSWOvP4DjDTV7yX5IuOGDMLsJvjicH8W128Q-6FGYc_knE78B4TdWoO3gUuXN4KOaxPMiJs4PJKO9tZA569-sJEC_NsTpOQAxdQUKiNLA3Iuc91SeWf6mKCpU3JlCCEyLk5Hl0t0e_SSGzI_QC9LfxCoqPV5_Uz71Cgdm7EEnjqyYPOwS9KLeQ8EGm54BS0Ps5S8pZddDif2um9dk16xLxbMyiPlKkCfJpxJoyACYqBrAnBSTlT67E3Ha9Gk_2OV3HV0s5sQnsOZYb3MzQ20mFFvCrzn5WoUByP5nfFNWyx2712fqy2odnjbM70cgCynR0gIFqqs1XZWx-K52d8AoZKdVytdoWGSQfldIRVXvPiOTqRbw2AXy7Si90QuiDC6BboE_LlDleXk8-fbn_EmOuzn3RmDpa7xkXNAhzbWGcn61wuY96_uXTLVCMhBz9wd4HfFP9GuyaChd8rcdrAjzx_Ym-YjrAvQu-H04utn1_vKpqNxYSeFWoarUahGwsvUBsps0Y1ffyRF2BbPSd6S5WsC03yu9IXEBKywYQM_tMYz3nPOEsqlbyt_eg8d\",\"id\":\"rs_d1ed60f47298485d3b4ba768d06166f4132dfd8c441144a790\",\"summary\":[{\"text\":\"**Crafting a weekly plan**\\n\\nI need to plan the week in a concise way. I could start with something generic like \\\"Mon–Fri: 9–11 deep work on Priority A and 11–12 for meetings.\\\" I'm considering stating that \\\"Tue/Thu are for admin and emails, while Wednesday is for review and planning.\\\" But wait, I need to make sure it really is one line! I’ll finalize it as: \\\"Mon–Fri: 9–11 deep work on Priority A, 11–12 meetings; 1–4 admin; Wed: review; Fri: wrap-up; Sat/Sun: rest.\\\"\",\"type\":\"summary_text\"}],\"type\":\"reasoning\"}]"
            response ["Mon–Fri: 9–11 deep work on Priority A, 11–12 meetings, 1–4 admin/communications; Wed: midweek review; Fri: wrap‑up and plan next week; Sat/Sun: rest."] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-5-nano-2025-08-07","requestID":"req_1","responseID":"resp_3cba0b7f18ac52680254e110b223921e34b858ee1d3be7f9bd","serviceTier":"flex"}

            usage
            input 20 cached 0, output 297 reasoning 192, metadata: {"cacheWriteTokenCount":0}

            last snapshot
            "Mon–Fri: 9–11 deep work on Priority A, 11–12 meetings, 1–4 admin/communications; Wed: midweek review; Fri: wrap‑up and plan next week; Sat/Sun: rest." ["reasoning [\"**Crafting a weekly plan**\\n\\nI need to plan the week in a concise way. I could start with something generic like \\\"Mon–Fri: 9–11 deep work on Priority A and 11–12 for meetings.\\\" I\'m considering stating that \\\"Tue/Thu are for admin and emails, while Wednesday is for review and planning.\\\" But wait, I need to make sure it really is one line! I’ll finalize it as: \\\"Mon–Fri: 9–11 deep work on Priority A, 11–12 meetings; 1–4 admin; Wed: review; Fri: wrap-up; Sat/Sun: rest.\\\"\"] metadata: {\"model\":\"gpt-5-nano-2025-08-07\",\"reasoningOrigin\":\"openai-responses\"} signature: \"[{\\\"content\\\":[],\\\"encrypted_content\\\":\\\"gAAAAABq7k6WjVYlJsiIx4-LzQP273cEW3kPo3pG2ZBdoRDB89QiOrEXQra7kD2lMqS5gKL5G_fP9YxY1zZdut9B5xhBlnnujsoUpPR_Zov5VxQYRVZ4h7jNasATfOqrevuPgMrWlH2BcZ_rtVvJZBMHqMMjta4VYow9odmvrMyNHnWMZHX8BEQJJZ2JGRMRVjWZNBH6YKeLqyqWlgVzNwhLYZ3J2Mxtnq8uMNKSoRl23KuNyPbNWidAOiZhPgwByhaJnL9Hz-81IBT4mnmgR6hxt3T8ZUD5QvqWFcakfKryvHx6CDqQNXNQmuelRtdUWw5FTWGyS9iZAwZzLLyaiHQxgMdBcbf7RqWaa1PGZxoxOqdN4aaFfBWZ1BXyR429-YtYK6UaEELfZ6mNGWkO4zCF4t4uwOwfRies45gM9zmyo3OZOGlYqOWxbUE8WkOec-rRvy8vG_MVjn62tgfAVHc7zlUpAhpkWgK11aI2Zk5j7QI3hou-P_a9nUN3PoDFs-_SJumODqxDzocpxyzIQTIOli4Km1RIAF0UmQoM9fELU_1hbUBQzVxjGtdRV901J3i0K9YA-RqzZifJwVC9UB1CZSKL0-j0WkKbFs8fZzCxurFdJ28FbVemP_ELUDwDhe-F75WOHSQgvL4uZBTHq3hP6VxkJTUoar1V9X5LV7SK7KE1n3lfUTGkiyp2PsfFwEj2uBKCm_tHNfwurcR6r6Vo_viIZbQv94aOvZZaN9b-pz6Gm8eiU_8gjIyUJ4MQvHFY9bNMT4p7_-h7BIMKAIaH0PQTdDVj6Wtmar6kc89fLSsIEXWeeheeo0L_6HLEWgym9axcQNEd1-ZvGYkinedMQApdloFEAFCQ79G-2AphmE7_cRHRI87pgIachbeQpWKhfBllWCRU1eCatrAjY1hllEdhOnBxEPD3L1kKSX7YWegxu9ZXruw7kcy3Ad0iyd0-2qcumiF6NHqTx164BQ3go11iXCglws9N0aL5iaXtt_ODAxGtg2qJGhoFxSOZw2EPgzlgQhlR8ohKbUxCqvgNoBZQwi1gpkD8hQ7Z3U4VUyWe50cZ8Qk1h0cT-04C96t2hane3ajTEu0fXiBYiZUAI_qCoYPE88iDPNe6aVVccCQwU0xy6bb3WM7DJgUcX1i_ovD-u8VF4BF15lVAohACfpb4IVBDUTtkKYwdApFsEX0dExW7Bg4qTWqsnQS9wtYSBunwMZWyV1PJOsKOpiwov7mkepzUxReX6OYOjETpoqfbp1t_s0vlfa1fY0715kpMPkh9Whf9Zbq-WKnqGurh530zC3U1aEpWrF_9JIe5UNEcFcZVf4Ep8RMxEi4NwzlwGC9iGuZieCJo0KJTHubWlkL_WHO6mIFuRTvyP62l8rsVshl3v6SQOBlxMPn60h1cTHfPGKnEsnlWS8DMCXmZTfpimOXGNdV5ufdP-_0JVaiLcbx9zi24uPPUYiPGpsdrFhksJVGufFsWMLOVr5rLkD6FMwlAfnJoXtZsXTXTdx15LGRPEyy0rAHmJ6DMpKPCwri1OlhweblnZEWz0WepBmNPClhqCTfqSOs2N2yyJCB-FF9hCopQhe2Q0b5wLFOsucqVJhRoPAzuGYSMF7y7sjtNq1e-9ZNjRCcCV5JC1IVy8QnlVk_6TedhFs9xQFUjozeUsnI2mcbAaywWW3E195XwjfWPca3M2yFyWgVjliDlD5v3Kgg5ZYpkAM2laMxAIizYJqNuWNkAC57exW6PEizT9hRhtyIZcLTwKhmb3pQhdLcI3SQ6L_L1YiBmf9Gmjf5dlMNrCwsnvrB245ToS3qvZO3tUvxO3gcjG78BvS79iu4fiQVnYll_d8LEPV0invi1lH9sCy2LN7RmHv735yZQ9XRWO-WtXxyFBsjCBaFYILf7OhjFqAuHVi9gTHFVDAd_r877i9-YG10jyV4jeZkz8vhMRaQPqT-8mk7mHQ-W-qyA8yIQ3MuEQpcXXiCR3TwJIOXqYD4M3RjVh7oXHIPn4oI9bxechH6uuG3GpH3rmYrF8ARTTJ-o8sJTLzMTQTraTArKtkjXKjN4wqDRoE4GqtdVF3pD9C73AH-W8aK4jR-NvdtsRRJNL_Qj7Vq93NeN_5tKcMgKk0HDkvbuEVaskk3_nkBjsG2H6UTiBiKIUcYh_MGABOz4ibec6fFw0JMrehl6NdobqJI1q7X_a-_09e6QbaOv3r6I_sAkp9dIUM_3CUAUwNQ76WNL5VbJY6Fm8gq0Fk_Y0OUPfYKXqzP99IRTPEO1uC94N5e_WQq35CXIhfXPcZ8CkxVLXbC-xG64DMvpSvsWCwRnEaQvJi7p3ROEj3GlWD4h_fB2H8lDPS7R0DXspqh9xj9MduqFJshRdNBThJrMHDxlxrZ8YsERDNdIRjzXbv3dJY9tepKTNO59-SPpgDITQ1nzugMorgYCz0mHjPrDX7k21p_mAZcS_AFHDzgIOWKs-rVd9g06PYtMMKEaE3F7g2_leOxMekQn9mUz0GnuuOgu0sSIb-984186HwxclGyDR_McW997oGquUAnkbQUVcVomGO-4HfsINnU6_34wgbcQkdZU4LlXTtenOq8aL4rPEWeryTEYoAG4X1c9lAi4zjEYp550Ez2M-8npUDjAZ3IeC-R_H5DltHlz-lSGcNlmagX1g8CUEFb7UrXZ-Z9bn1Zn3Bp6M_5VrFIcPyBG375o8WpPkWW55buB7CdK2K7jgF_Xuecd4rN3GyK9nj81x0BIs0jPmq2KIOGTsiaTs5rJvjToNBMcosjaSEst61TABIoFuvy9grYszNWarnEfKHdf5gvtZYMwi0wdAE3ahpMG92-K12O8RmAYqi0ceCJOh8OIk28NGYDES8fDh13H4De7oIq7_e23JKHm67Zd5hOl8-tuPwHP4RSTOSCjlzyR0lIU-ZKeOAmq_nO6AEMw9APibzu6BLfY-qzFBpYKtbzdqYfdLiQ2GX6zGaXzc-TKJki1JkLLM5C2PdudS1fRfpmQrgLMZkfjRmqhpEvZMR82Gp4cVOqzjdf36kxNiD0Znv5ApUasjk982ZZ09lEu0slz9rkJOW-PKlUrMJFc47STGKAz7mhMyjdqG4B2oGZ6C_C6fYAp__Bdh7FhFmijAZmw7EQZPY98AOse6nYd3jSo7NB74cOk5GXCzm2BrLGOSNqsVGKkcZpinI9kQLZ9-q_jmaGWWBWVqlylBBsS7w4TkafDzw2KEMtnowzHqKNW0Y1KWTUAmt5bssSY1p-JPdeVqIP43S4RoLoauZPBvXvBs2Sm-kpCAjeqCxvW1lTO7R775ixtastwy0kROE2F9y8kWM0Hl7pmjXVsozmTMwtZOQNQ5etxG3SKZRanBILc9377vEYrB2uzRJScdv-v0Xi0neGhXg6lda_2i8kfLkTUFhaMR6qXl5q5Bz704dzOylCy4kOaZpqagywJ9Gic4ftnHx2Pa_AjL20ups6yXMX4NXSDgKmUZk_qV1zr-2SjqdkYGZ4fGo7A335MRdVjsD1If3NIWz0zhcbsoqD9n6v1E6D9GSEyB2HxTWFGBKL_SImoUspQ0rGL2sAhxLh1v9SWbcOxCmSDCs0lt36MpS4gRDhtqf-Gyi-RYgBR5GRWQ8sYb6Up09QA7Oeq-lYf3dYmIWDM0yaRWM1QbvesV7yw7uEdhrgFDvvbU139HTbLlX3X7X3MsQ1Pq93_xoyirziTWHmvJCai5QizcU-yUSWOvP4DjDTV7yX5IuOGDMLsJvjicH8W128Q-6FGYc_knE78B4TdWoO3gUuXN4KOaxPMiJs4PJKO9tZA569-sJEC_NsTpOQAxdQUKiNLA3Iuc91SeWf6mKCpU3JlCCEyLk5Hl0t0e_SSGzI_QC9LfxCoqPV5_Uz71Cgdm7EEnjqyYPOwS9KLeQ8EGm54BS0Ps5S8pZddDif2um9dk16xLxbMyiPlKkCfJpxJoyACYqBrAnBSTlT67E3Ha9Gk_2OV3HV0s5sQnsOZYb3MzQ20mFFvCrzn5WoUByP5nfFNWyx2712fqy2odnjbM70cgCynR0gIFqqs1XZWx-K52d8AoZKdVytdoWGSQfldIRVXvPiOTqRbw2AXy7Si90QuiDC6BboE_LlDleXk8-fbn_EmOuzn3RmDpa7xkXNAhzbWGcn61wuY96_uXTLVCMhBz9wd4HfFP9GuyaChd8rcdrAjzx_Ym-YjrAvQu-H04utn1_vKpqNxYSeFWoarUahGwsvUBsps0Y1ffyRF2BbPSd6S5WsC03yu9IXEBKywYQM_tMYz3nPOEsqlbyt_eg8d\\\",\\\"id\\\":\\\"rs_d1ed60f47298485d3b4ba768d06166f4132dfd8c441144a790\\\",\\\"summary\\\":[{\\\"text\\\":\\\"**Crafting a weekly plan**\\\\n\\\\nI need to plan the week in a concise way. I could start with something generic like \\\\\\\"Mon–Fri: 9–11 deep work on Priority A and 11–12 for meetings.\\\\\\\" I\'m considering stating that \\\\\\\"Tue/Thu are for admin and emails, while Wednesday is for review and planning.\\\\\\\" But wait, I need to make sure it really is one line! I’ll finalize it as: \\\\\\\"Mon–Fri: 9–11 deep work on Priority A, 11–12 meetings; 1–4 admin; Wed: review; Fri: wrap-up; Sat/Sun: rest.\\\\\\\"\\\",\\\"type\\\":\\\"summary_text\\\"}],\\\"type\\\":\\\"reasoning\\\"}]\"", "response [\"Mon–Fri: 9–11 deep work on Priority A, 11–12 meetings, 1–4 admin/communications; Wed: midweek review; Fri: wrap‑up and plan next week; Sat/Sun: rest.\"] metadata: {\"cacheWriteTokenCount\":0,\"finishReason\":\"stop\",\"model\":\"gpt-5-nano-2025-08-07\",\"requestID\":\"req_1\",\"responseID\":\"resp_3cba0b7f18ac52680254e110b223921e34b858ee1d3be7f9bd\",\"serviceTier\":\"flex\"}"]
            """#
        }
    }

    @Test func `a real second turn reads its long instructions from OpenAI's cache`() async throws {
        let exchange = try await ExactExchange(replaying: .cached)

        assertInlineSnapshot(of: exchange.usage ?? "no usage", as: .lines) {
            """
            input 1536 cached 1408, output 20 reasoning 0, metadata: {"cacheWriteTokenCount":0}
            """
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a real answer about earlier attachments reads as OpenAI sent it`() async throws {
        let exchange = try await ExactExchange(replaying: .attachments)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-5-nano",
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
              ],
              "reasoning": {
                "effort": "minimal"
              },
              "max_output_tokens": 500
            }

            transcript
            prompt ["Keep these.", attachment Photo, attachment Menu] metadata: {}
            response ["Kept."] metadata: {"assetIDs":[]}
            prompt ["What's in these?"] metadata: {}
            reasoning [] metadata: {"model":"gpt-5-nano-2025-08-07","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq7k6bVh0ai0jNkm4-ZLpDyy_SpyVvIj8nxXCqdvPVQ8z5wKvEYg194q3_FM6_9dTUDL_l2BbaERjl6rKNDKmr7FOZ8DGIYKa_v1_fMpmpyXO3qa7mCHDZg9pkSKoUYib4VFe8IEJwtMub1vcUuY0y_NT1bEWcqxu_F60544SCuP9mUifq9SVhBICPITtZ4rnzYSMYI3HhkRubOK6H69km9m0Eceg1vq8Y5i4Kj6UC8bUpERo_MCxacg4UWfASkCRy0thakGs7PdHKfJyCefuzUPVnuSbcPfdZdIQ3399aNKWySpkR6rXYxC_HsLfFQAQYeBNwtDhzDaGqPJeY6LqrUXF9JZM4mZPnYnOC-ecAaoOU3pFpYLFEZCz1MHbUBmwWQDry9pDE5yoHpX5xiEG6JVPo0XJDyxR-dJmWZ_18HMlQ3tOHj12a_Ld4W-ssZj70wywW0crfIAXIYf1_J9h4-mNiqg83DzSisJSI2o-P3o6o8OiHk9AYCSqky1CpX-ZWUwFV6fA3EqXThGCGu_sCj_9y7e_FNd60rRMwy0VII2KO2NGvH2rl2uXWgdzVB9X6vajwOHYFqSrPEbe73cbOznCIVGqF6pmCIcMWwKBgYycmnd989jIeZ04noyBiWZj5p3bsxLLqLxqd3sCTaLOVzCYJP5eXH7oHVHqSecx1YDYoBfHQasZyO-0xRez32acmpUIaEga5L_NxXNMEWK3zdMben23yFmkcweoZMUfyqjo4HwkLJ2v7tzGaWJRtc2ewlUpyfRhC88mX7vYvf6oXGA0dNfAkiEXXeN-SOHpjGpXJtXY0F8O9qiBkeYXJzpMbKR5R_-Y6RL4hV1eJ0zyDv5-g2us02fcxx4lCg42_u0jJIIV_tXKfo0x4OL2sNN41lKgbidikOzF-0KCA9K27y-IvYURbEAVCMW-PFP0B0Uul_QWliZLZWw0BpnWTcTkquYsZ7Aj9h81e6xNufu6EugLB_TgSk4KrCK4ve-YjKJg5ki8lmDlEIhxu7gOyWxAsmVAdbRRtwRz5tesg_JGrSNfGSUq2RRo1KUpVkxetmhhkBQYzEnezIqKaaj3gWRkSRMBcl_u5cPEk6QHPnNAKNHNpgi6ZJK6aS-fg07NSkHQUr5hd8FLRcqSyZmxWAIOUprElugQJYlTv8VQnYGfXtBAN8dH4-wPZrEOUWnhPGKxaWyfkuqZXEpslMbJxvuSgWwuyNX9LbAxxsyVJkgKUeImiLhvhUxAOxj9tqdFCSCMdadM7Qe6r_-_AFNdQFS0tLeySl4pSqv023RvQ9KMqh5JI21dLCCdx1ACkDepbwpPFY5B0P9OE4gYQx43CeBmpNdXZ8ki_3imOPL_4mHPwNArZzHhCqXMIWzT8JocE40f9ggk3ZwelLeMeMxaF6koJmhTYzWpM9uI4xBYR3UT07qWO4TAv_NNh_WHJvdwCZBD2yLljAs1rNhfHXcqsph0gyiDzuSlHCoDe4hzAkUPJO8qdlBFWikZuLMjuJ_ssYR_W3tNUTn353Fkll5bE4z9AMW1KkF6_1gXYLQetXocYpFh518FtqeoiePAW4MYDF12n_zOiQkgPOi3qWJppYQ02zLMtVbDgYIaRW02PzJLWPbhtIZCFeNsheb_fLAa7YQOOOjGLQTdVYJmbcPnFq7_zZpqkp6FGj8kaFdMcH8KDhF_efHg_gSqv6Xqva0z0LVXAZrUs__wQNT5kglK63n6xbskj9AWF7cUtLJxx4QFullQWjvAUuwKqWIztiD96qOY8KM1IeMcEjbqTz7jxzmnfkkcoo4yhNeQKM1v486ZJvzFiNA==\",\"id\":\"rs_3f970c12be062f690f8bbb90ce6389fbfb0ecb3b7b21b9ecef\",\"summary\":[],\"type\":\"reasoning\"}]"
            response ["You shared two items:\n- A small image labeled “Photo” that shows a black-on-orange menu item with “Menu” text; I can’t identify its contents from the image alone.\n- Text that says “Soup of the day.”\n\nIf you want details, you could:\n- Describe the photo or upload a clearer image for transcription or ingredient guesses.\n- Provide the menu context or day’s soup to help identify possible ingredients."] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-5-nano-2025-08-07","requestID":"req_1","responseID":"resp_12470ac8003684594a0702f762bdd25d295cd6e7a161e146bd","serviceTier":"default"}

            usage
            input 52 cached 0, output 104 reasoning 0, metadata: {"cacheWriteTokenCount":0}
            """#
        }
    }
    #endif

    @Test func `every recorded failure ends in the error it maps to`() async throws {
        let failures = try await [
            ("invalid key", ExactExchange(replaying: .invalidKey).error),
            ("unknown model", ExactExchange(replaying: .unknownModel).error),
            ("context overflow in the stream", ExactExchange(replaying: .contextOverflow).error),
        ]

        assertInlineSnapshot(of: failures.map { "\($0.0)\n\($0.1 ?? "no error")" }.joined(separator: "\n\n"), as: .lines) {
            """
            invalid key
            OpenAIError(status: Optional(401), message: "Incorrect API key provided: sk-invalid. You can find your API key at https://platform.openai.com/account/api-keys.", code: invalid_api_key, errorType: Optional(invalid_request_error), parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: false)

            unknown model
            OpenAIError(status: Optional(404), message: "The model `gpt-no-such-model` does not exist or you do not have access to it.", code: model_not_found, errorType: Optional(invalid_request_error), parameter: nil, requestID: Optional("req_1"), retryAfter: nil, isQuotaExhausted: false)

            context overflow in the stream
            LanguageModelError.contextSizeExceeded contextSize: 400000 tokenCount: 0 "Your input exceeds the context window of this model. Please adjust your input and try again." metadata: [errorCode: context_length_exceeded, requestID: req_1]
            """
        }
    }
}
