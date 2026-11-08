import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

extension RecordedExchangeTests {
    @Test func `a real web search's call, sources and citations read as OpenAI sent them, and the call goes back`() async throws {
        let exchange = try await ExactExchange(replaying: .webSearch)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web: what is the latest stable release of Swift? One sentence."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content",
                "web_search_call.action.sources"
              ],
              "tools": [
                {
                  "type": "web_search"
                }
              ],
              "reasoning": {
                "summary": "auto"
              },
              "max_output_tokens": 4000,
              "max_tool_calls": 2
            }

            request 2
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web: what is the latest stable release of Swift? One sentence."
                },
                {
                  "action": {
                    "queries": [
                      "latest stable release Swift programming language official release"
                    ],
                    "query": "latest stable release Swift programming language official release",
                    "sources": [
                      {
                        "type": "url",
                        "url": "https://www.swift.org/blog/"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.org/blog/swift-6.4-released/?trk=article-ssr-frontend-pulse_little-text-block"
                      },
                      {
                        "type": "url",
                        "url": "https://github.com/swiftlang/swift-evolution/blob/main/README.md?plain=1"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.org/install/macos/"
                      },
                      {
                        "type": "url",
                        "url": "https://swiftlee-weekly.com/swift-evolution/releases/"
                      },
                      {
                        "type": "url",
                        "url": "https://developer.apple.com/swift/blog/"
                      },
                      {
                        "type": "url",
                        "url": "https://github.com/swiftlang/swift-evolution"
                      },
                      {
                        "type": "url",
                        "url": "https://swiftly.dev/swift-versions"
                      },
                      {
                        "type": "url",
                        "url": "https://forums.swift.org/c/development/dev-announce/17"
                      },
                      {
                        "type": "url",
                        "url": "https://zairalabs.ai/guide/languages/swift/"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.org/blog/swift-6.3-released/?trk=article-ssr-frontend-pulse_little-text-block"
                      },
                      {
                        "type": "url",
                        "url": "https://github.com/SwiftLang"
                      },
                      {
                        "type": "url",
                        "url": "https://en.wikipedia.org/wiki/Swift_%28programming_language%29"
                      },
                      {
                        "type": "url",
                        "url": "https://en.wikipedia.org/wiki/Swift_%28parallel_scripting_language%29"
                      },
                      {
                        "type": "url",
                        "url": "https://www2.swift.com/knowledgecentre/rest/v1/publications/sref_rl_20230929/2.0/sref_rl_20230929.pdf?logDownload=true"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.com/swift-resource/251959/download"
                      },
                      {
                        "type": "url",
                        "url": "https://es.wikipedia.org/wiki/Swift_%28lenguaje_de_programaci%C3%B3n%29"
                      },
                      {
                        "type": "url",
                        "url": "https://en.wikipedia.org/wiki/Julia_%28programming_language%29"
                      },
                      {
                        "type": "url",
                        "url": "https://www.reddit.com/r/iOSProgramming/comments/1x3leg8/what_happened_to_the_swift_on_android_what_is/"
                      },
                      {
                        "type": "url",
                        "url": "https://en.wikipedia.org/wiki/Python_%28programming_language%29"
                      },
                      {
                        "type": "url",
                        "url": "https://en.wikipedia.org/wiki/Swift_Playgrounds"
                      },
                      {
                        "type": "url",
                        "url": "https://bobkonf.de/2024/slides/chakravarty.pdf"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.com/sites/default/files/documents/swift_release_timeline_q2_2020.pdf"
                      },
                      {
                        "type": "url",
                        "url": "https://www.reddit.com/r/swift/comments/1w4yo7y/whats_everyone_working_on_this_month_september/"
                      },
                      {
                        "type": "url",
                        "url": "https://www2.swift.com/knowledgecentre/rest/v1/publications/sref_rl_20211119/1.0/sref_rl_20211119.pdf?logDownload=true"
                      },
                      {
                        "type": "url",
                        "url": "https://www.reddit.com/r/swift/comments/192tvaf/no_way_to_get_a_clean_the_swift_programming/"
                      },
                      {
                        "type": "url",
                        "url": "https://www.reddit.com/r/swift/comments/1c7ju6l/where_can_i_find_the_epub_ebook_for_the_swift/"
                      },
                      {
                        "type": "url",
                        "url": "https://www.reddit.com/r/swift/comments/1nid8ln"
                      },
                      {
                        "type": "url",
                        "url": "https://arxiv.org/abs/2609.28822"
                      }
                    ],
                    "type": "search"
                  },
                  "id": "ws_10b349fa4eb3ec0767faeb2628eae9067277d0d2c007ba6ae6",
                  "status": "completed",
                  "type": "web_search_call"
                },
                {
                  "content": [],
                  "encrypted_content": "gAAAAABq8KJ0xg7cvrl7KsSaIBAO3N7Cdlzm4ihEEHixncmH1wpGkuPssdgTl4rJfkcEqxAjqbOp2uIGnz6SD1tJEV3fCiQrcU_9hJEIDabm0G1Ws6cYggMK5hJ1PAyu_tqbD_-qU2cBKiWGkyOgl5-1xpWt-4fE4GgDV1G6cjxUs-_ZO3pS7n7jGcSx2lmO8uvAREypWmRzBAgUby1M96n_6_gGfgU6IPESPdM8aZgR1z6EHXp1jR6XM75VSf-myXaKPejWiedp5ijICKBVKx2zNOXBvS1elMTGieSm8QTH-5oqKKlZohUYOQjELXoOtwIcOd2xz5qaJ65ZOiezuNUckplFhm51xKRE98rhg7DIHqOrTP8CxKj_WysJrAzbuDUhzzGiwPa9gX05nEbsnhZQotw-H0dXHeNG3bXz5KYQJ92Ng0MCmfZI1NOEai9tEW7Xu4eP3Nhmuw6zrQ5Ofqb1Ctzk-rv7EAdUj1Nl8TPjdWR6j705XMweMJxJN5vAILvRJmrNYHrexWagjFyGEsYWFG2fOz0OkERJbgnmF8R0tNtQrykeIlpYpJcrMAbHzYIRS6tJnKCzbva3jYek-y2cRr3_2eouQPbNhFoHzXcrNSogCPZr7AmE3cFMg8lVIcw4uHentgv3mAmnFljZdUyp8WnmptrkvTwzr-T_3oHHG753a27FChKCvlv83xWr8__bUxNKjLEQP_bjfFUn1T-NT8Mi99YNU7ZIjSdJgGXfA7q6-kvXW_f9sCnc-9OnWPo5L-XdDNuS-8oGEMEytrXRfxJtRVRPt_0PzTuu4Zp1BgnyV5b_o4RIf0UC5HnHZ_hEPMmGjGMgrQYZ7V5l3WQuwxst5DBQLOQrhF3zjrgoXFJdCGsd8lgtN1_dgSbzJquTwqDei_IGcoH2DRXS9nXKOS--X29BIdJWLc78EvPv8mYxnBsZtRq_Z0XrTrFeHIWzai5yhF2oE09rRZ5ofYuFq8FW3FNK-Iwm72BuQD5lnoZ96d_K53RfDKLzRvdNyQ0tx75mDduiDgel3EKucO1ahVmoGsggOxKkO5rZa7_OVZNJUVOqw-UKtK7JzvPqdRJQhB-QE2qey8Jlc8SDfHEvZQ_sdxuW4IDMqGnvHxLdnnbX14LuTDIv298d1WyP1y2nBgmZLU25VeE70hQ8bBZW1C2Np3NMf_NLKj1xZTk2z-FQz_R63Eh0Ihx3A1SiBRogyAdnQZgpATLdOGRzFr0PEwBf5ImdxwtH5G-mr_TcbhoKtNBlhCmIxPrJ2fYJ1g50dUItGZsk0ebHERb0Jukh0Ew-yzqCSD4Alt21xlP3EX7B-h5LyC278-3rM08pzniXdPzpZZmwno4ZedQHVE-DekAmwTv2be5bo8laFtmi5ZgO4r1T6AtO9t3fPFh4buVJU_I3djKavFysIj3kdB1ssoIqL3ETKfpncXqi_4YUu4M8_mMdhrqJlI-Ny3WrgKVPZBVWq4-sG335ohMhHBViXmetUbwCl9sPfv1Uu7CYCep4HHlUd4_7T5c8VFGXhMAb0uy9FtzWtqqtnKNO-T8g8CSK2BHcEaGj8r7JD-_w1_1nhBbG_ENMmNsFgba1ygCTASXWPPUH3ICxEABpW5R481vD_2i8ggteaXMGLsoV5qQaf0BA5RfKxydDVwIjpbLgSdYUYRO3pUGMObEadrEcBURoJeFIgUZK4ZEgzUwfAbZWkH3dq7sH-1Zz9HVo0aAyoIHNw8oy1V2C5iDOCYtVP9X1oLUV9sx3NE4DtV5NC9F2Zv0lUOaLSJScG61WfbpLPYlls69n-BE6enKGHNQ3r0NJbaesQomRUGBl69hgnTXZPYueKhm5uORopiMXEHJd_Bx6oGNccBFtyuaJtRJFKpn_dU9alVpZQyHtwO965hG2J9ofUExzPHqPidnHAutc3ch6_jnGYR0tIrwKMwjQxAY-yyegjYRbOm50Pxt_ew66ou9qBwCKkbIWeJfbNrukZOoSlDBLUcGEBkFZF7iyuhD9UHxHaafZWLGDI-FeOGAxUbO3voMvKyg34UZdUvzWdCB1jGk15XzAqxAUlkTzFXC0Sy70r5wl9IOjWCuXzipMYRS-GPHhkUTOHeMx30FHdBb5aZ_SilJhdzbwlaYntxHZYxFxvD3PburhF8wR3uMFHkPwPe0zUerC_-oIl9Ed7wckWKmliKAFYzcq4rjaw6UCnBsF2g==",
                  "id": "rs_7d6138127ba32cbf0908f4310bce391e51b9e8517beb3d0bb6",
                  "summary": [
                    {
                      "text": "**Verifying latest release**\n\nI need to check for the likely latest stable release, which looks like version 6.4 with a potential patch at 6.4.2. It’s important to verify this by looking at the official Swift download releases. The user is asking about the latest stable release, so I'll search the official GitHub releases page to confirm the right version. This will ensure I provide accurate and up-to-date information for the user!",
                      "type": "summary_text"
                    }
                  ],
                  "type": "reasoning"
                },
                {
                  "action": {
                    "queries": [
                      "site:swift.org/blog \"Swift 6.4.2\"",
                      "site:github.com/swiftlang/swift/releases Swift 6.4.2 release",
                      "site:swift.org \"6.4.2\" Swift release"
                    ],
                    "query": "site:swift.org/blog \"Swift 6.4.2\"",
                    "sources": [
                      {
                        "type": "url",
                        "url": "https://www.swift.org/install/windows/"
                      },
                      {
                        "type": "url",
                        "url": "https://github.com/swiftlang/swift/releases"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.org/install/windows/manual/"
                      },
                      {
                        "type": "url",
                        "url": "https://forums.swift.org/t/announcing-swift-6-4-2/90337"
                      },
                      {
                        "type": "url",
                        "url": "https://forums.swift.org/t/development-open-for-swift-6-4-3-for-non-darwin-platforms/90403"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.org/install/linux/debian/12/"
                      },
                      {
                        "type": "url",
                        "url": "https://github.com/swiftlang/swift-evolution/blob/main/README.md?plain=1"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.org/install/linux/debian/13/"
                      },
                      {
                        "type": "url",
                        "url": "https://github.com/swiftlang/swift-llbuild/releases"
                      },
                      {
                        "type": "url",
                        "url": "https://forums.swift.org/c/general-announce/24"
                      },
                      {
                        "type": "url",
                        "url": "https://www.swift.org/install/macos/package_installer/"
                      },
                      {
                        "type": "url",
                        "url": "https://github.com/swiftlang/swift-build/releases"
                      }
                    ],
                    "type": "search"
                  },
                  "id": "ws_eecb54d15323721f327d2c04d38c1d7feac25542b4213db93b",
                  "status": "completed",
                  "type": "web_search_call"
                },
                {
                  "role": "assistant",
                  "content": "The latest stable Swift release is **Swift 6.4.2**, released October 30, 2026. ([forums.swift.org](https://forums.swift.org/t/announcing-swift-6-4-2/90337?utm_source=openai))",
                  "phase": "final_answer"
                },
                {
                  "role": "user",
                  "content": "When was it released? One sentence."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content",
                "web_search_call.action.sources"
              ],
              "tools": [
                {
                  "type": "web_search"
                }
              ],
              "reasoning": {
                "summary": "auto"
              },
              "max_output_tokens": 4000,
              "max_tool_calls": 2
            }

            transcript
            prompt ["Search the web: what is the latest stable release of Swift? One sentence."] metadata: {}
            reasoning ["**Verifying latest release**\n\nI need to check for the likely latest stable release, which looks like version 6.4 with a potential patch at 6.4.2. It’s important to verify this by looking at the official Swift download releases. The user is asking about the latest stable release, so I'll search the official GitHub releases page to confirm the right version. This will ensure I provide accurate and up-to-date information for the user!"] metadata: {"model":"gpt-6-luna","reasoningOrigin":"openai-responses"} signature: "[{\"type\":\"web_search_call\"},{\"content\":[],\"encrypted_content\":\"gAAAAABq8KJ0xg7cvrl7KsSaIBAO3N7Cdlzm4ihEEHixncmH1wpGkuPssdgTl4rJfkcEqxAjqbOp2uIGnz6SD1tJEV3fCiQrcU_9hJEIDabm0G1Ws6cYggMK5hJ1PAyu_tqbD_-qU2cBKiWGkyOgl5-1xpWt-4fE4GgDV1G6cjxUs-_ZO3pS7n7jGcSx2lmO8uvAREypWmRzBAgUby1M96n_6_gGfgU6IPESPdM8aZgR1z6EHXp1jR6XM75VSf-myXaKPejWiedp5ijICKBVKx2zNOXBvS1elMTGieSm8QTH-5oqKKlZohUYOQjELXoOtwIcOd2xz5qaJ65ZOiezuNUckplFhm51xKRE98rhg7DIHqOrTP8CxKj_WysJrAzbuDUhzzGiwPa9gX05nEbsnhZQotw-H0dXHeNG3bXz5KYQJ92Ng0MCmfZI1NOEai9tEW7Xu4eP3Nhmuw6zrQ5Ofqb1Ctzk-rv7EAdUj1Nl8TPjdWR6j705XMweMJxJN5vAILvRJmrNYHrexWagjFyGEsYWFG2fOz0OkERJbgnmF8R0tNtQrykeIlpYpJcrMAbHzYIRS6tJnKCzbva3jYek-y2cRr3_2eouQPbNhFoHzXcrNSogCPZr7AmE3cFMg8lVIcw4uHentgv3mAmnFljZdUyp8WnmptrkvTwzr-T_3oHHG753a27FChKCvlv83xWr8__bUxNKjLEQP_bjfFUn1T-NT8Mi99YNU7ZIjSdJgGXfA7q6-kvXW_f9sCnc-9OnWPo5L-XdDNuS-8oGEMEytrXRfxJtRVRPt_0PzTuu4Zp1BgnyV5b_o4RIf0UC5HnHZ_hEPMmGjGMgrQYZ7V5l3WQuwxst5DBQLOQrhF3zjrgoXFJdCGsd8lgtN1_dgSbzJquTwqDei_IGcoH2DRXS9nXKOS--X29BIdJWLc78EvPv8mYxnBsZtRq_Z0XrTrFeHIWzai5yhF2oE09rRZ5ofYuFq8FW3FNK-Iwm72BuQD5lnoZ96d_K53RfDKLzRvdNyQ0tx75mDduiDgel3EKucO1ahVmoGsggOxKkO5rZa7_OVZNJUVOqw-UKtK7JzvPqdRJQhB-QE2qey8Jlc8SDfHEvZQ_sdxuW4IDMqGnvHxLdnnbX14LuTDIv298d1WyP1y2nBgmZLU25VeE70hQ8bBZW1C2Np3NMf_NLKj1xZTk2z-FQz_R63Eh0Ihx3A1SiBRogyAdnQZgpATLdOGRzFr0PEwBf5ImdxwtH5G-mr_TcbhoKtNBlhCmIxPrJ2fYJ1g50dUItGZsk0ebHERb0Jukh0Ew-yzqCSD4Alt21xlP3EX7B-h5LyC278-3rM08pzniXdPzpZZmwno4ZedQHVE-DekAmwTv2be5bo8laFtmi5ZgO4r1T6AtO9t3fPFh4buVJU_I3djKavFysIj3kdB1ssoIqL3ETKfpncXqi_4YUu4M8_mMdhrqJlI-Ny3WrgKVPZBVWq4-sG335ohMhHBViXmetUbwCl9sPfv1Uu7CYCep4HHlUd4_7T5c8VFGXhMAb0uy9FtzWtqqtnKNO-T8g8CSK2BHcEaGj8r7JD-_w1_1nhBbG_ENMmNsFgba1ygCTASXWPPUH3ICxEABpW5R481vD_2i8ggteaXMGLsoV5qQaf0BA5RfKxydDVwIjpbLgSdYUYRO3pUGMObEadrEcBURoJeFIgUZK4ZEgzUwfAbZWkH3dq7sH-1Zz9HVo0aAyoIHNw8oy1V2C5iDOCYtVP9X1oLUV9sx3NE4DtV5NC9F2Zv0lUOaLSJScG61WfbpLPYlls69n-BE6enKGHNQ3r0NJbaesQomRUGBl69hgnTXZPYueKhm5uORopiMXEHJd_Bx6oGNccBFtyuaJtRJFKpn_dU9alVpZQyHtwO965hG2J9ofUExzPHqPidnHAutc3ch6_jnGYR0tIrwKMwjQxAY-yyegjYRbOm50Pxt_ew66ou9qBwCKkbIWeJfbNrukZOoSlDBLUcGEBkFZF7iyuhD9UHxHaafZWLGDI-FeOGAxUbO3voMvKyg34UZdUvzWdCB1jGk15XzAqxAUlkTzFXC0Sy70r5wl9IOjWCuXzipMYRS-GPHhkUTOHeMx30FHdBb5aZ_SilJhdzbwlaYntxHZYxFxvD3PburhF8wR3uMFHkPwPe0zUerC_-oIl9Ed7wckWKmliKAFYzcq4rjaw6UCnBsF2g==\",\"id\":\"rs_7d6138127ba32cbf0908f4310bce391e51b9e8517beb3d0bb6\",\"summary\":[{\"text\":\"**Verifying latest release**\\n\\nI need to check for the likely latest stable release, which looks like version 6.4 with a potential patch at 6.4.2. It’s important to verify this by looking at the official Swift download releases. The user is asking about the latest stable release, so I'll search the official GitHub releases page to confirm the right version. This will ensure I provide accurate and up-to-date information for the user!\",\"type\":\"summary_text\"}],\"type\":\"reasoning\"},{\"type\":\"web_search_call\"},{\"type\":\"message\"}]"
            response ["The latest stable Swift release is **Swift 6.4.2**, released October 30, 2026. ([forums.swift.org](https://forums.swift.org/t/announcing-swift-6-4-2/90337?utm_source=openai))"] metadata: {"cacheWriteTokenCount":4455,"citations":[{"endOffset":174,"excerpt":null,"startOffset":79,"title":"Announcing Swift 6.4.2 - Announcements - Swift Forums","url":"https://forums.swift.org/t/announcing-swift-6-4-2/90337?utm_source=openai"}],"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":174,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"action\":{\"queries\":[\"latest stable release Swift programming language official release\"],\"query\":\"latest stable release Swift programming language official release\",\"sources\":[{\"type\":\"url\",\"url\":\"https://www.swift.org/blog/\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/blog/swift-6.4-released/?trk=article-ssr-frontend-pulse_little-text-block\"},{\"type\":\"url\",\"url\":\"https://github.com/swiftlang/swift-evolution/blob/main/README.md?plain=1\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/install/macos/\"},{\"type\":\"url\",\"url\":\"https://swiftlee-weekly.com/swift-evolution/releases/\"},{\"type\":\"url\",\"url\":\"https://developer.apple.com/swift/blog/\"},{\"type\":\"url\",\"url\":\"https://github.com/swiftlang/swift-evolution\"},{\"type\":\"url\",\"url\":\"https://swiftly.dev/swift-versions\"},{\"type\":\"url\",\"url\":\"https://forums.swift.org/c/development/dev-announce/17\"},{\"type\":\"url\",\"url\":\"https://zairalabs.ai/guide/languages/swift/\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/blog/swift-6.3-released/?trk=article-ssr-frontend-pulse_little-text-block\"},{\"type\":\"url\",\"url\":\"https://github.com/SwiftLang\"},{\"type\":\"url\",\"url\":\"https://en.wikipedia.org/wiki/Swift_%28programming_language%29\"},{\"type\":\"url\",\"url\":\"https://en.wikipedia.org/wiki/Swift_%28parallel_scripting_language%29\"},{\"type\":\"url\",\"url\":\"https://www2.swift.com/knowledgecentre/rest/v1/publications/sref_rl_20230929/2.0/sref_rl_20230929.pdf?logDownload=true\"},{\"type\":\"url\",\"url\":\"https://www.swift.com/swift-resource/251959/download\"},{\"type\":\"url\",\"url\":\"https://es.wikipedia.org/wiki/Swift_%28lenguaje_de_programaci%C3%B3n%29\"},{\"type\":\"url\",\"url\":\"https://en.wikipedia.org/wiki/Julia_%28programming_language%29\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/iOSProgramming/comments/1x3leg8/what_happened_to_the_swift_on_android_what_is/\"},{\"type\":\"url\",\"url\":\"https://en.wikipedia.org/wiki/Python_%28programming_language%29\"},{\"type\":\"url\",\"url\":\"https://en.wikipedia.org/wiki/Swift_Playgrounds\"},{\"type\":\"url\",\"url\":\"https://bobkonf.de/2024/slides/chakravarty.pdf\"},{\"type\":\"url\",\"url\":\"https://www.swift.com/sites/default/files/documents/swift_release_timeline_q2_2020.pdf\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/1w4yo7y/whats_everyone_working_on_this_month_september/\"},{\"type\":\"url\",\"url\":\"https://www2.swift.com/knowledgecentre/rest/v1/publications/sref_rl_20211119/1.0/sref_rl_20211119.pdf?logDownload=true\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/192tvaf/no_way_to_get_a_clean_the_swift_programming/\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/1c7ju6l/where_can_i_find_the_epub_ebook_for_the_swift/\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/1nid8ln\"},{\"type\":\"url\",\"url\":\"https://arxiv.org/abs/2609.28822\"}],\"type\":\"search\"},\"id\":\"ws_10b349fa4eb3ec0767faeb2628eae9067277d0d2c007ba6ae6\",\"status\":\"completed\",\"type\":\"web_search_call\"}","{\"action\":{\"queries\":[\"site:swift.org/blog \\\"Swift 6.4.2\\\"\",\"site:github.com/swiftlang/swift/releases Swift 6.4.2 release\",\"site:swift.org \\\"6.4.2\\\" Swift release\"],\"query\":\"site:swift.org/blog \\\"Swift 6.4.2\\\"\",\"sources\":[{\"type\":\"url\",\"url\":\"https://www.swift.org/install/windows/\"},{\"type\":\"url\",\"url\":\"https://github.com/swiftlang/swift/releases\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/install/windows/manual/\"},{\"type\":\"url\",\"url\":\"https://forums.swift.org/t/announcing-swift-6-4-2/90337\"},{\"type\":\"url\",\"url\":\"https://forums.swift.org/t/development-open-for-swift-6-4-3-for-non-darwin-platforms/90403\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/install/linux/debian/12/\"},{\"type\":\"url\",\"url\":\"https://github.com/swiftlang/swift-evolution/blob/main/README.md?plain=1\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/install/linux/debian/13/\"},{\"type\":\"url\",\"url\":\"https://github.com/swiftlang/swift-llbuild/releases\"},{\"type\":\"url\",\"url\":\"https://forums.swift.org/c/general-announce/24\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/install/macos/package_installer/\"},{\"type\":\"url\",\"url\":\"https://github.com/swiftlang/swift-build/releases\"}],\"type\":\"search\"},\"id\":\"ws_eecb54d15323721f327d2c04d38c1d7feac25542b4213db93b\",\"status\":\"completed\",\"type\":\"web_search_call\"}"]},"requestID":"req_1","responseID":"resp_ae79c0d2d30b9ce28bd0da6dcf50cf3eef2c22b18f408c38c6","serviceTier":"default","webSearchCount":2}
            prompt ["When was it released? One sentence."] metadata: {}
            reasoning [] metadata: {"model":"gpt-6-luna","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq8KJ6mYWeCG8hlznt2rWUuLpLt1MXWEkssvx0DSKe1CWytG9Ocgs8EU5BP3dAdHGaWT6h8s6R0kHRbidfELDrg-PRMT6TJaW9iI8PD0vyu4UTgov1wAR_k3PeNAjOjZuKeGiycOJp4H3RxKrMFMLlDXy2rhMVqcdVJeyj5Mclg2I7wBo4C4pZmv3kpgMNpzDbgVmLbFvbcLPCiIYCEFOq-5teYi1rUJuCYz_tE_GNzputmVN_MYwdIj4hXWuLILqaAig9CASXUG8W1BoMAJInWIxvTTg6yP0c5mYJ6bju2Lq0Qu-XII6HHuSjI_m8QXYu3lx3o9gsaHritOjdpaIRAfCPcrjTxBa76f-OLvrXsv9zwolw7do8BexGWbSfX1YqlIlj_n06OtvffxT62UzGdYXH-s-RRlfa95JGaHpPcB_GW3_F5qLDzC9eQtAwnvbRDvzKe5or21tsiUkGMnguLLdHx-ufeWxS8jtttXgT0zGjLfT6Pbz4X2eym6u3GMWTVsjzbg4tqstxCunAp7AZM-BxwCHzN-YjV-TkG73tA82yUa6KzA1edanza6Cg_c9GgGTQik2Wcgw5FX-gfiU16PV5A28shTvPsNnYQVh4dIUjsVpBQDp78VyPMUbw4RUH4R7juluHEG5BI4xLcntZvOe_MT5z5BU9KP8DHsj7kWwelPdvci-QhMn4a9qyxawnfV8KhOioi1JO-opOES59SRVwC2dfax_VGQwvGySHP03ml1MPTbcRWIoN8ryq5UI1SSrI_IQae5QMlioVPeh_rMbVejPSBHIXIyYVNM4ozPVcM6kKxrJqlcCG3Mg-z0r8mu6X5bb7qnfZzG7ZjjqaEOW0CsyzcGmuv3IG56iRcvRwKtODnHxTXfMfA9gwCT1hoFcwyk8xaANLrVM9l1lce7eMzYO8kh9PgEDND4iXTZA5lTo5bRqnyG39CUewxcX9DXih43SekxU3wtegwa5ruDRFNq9ZAwa3YYuIwytK0CaosPB917iDt1kcjCLvIoQtDZdX1thVeIkkhMOLDNe0QWb9dvsgEJFg18aM6DieaO19fMRNjfirIlcz6mRHruESzGLPbaxNED3o7UVofLMvPkV8GavPJUjvFiHhLJ1rWIknmyV_59LUI48b55tN30JCVnN1lIq3E-oHQ92xbR_AUNbqbdxj1ROmcDVWVdZzWO_CFiXcBtsQt7dvs1385A0bocnFSCVJj3Kws_hfrjDE17jfTt9awaqm1v_QeSJhXegOzr6JKty35S1usWLTfpaUXLvyNKdu4muvwn-XVVJDMzV-7Mzxc2lPHwa3vznboSH5HNlEfFb4Yx3uruMhx3eSuBQCpbLFKXrqYzMDW9EZRFHtxtN0LdPZ6y2D9TanoILVpyDyPhV-WKpGuTTx-kKevq09nEBzgkDsRfDD5O8Tv9AvMu7aUE5q6x5cnyiQZyWsgwf36yvB3dkmgdNpOr-EqT3EsXwM7-JaT486jkg9QnauW9TE5R2vLK6EmZ0zkJVjgRFct6DjKPcJO9lGxJTUWJ1nrhK5yH9EJ3lrbC9yi4Yd78c9aqx0yYNlE-HD5LE_LmCByJiofyrLFDa-iZm3iX3dC0c_06p_ldpIVbvzGm6VSkWHix6Oxh9Dhufjbe5lRyn3fJ3uszbq-RvcyXUAFfPNvBBMhUewHlHxerE_qh2vLvOFJBwcJio7NgEBSfPDzbuZSM2vYaKctKZ0yPajrInyDKReprAfxtjIvLrj7U9M0FpEa1Dv6chmX2UEJqGsWhySj_r7j99mzmRAmwSrfwOPUUV7V_T6G9z5gtbSViP6mXSJAdnawuVBDGR1ahhRSQlVf4KISvXXVplQjcrlE11jr25wUqEksPWt5vTBIzLB8otOjWYCRMN2MvaT_QdDHO5jAWGrmENunD8Uf4wgqvf2AsbRiwPnQ3LMb8nDnWjh7K4CY7bejbU--x4GudyziyDaJWVe5Vjq3NtDZmvwkLvS\",\"id\":\"rs_d400d0b97d1252b0db322b1383be999576e618ef438af168ba\",\"summary\":[],\"type\":\"reasoning\"},{\"type\":\"web_search_call\"},{\"type\":\"message\"}]"
            response ["Swift 6.4.2 was released on **October 30, 2026**. ([forums.swift.org](https://forums.swift.org/t/announcing-swift-6-4-2/90337?utm_source=openai))"] metadata: {"cacheWriteTokenCount":231,"citations":[{"endOffset":145,"excerpt":null,"startOffset":50,"title":"Announcing Swift 6.4.2 - Announcements - Swift Forums","url":"https://forums.swift.org/t/announcing-swift-6-4-2/90337?utm_source=openai"}],"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":145,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"action\":{\"queries\":[\"Swift 6.4.2 release date October 30 2026 official\"],\"query\":\"Swift 6.4.2 release date October 30 2026 official\",\"sources\":[{\"type\":\"url\",\"url\":\"https://forums.swift.org/t/announcing-swift-6-4-2/90337\"},{\"type\":\"url\",\"url\":\"https://swiftpackageindex.com/swiftlang/swift-corelibs-foundation\"},{\"type\":\"url\",\"url\":\"https://forums.swift.org/c/general-announce/24\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/blog/swift-6.4-released/?trk=article-ssr-frontend-pulse_little-text-block\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/blog/\"},{\"type\":\"url\",\"url\":\"https://github.com/swiftlang/swift-evolution/blob/main/README.md?plain=1\"},{\"type\":\"url\",\"url\":\"https://sourceforge.net/projects/swift.mirror/files/\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/install/linux/debian/13/\"},{\"type\":\"url\",\"url\":\"https://obelisk.club/app-rankings/apple-updates\"},{\"type\":\"url\",\"url\":\"https://www.swift.org/install/linux/ubuntu/26_04/\"},{\"type\":\"url\",\"url\":\"https://xitter.cf/swiftlang\"},{\"type\":\"url\",\"url\":\"https://bsky.app/profile/swift.org/post/3mvkwrfshis24\"},{\"type\":\"url\",\"url\":\"https://en.wikipedia.org/wiki/Xcode\"},{\"type\":\"url\",\"url\":\"https://en.wikipedia.org/wiki/Swift_%28programming_language%29\"},{\"type\":\"url\",\"url\":\"https://apple-swift.readthedocs.io/_/downloads/en/latest/pdf/\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/iOSProgramming/comments/1x3leg8/what_happened_to_the_swift_on_android_what_is/\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/1wh28j6/swift_64_released/\"},{\"type\":\"url\",\"url\":\"https://it.wikipedia.org/wiki/Swift_%28linguaggio_di_programmazione%29\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swifties/comments/1vijqr4/taylors_website_has_a_debut_image_up_as_of_8726/\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/1wwc7m8/whats_everyone_working_on_this_month_october_2026/\"},{\"type\":\"url\",\"url\":\"https://www.iso20022.org/milestone/24761/download\"},{\"type\":\"url\",\"url\":\"https://www.iso20022.org/milestone/24824/download\"},{\"type\":\"url\",\"url\":\"https://www.six-group.com/dam/download/banking-services/standardization/sic-eurosic/5-3/sic-platform-releasenotes-2026-en.pdf\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/1x179yl/whats_new_in_swift_september_2026_edition/\"},{\"type\":\"url\",\"url\":\"https://swift.tv/wp-content/uploads/2025/08/29_08_2025_Appendix-4E.pdf\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/1wxj8t7/the_future_of_swift_outside_of_apple/\"},{\"type\":\"url\",\"url\":\"https://www.reddit.com/r/swift/comments/1s2snlx/swift_63_released/\"}],\"type\":\"search\"},\"id\":\"ws_646860155c3e7ad63f2eb1bb2dc3260afb12edad0413a5512b\",\"status\":\"completed\",\"type\":\"web_search_call\"}"]},"requestID":"req_1","responseID":"resp_bd4c1069fa71fdbfa4350794835730c33a7354ca212d628d28","serviceTier":"default","webSearchCount":1}

            usage
            input 8724 cached 4455, output 109 reasoning 70, metadata: {"cacheWriteTokenCount":231,"webSearchCount":1}
            """#
        }
    }

    @Test func `a real web search that OpenAI doesn't keep sends its call back whole`() async throws {
        let exchange = try await ExactExchange(replaying: .webSearchNotStored)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web: what is the tallest building in Lisbon? One sentence."
                }
              ],
              "stream": true,
              "store": false,
              "include": [
                "reasoning.encrypted_content"
              ],
              "tools": [
                {
                  "type": "web_search"
                }
              ],
              "reasoning": {
                "summary": "auto"
              },
              "max_output_tokens": 4000,
              "max_tool_calls": 2
            }

            request 2
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web: what is the tallest building in Lisbon? One sentence."
                },
                {
                  "action": {
                    "queries": [
                      "tallest building in Lisbon Portugal height Torre Vasco da Gama official"
                    ],
                    "query": "tallest building in Lisbon Portugal height Torre Vasco da Gama official",
                    "type": "search"
                  },
                  "id": "ws_b4b53699db835a93b43f48b9481acda86d8426da01aa873cd2",
                  "status": "completed",
                  "type": "web_search_call"
                },
                {
                  "role": "assistant",
                  "content": "Lisbon’s tallest building is the **Vasco da Gama Tower**, at 145 metres tall. ([visitlisboa.com](https://www.visitlisboa.com/en/places/vasco-da-gama-tower?utm_source=openai))",
                  "phase": "final_answer"
                },
                {
                  "role": "user",
                  "content": "How tall is it? One sentence."
                }
              ],
              "stream": true,
              "store": false,
              "include": [
                "reasoning.encrypted_content"
              ],
              "tools": [
                {
                  "type": "web_search"
                }
              ],
              "reasoning": {
                "summary": "auto"
              },
              "max_output_tokens": 4000,
              "max_tool_calls": 2
            }

            transcript
            prompt ["Search the web: what is the tallest building in Lisbon? One sentence."] metadata: {}
            response ["Lisbon’s tallest building is the **Vasco da Gama Tower**, at 145 metres tall. ([visitlisboa.com](https://www.visitlisboa.com/en/places/vasco-da-gama-tower?utm_source=openai))"] metadata: {"cacheWriteTokenCount":19,"citations":[{"endOffset":174,"excerpt":null,"startOffset":78,"title":"Vasco da Gama Tower | Visit Lisboa","url":"https://www.visitlisboa.com/en/places/vasco-da-gama-tower?utm_source=openai"}],"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":174,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"action\":{\"queries\":[\"tallest building in Lisbon Portugal height Torre Vasco da Gama official\"],\"query\":\"tallest building in Lisbon Portugal height Torre Vasco da Gama official\",\"type\":\"search\"},\"id\":\"ws_b4b53699db835a93b43f48b9481acda86d8426da01aa873cd2\",\"status\":\"completed\",\"type\":\"web_search_call\"}"],"unstored":true},"requestID":"req_1","responseID":"resp_e33a63c7af9f263ae4c7308d4eb4e1e51dcdd0923eb854a9f6","serviceTier":"default","webSearchCount":1}
            prompt ["How tall is it? One sentence."] metadata: {}
            reasoning [] metadata: {"model":"gpt-6-luna","reasoningOrigin":"openai-responses"} signature: "[{\"content\":[],\"encrypted_content\":\"gAAAAABq8KKEYVWVCcu5Z39rOLK8BqJd7OI8wRI_uaguHqrxJDd54-lfhBmtuikKoe8IalE8_R_5nJSsRLoAr5gO6SEQIu0BXnedK4djaOhxWvgDMPCnbDaoKauwJmJCWXCfJjgGnHsvIRonAOkntRzT2sC1oR1SLCla0enVxv_1SA7351ZAubYsL71tUA8ZRyu0nObIRhOYWJifLHKxgYMU0AmxE0Jlg8L5qM5QTxVWV5beV4JBwGDvGU46asrkKloBCkiK1diQQVwER0DsyvEXCL6g19PpKSByzaVcND3tVT9HtcbUjYodb2ArdExZbkzfqzsEGsuTTtU-7qgBL7PvinilrG1PMCj9qks2vgnzHuaRTrcVIgxvfMOWP8TWXtLlL2rSqw9IWUufO-XF8QfmyOR2bB9EEJ9iuYAlUEeX_ZKfSqJHg_Tq7_XmeXEEXW6bmKCnrDx1WZI9-lZ68OzRvu7wjDK162FnM0WDEUIc_B2Gkhib-xSw6RrYq88omfe78AqFbL9LTf26u6DS_FU3LWGC50OgUKngPsLPus511tpsn_4KM2QOvSwZrQhBiPxeLgGt_oM9cQQQSxj-R5hPwe70SFwOam1vQxn7_lh5MzvrgbIQU4L10iHDJo8GLcfMHoWkK2fVuhs1pQvk7AXkmd92ukQVZ20cvA10R0AEb2M6iJOm654b-pkjz2EV2c2ItxQPPqtnw7a6z4sTH8qzK7yw27ISqdt4GiNEk3ck_VHyVqOEYf0sYyfcsjFKQTSOcfeUS_-t2GM4IZMlvZZwmFTcPgjC-Xh0R_kHM91MXANTJhTc9tA_NRsB1O5ma9HazR9nbOeLT2cLqPkEsH0SjTsIkGQ2vz_xhWAMUlnlYrNf_z_W2k85SD8v5dBPEGQCfGD1h0tdtoaTDZ5S2FWuN50aIzcx_xPBlDXDqluSZveDlC5C7QrktMYxloy5Bj8MUtNlwUq8DQrxbPqQtim7XSKXpc0HCHWafMmNr-77abrTGK6RwMyY7RUZt_8P7hCqSx46EfTdSa-WBUP5zXOasifDJvNcHPm7PxQMezUGNdpCHv56IcfnTVHzQaQiXXyxYs9o-dtkcBHpfjFBlfP8PyyDeEg5lNh6zEQ9eIzew9NzPnR8ifiwAeg2naTpFAP2UCNdsoY39VDIKkmRzkuXaeCRSohbeHz_Bc1aZFV1iZiNP61LgMRrgm_oz2VOJh6-Ke9vDu6KYUw0DY0RmVPMxgLl9YY13NQZj5PkXNQj8sQPnpwH7OtHaZ1FSxGq7rzA1AGHouMpTHOC2lo-D-4cSYbV9usj8-zdLQkggfez6nEDYurhMbeMVo0PNtUFKJ6QICxDqfVsq0dogQF99r3UdPNLm4TK5aX4v0a4HwigT70gwMWm55VAvxfrwPlXeP-w41cLIfbmwLwCTrQ336xWVDrSPn7ol_o9axTOHI9tSOArYzuvBFENYKVhNpCNOB8Bub-vQaoeVXil0YAwscX8cSGXbP1wXM6uNxUn8OFo2X3qlzSa6fXpxnPCyPPhC9dR-nb-UpVypTDtP96n5R7njS4WJjn799Tak3_BcKlhkO_boUjnGfuA_3TDI6Vf_e9Y8ztCILRdXYBYoWjEkMTDglaJ4LKRd0IpJdblSQL0BJto70wlc88_0YtWavbtpIiVHnXx-EbUeskLYyrVsVs4mj-TiSsRrDKlHlB8MW64hwOfZS9FrmcFFKPXpblLl2mhtUv2bEc0CEfY7sWOa4Yce1JQR9nK6ZmMrWfDyjqE54zeG-Nc3CdfjukkXlFX7f0FnEKBnNyHR7lFspSf5uTXrgUhNmlI7ZOD48JB5dNSlbKQ4sVtyenV8d4dVUt_AzFKv5brv7Xwu34SogGRb3-R3WSJZllzxoBpVfLaJ640C9tAChnCJYJkesRsqvqQoq_FsIbEnQCvvXTwroA4QEGm8J9tJ6bF_pD-9q7C9WlGHBRXEDyKeMzSdTP9Z7lZxFLgfCBns42H\",\"id\":\"rs_634b68a79cff993cd60d633b4f2bd261c0c2726ab76578852a\",\"summary\":[],\"type\":\"reasoning\"},{\"type\":\"web_search_call\"},{\"type\":\"message\"}]"
            response ["It’s approximately **145 metres (476 feet)** tall. ([vascodagamatower.com](https://www.vascodagamatower.com/en/faqs/?utm_source=openai))"] metadata: {"cacheWriteTokenCount":110,"citations":[{"endOffset":136,"excerpt":null,"startOffset":51,"title":"Faqs - Vasco da Gama Tower","url":"https://www.vascodagamatower.com/en/faqs/?utm_source=openai"}],"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":136,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"action\":{\"queries\":[\"Vasco da Gama Tower Lisbon height 145 metres\"],\"query\":\"Vasco da Gama Tower Lisbon height 145 metres\",\"type\":\"search\"},\"id\":\"ws_83c3db96b0ffe27fdb1387f03a875d44333dbaee757f7c5d34\",\"status\":\"completed\",\"type\":\"web_search_call\"}"],"unstored":true},"requestID":"req_1","responseID":"resp_a9e730bf4aabdea72cb13110ede0d391681c84a5531c7e432e","serviceTier":"default","webSearchCount":1}

            usage
            input 10871 cached 4454, output 93 reasoning 62, metadata: {"cacheWriteTokenCount":110,"webSearchCount":1}
            """#
        }
    }

    @Test func `a real web search by a model that doesn't reason sends its call back before the message`() async throws {
        let exchange = try await ExactExchange(replaying: .webSearchPlain)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-4o-mini",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web: who designed the Eiffel Tower? One sentence."
                }
              ],
              "stream": true,
              "tools": [
                {
                  "type": "web_search"
                }
              ],
              "max_output_tokens": 300,
              "max_tool_calls": 1
            }

            request 2
            {
              "model": "gpt-4o-mini",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web: who designed the Eiffel Tower? One sentence."
                },
                {
                  "action": {
                    "queries": [
                      "who designed the Eiffel Tower?"
                    ],
                    "query": "who designed the Eiffel Tower?",
                    "type": "search"
                  },
                  "id": "ws_634b68a79cff993cd60d633b4f2bd261c0c2726ab76578852a",
                  "status": "completed",
                  "type": "web_search_call"
                },
                {
                  "role": "assistant",
                  "content": "The Eiffel Tower was designed by engineers Maurice Koechlin and Émile Nouguier, with architectural enhancements by Stephen Sauvestre, under the leadership of Gustave Eiffel. ([en.wikipedia.org](https://en.wikipedia.org/wiki/Eiffel_Tower?utm_source=openai)) "
                },
                {
                  "role": "user",
                  "content": "In which year was it finished? One sentence."
                }
              ],
              "stream": true,
              "tools": [
                {
                  "type": "web_search"
                }
              ],
              "max_output_tokens": 300,
              "max_tool_calls": 1
            }

            transcript
            prompt ["Search the web: who designed the Eiffel Tower? One sentence."] metadata: {}
            response ["The Eiffel Tower was designed by engineers Maurice Koechlin and Émile Nouguier, with architectural enhancements by Stephen Sauvestre, under the leadership of Gustave Eiffel. ([en.wikipedia.org](https://en.wikipedia.org/wiki/Eiffel_Tower?utm_source=openai)) "] metadata: {"cacheWriteTokenCount":0,"citations":[{"endOffset":256,"excerpt":null,"startOffset":174,"title":"Eiffel Tower","url":"https://en.wikipedia.org/wiki/Eiffel_Tower?utm_source=openai"}],"finishReason":"stop","model":"gpt-4o-mini-2024-07-18","openAI.serverTools":{"calls":["{\"action\":{\"queries\":[\"who designed the Eiffel Tower?\"],\"query\":\"who designed the Eiffel Tower?\",\"type\":\"search\"},\"id\":\"ws_634b68a79cff993cd60d633b4f2bd261c0c2726ab76578852a\",\"status\":\"completed\",\"type\":\"web_search_call\"}"]},"requestID":"req_1","responseID":"resp_a9e730bf4aabdea72cb13110ede0d391681c84a5531c7e432e","serviceTier":"default","webSearchCount":1}
            prompt ["In which year was it finished? One sentence."] metadata: {}
            response ["The Eiffel Tower was completed in 1889."] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-4o-mini-2024-07-18","requestID":"req_1","responseID":"resp_e3089e59d45249fa65328d971a75af87e8442a443c28cc5b72","serviceTier":"default"}

            usage
            input 713 cached 0, output 12 reasoning 0, metadata: {"cacheWriteTokenCount":0}
            """#
        }
    }

    @Test func `a real web search beside the session's tool calls goes back in its place`() async throws {
        let exchange = try await ExactExchange(replaying: .webSearchWithSessionTool)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web for the calories in a boiled egg, and look up rice with the tool. Give both in one sentence."
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
                },
                {
                  "type": "web_search"
                }
              ],
              "reasoning": {
                "effort": "low"
              },
              "max_output_tokens": 3000,
              "max_tool_calls": 1
            }

            request 2
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web for the calories in a boiled egg, and look up rice with the tool. Give both in one sentence."
                },
                {
                  "action": {
                    "queries": [
                      "calories in one large hard boiled egg USDA"
                    ],
                    "query": "calories in one large hard boiled egg USDA",
                    "type": "search"
                  },
                  "id": "ws_27fc3dc5a270b0205b33b577450d1b3ebbdd8e02350b88fbbf",
                  "status": "completed",
                  "type": "web_search_call"
                },
                {
                  "type": "function_call",
                  "call_id": "call_G1JZYOt6bG2AskUydQ99n2Tq",
                  "name": "lookUpFood",
                  "arguments": "{\"food\":\"rice\"}"
                },
                {
                  "type": "function_call_output",
                  "call_id": "call_G1JZYOt6bG2AskUydQ99n2Tq",
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
                },
                {
                  "type": "web_search"
                }
              ],
              "reasoning": {
                "effort": "low"
              },
              "max_output_tokens": 3000,
              "max_tool_calls": 1
            }

            request 3
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the web for the calories in a boiled egg, and look up rice with the tool. Give both in one sentence."
                },
                {
                  "action": {
                    "queries": [
                      "calories in one large hard boiled egg USDA"
                    ],
                    "query": "calories in one large hard boiled egg USDA",
                    "type": "search"
                  },
                  "id": "ws_27fc3dc5a270b0205b33b577450d1b3ebbdd8e02350b88fbbf",
                  "status": "completed",
                  "type": "web_search_call"
                },
                {
                  "type": "function_call",
                  "call_id": "call_G1JZYOt6bG2AskUydQ99n2Tq",
                  "name": "lookUpFood",
                  "arguments": "{\"food\":\"rice\"}"
                },
                {
                  "type": "function_call_output",
                  "call_id": "call_G1JZYOt6bG2AskUydQ99n2Tq",
                  "output": "rice: 100 kcal"
                },
                {
                  "type": "function_call",
                  "call_id": "call_DGVzLWY4h3vnqG7Ktsam7PES",
                  "name": "lookUpFood",
                  "arguments": "{\"food\":\"rice\"}"
                },
                {
                  "type": "function_call",
                  "call_id": "call_iN3hFnz9OoPR8cGc4mHmmAad",
                  "name": "lookUpFood",
                  "arguments": "{\"food\":\"boiled egg\"}"
                },
                {
                  "type": "function_call_output",
                  "call_id": "call_DGVzLWY4h3vnqG7Ktsam7PES",
                  "output": "rice: 100 kcal"
                },
                {
                  "type": "function_call_output",
                  "call_id": "call_iN3hFnz9OoPR8cGc4mHmmAad",
                  "output": "boiled egg: 100 kcal"
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
                },
                {
                  "type": "web_search"
                }
              ],
              "reasoning": {
                "effort": "low"
              },
              "max_output_tokens": 3000,
              "max_tool_calls": 1
            }

            transcript
            instructions [] tools: ["lookUpFood"]
            prompt ["Search the web for the calories in a boiled egg, and look up rice with the tool. Give both in one sentence."] metadata: {}
            toolCalls ["call_G1JZYOt6bG2AskUydQ99n2Tq lookUpFood {\"food\":\"rice\"} metadata: {\"cacheWriteTokenCount\":4505,\"finishReason\":\"tool_calls\",\"model\":\"gpt-6-luna\",\"openAI.serverTools\":{\"calls\":[\"{\\\"action\\\":{\\\"queries\\\":[\\\"calories in one large hard boiled egg USDA\\\"],\\\"query\\\":\\\"calories in one large hard boiled egg USDA\\\",\\\"type\\\":\\\"search\\\"},\\\"id\\\":\\\"ws_27fc3dc5a270b0205b33b577450d1b3ebbdd8e02350b88fbbf\\\",\\\"status\\\":\\\"completed\\\",\\\"type\\\":\\\"web_search_call\\\"}\"]},\"requestID\":\"req_1\",\"responseID\":\"resp_816495b11ead0ae100dff36813c272a2a7c272ae4a18a9a18a\",\"serviceTier\":\"default\",\"webSearchCount\":1}"]
            toolOutput call_G1JZYOt6bG2AskUydQ99n2Tq lookUpFood ["rice: 100 kcal"]
            toolCalls ["call_DGVzLWY4h3vnqG7Ktsam7PES lookUpFood {\"food\":\"rice\"} metadata: {\"cacheWriteTokenCount\":70,\"finishReason\":\"tool_calls\",\"model\":\"gpt-6-luna\",\"requestID\":\"req_1\",\"responseID\":\"resp_251b21b487178075a11227576790ac9255f2620e07595cc650\",\"serviceTier\":\"default\"}", "call_iN3hFnz9OoPR8cGc4mHmmAad lookUpFood {\"food\":\"boiled egg\"} metadata: {}"]
            toolOutput call_DGVzLWY4h3vnqG7Ktsam7PES lookUpFood ["rice: 100 kcal"]
            toolOutput call_iN3hFnz9OoPR8cGc4mHmmAad lookUpFood ["boiled egg: 100 kcal"]
            response ["A large boiled egg has about **78 calories**, and the food lookup lists rice at **100 calories** (serving size unspecified). ([fdc.nal.usda.gov](https://fdc.nal.usda.gov/food-search/?component=1100&utm_source=openai))"] metadata: {"cacheWriteTokenCount":86,"citations":[{"endOffset":217,"excerpt":null,"startOffset":125,"title":"Food Search | USDA FoodData Central","url":"https://fdc.nal.usda.gov/food-search/?component=1100&utm_source=openai"}],"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":217,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"action\":{\"queries\":[\"site:fdc.nal.usda.gov hard boiled egg calories 1 large\"],\"query\":\"site:fdc.nal.usda.gov hard boiled egg calories 1 large\",\"type\":\"search\"},\"id\":\"ws_28a7e066747c5d5d6d0667b7016a4e4df933162879f553256b\",\"status\":\"completed\",\"type\":\"web_search_call\"}"]},"requestID":"req_1","responseID":"resp_4f2d12126f455cf9e8a29d33ed6227cb98493b955ec6a1ea90","serviceTier":"default","webSearchCount":1}

            usage
            input 8919 cached 4575, output 85 reasoning 39, metadata: {"cacheWriteTokenCount":86,"webSearchCount":1}
            """#
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a real image becomes a data entry with its call, which goes back by its id for the next turn's edit`() async throws {
        let exchange = try await ExactExchange(replaying: .imageGeneration)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Draw a small red circle on a white background."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "tools": [
                {
                  "type": "image_generation",
                  "quality": "low",
                  "size": "1024x1024"
                }
              ],
              "max_output_tokens": 2000
            }

            request 2
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Draw a small red circle on a white background."
                },
                {
                  "action": "generate",
                  "background": "opaque",
                  "id": "ig_10b349fa4eb3ec0767faeb2628eae9067277d0d2c007ba6ae6",
                  "output_format": "png",
                  "quality": "low",
                  "result": null,
                  "revised_prompt": "A clean minimalist graphic: one small solid red circle centered on a plain pure white background. No shadow, no outline, no texture, no text. Square canvas.",
                  "size": "1024x1024",
                  "status": "completed",
                  "type": "image_generation_call"
                },
                {
                  "role": "user",
                  "content": "Now make the circle blue."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "tools": [
                {
                  "type": "image_generation",
                  "quality": "low",
                  "size": "1024x1024"
                }
              ],
              "max_output_tokens": 2000
            }

            transcript
            prompt ["Draw a small red circle on a white background."] metadata: {}
            data public.png iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAD0lEQVR4nGNgiDoBQhAKABymBImcIySdAAAAAElFTkSuQmCC metadata: {"openAI.serverTools":{"calls":["{\"action\":\"generate\",\"background\":\"opaque\",\"id\":\"ig_10b349fa4eb3ec0767faeb2628eae9067277d0d2c007ba6ae6\",\"output_format\":\"png\",\"quality\":\"low\",\"result\":null,\"revised_prompt\":\"A clean minimalist graphic: one small solid red circle centered on a plain pure white background. No shadow, no outline, no texture, no text. Square canvas.\",\"size\":\"1024x1024\",\"status\":\"completed\",\"type\":\"image_generation_call\"}"]}}
            response [""] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":0,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"action\":\"generate\",\"background\":\"opaque\",\"id\":\"ig_10b349fa4eb3ec0767faeb2628eae9067277d0d2c007ba6ae6\",\"output_format\":\"png\",\"quality\":\"low\",\"result\":null,\"revised_prompt\":\"A clean minimalist graphic: one small solid red circle centered on a plain pure white background. No shadow, no outline, no texture, no text. Square canvas.\",\"size\":\"1024x1024\",\"status\":\"completed\",\"type\":\"image_generation_call\"}"]},"requestID":"req_1","responseID":"resp_ae79c0d2d30b9ce28bd0da6dcf50cf3eef2c22b18f408c38c6","serviceTier":"default"}
            prompt ["Now make the circle blue."] metadata: {}
            data public.png iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAD0lEQVR4nGNgiDoBQhAKABymBImcIySdAAAAAElFTkSuQmCC metadata: {"openAI.serverTools":{"calls":["{\"action\":\"edit\",\"background\":\"opaque\",\"id\":\"ig_c0c99597050c57a3b30da8fde91091f529adfe31b1bf7b8e94\",\"output_format\":\"png\",\"quality\":\"low\",\"result\":null,\"revised_prompt\":\"Edit the previous minimalist graphic: keep the exact same plain pure white square background and the same small solid circle in the same centered position and size, but change its fill color from red to a vivid blue. No shadow, no outline, no texture, no text.\",\"size\":\"1024x1024\",\"status\":\"completed\",\"type\":\"image_generation_call\"}"]}}
            reasoning [] metadata: {"model":"gpt-6-luna","reasoningOrigin":"openai-responses"} signature: "[{\"type\":\"image_generation_call\"},{\"content\":[],\"encrypted_content\":\"gAAAAABq8FuaXqlESrvDC25uJ0D1i8c7ifXHV3fO_wwiYJndTJDS8K9DLcOYUBAP5muvM-LLpS7b_3oX8MskyUILTNSc_1Nh3dHN3m1dKeokNJuoqBOEAP2hVH-3J0CyaW9muUp515P1OF0NVHF2jyBDFFECEY1OGdEHcrLBbkVF6tTVXmOeWMejPdq32G4Ar-1a9IBzxw8zyV9C9AtIxk5nVR93BJdscXgeZwf5eBvhyTyZVM7UvhB-d7vPMJD-BHhaiCnFzWlKlx2KASrMB-GSdGUUFmltcYYM_-ETFSGXRiQAbqn87WLSmP2rQZ8Acngw6RuBJXMC8bdODAorCYtiCaGT8nhMIx22s8Yd7pbKYQyfQSe7b1Uf7uOz8c9BUsvHsqiGncslMzN48jWIGoZ5G_nig9yubj7IUCP1n-plKfCvVaoM6fOlnuf6JC-jGbmOhgXPXxNtfkstQR-9LiVp65IZdSctjYDcmw5crVinHIYLAPswBCvWpiihEdskhY0ksxnPyNZGER9yxNrXpEKvXwnozRQFK44dwPTV9b9vxnNXhC55WwAU0REyz47QY94BIiTOTxt50MLNVRF9UYpgiPqzA8BHFP2LMY28TIyRo6n3DIegq2qd3rc3ZW3BeQQECujfFd5Q78oN9D8upHpmY6AGQ4OR_0XhW-Bvwf7M-4B2auTZkCYxsVGAPqzAGv1mfBOpOMI10g7OaEnNRKZnwwDSvetrLgc5b8fQ8hBtwRCmDKc_GfPxOHEJFUexEnQaVLrBQyfh09cSjHcnn39NMyEluNBhXEjpQsY9q6uu6-emJVfowHHAn692LCGDnUnOQ_NVme9r2IiaJz8Ytv2hMzFiWO-0aSDAq4DdqMF0nHWK4RBbipjKZPJgJiyys9Q64B_Ler5wr4D_9ude-HHNVtjHu9tpt_SgiEjAAiL3hOKe2079fol3cmJyQtA4dgD2_4MCujYnCRG8ULd948EzPEkt_UiQ8Qsqx_njTxyBzo_kPedlAlfTxvoEEDdhPEEqRQ4iI_igxGp9aEmoZiMnCkGvH1NSFIFPJ53CDLsOV9nVWspgS-hmYcpI8O-qgUVe5p1tN4paab_FZaA_-Ivbf5sDOUBUpTfzhuYiHht87Lx_Ib3IEorIT9A2be95PV-MGKZnzN242RriKJIwDjstGAPGrTs1BX5zIfrm-jCd8TjUYyifKb5yV6_84YiVml78b_bbMaII4xgbYp8Tdt9Hb8ms2MxZ1tIDQlXrYu0AfB_xOVj4dn_P7KrgW3Vduqb_e5ezNXWwzyv40TbqBhiuChAllgNUv_Bxlbp3w4N8hnfJphnfCiNbBGx5PoD242NvqIEnx29FsPfAz8ZMbJegAiZOQv4ehCxqB3k0AXuAiGIn5yw7eyRf6XPSdbY8hesHw0p3tDEDs6BPA9w8mwk-2Q4psOIsWJzx0gQE4XRJ7DH9i2lIiA470Aj49XbIJhLQ5MXysH224uuh-zfWv1MqkWX1D0kb7AKgdSrHc1eaWpg-F29mTOuXZy1CsEo939N2CDg-W7ZHppvtMcGjFoR-oVone7l53nztGjDB_E06bx2eY9KHuUci5bA_qSsUwZot5M_LSjr1AzjBhu6kJNrS1-TvkGrZffd6ki61u9rFu-95CWWLeHN5rjmuwd3QxCJTpppXdgsoelshyscxHwmUkDJW04GZAdOfxzjwVt1F8upS2aMIIfSCrRSiMYWCsiDbk_mMYx4IMLc5xGWE34b5Ahg98ShEB-mLVYrrU2sTixO9es1dRcup4QdZddShL_nvIXp7tI37BXIo748SgVIJUQiqPLmoOmyjjXu63irKHUXp2udyXQLZTqpgCfcFJuqRdSt_bTJV\",\"id\":\"rs_bd4c1069fa71fdbfa4350794835730c33a7354ca212d628d28\",\"summary\":[],\"type\":\"reasoning\"}]"
            response [""] metadata: {"cacheWriteTokenCount":0,"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":0,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"action\":\"edit\",\"background\":\"opaque\",\"id\":\"ig_c0c99597050c57a3b30da8fde91091f529adfe31b1bf7b8e94\",\"output_format\":\"png\",\"quality\":\"low\",\"result\":null,\"revised_prompt\":\"Edit the previous minimalist graphic: keep the exact same plain pure white square background and the same small solid circle in the same centered position and size, but change its fill color from red to a vivid blue. No shadow, no outline, no texture, no text.\",\"size\":\"1024x1024\",\"status\":\"completed\",\"type\":\"image_generation_call\"}"]},"requestID":"req_1","responseID":"resp_eecb54d15323721f327d2c04d38c1d7feac25542b4213db93b","serviceTier":"default"}

            usage
            input 1736 cached 0, output 94 reasoning 20, metadata: {"cacheWriteTokenCount":0}
            """#
        }
    }
    #endif

    @Test func `a real file search's call and cited file read as OpenAI sent them, and the call goes back`() async throws {
        let exchange = try await ExactExchange(replaying: .fileSearch)

        assertInlineSnapshot(of: exchange, as: .exchange) {
            #"""
            request 1
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the files: what does Harbor Kitchen serve on Tuesday? One sentence."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "tools": [
                {
                  "type": "file_search",
                  "vector_store_ids": [
                    "vs_recordedvectorstore0000000000"
                  ],
                  "max_num_results": 3
                }
              ],
              "reasoning": {
                "effort": "low"
              },
              "max_output_tokens": 2000
            }

            request 2
            {
              "model": "gpt-6-luna",
              "input": [
                {
                  "role": "user",
                  "content": "Search the files: what does Harbor Kitchen serve on Tuesday? One sentence."
                },
                {
                  "id": "fs_86db36ab33d0065bdb91f1a8c999af47188b99cf8856133a33",
                  "queries": [
                    "What does Harbor Kitchen serve on Tuesday?"
                  ],
                  "results": null,
                  "status": "completed",
                  "type": "file_search_call"
                },
                {
                  "role": "assistant",
                  "content": "Harbor Kitchen serves grilled sardines with lemon potatoes on Tuesday. ",
                  "phase": "final_answer"
                },
                {
                  "role": "user",
                  "content": "And when does the kitchen close? One sentence."
                }
              ],
              "stream": true,
              "include": [
                "reasoning.encrypted_content"
              ],
              "tools": [
                {
                  "type": "file_search",
                  "vector_store_ids": [
                    "vs_recordedvectorstore0000000000"
                  ],
                  "max_num_results": 3
                }
              ],
              "reasoning": {
                "effort": "low"
              },
              "max_output_tokens": 2000
            }

            transcript
            prompt ["Search the files: what does Harbor Kitchen serve on Tuesday? One sentence."] metadata: {}
            response ["Harbor Kitchen serves grilled sardines with lemon potatoes on Tuesday. "] metadata: {"cacheWriteTokenCount":1475,"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":71,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"id\":\"fs_86db36ab33d0065bdb91f1a8c999af47188b99cf8856133a33\",\"queries\":[\"What does Harbor Kitchen serve on Tuesday?\"],\"results\":null,\"status\":\"completed\",\"type\":\"file_search_call\"}"],"fileCitations":[{"fileID":"file-Iwjw69k0XQgTmttP4AwqT8","filename":"menu.txt","offset":71}]},"requestID":"req_1","responseID":"resp_646860155c3e7ad63f2eb1bb2dc3260afb12edad0413a5512b","serviceTier":"default"}
            prompt ["And when does the kitchen close? One sentence."] metadata: {}
            response ["Harbor Kitchen closes at nine every evening. "] metadata: {"cacheWriteTokenCount":182,"finishReason":"stop","model":"gpt-6-luna","openAI.phases":[{"length":45,"phase":"final_answer"}],"openAI.serverTools":{"calls":["{\"id\":\"fs_58c3a69b96b01f0f120ffb843809cbe04eaf6aba9e730bf4aa\",\"queries\":[\"When does Harbor Kitchen close?\"],\"results\":null,\"status\":\"completed\",\"type\":\"file_search_call\"}"],"fileCitations":[{"fileID":"file-Iwjw69k0XQgTmttP4AwqT8","filename":"menu.txt","offset":45}]},"requestID":"req_1","responseID":"resp_35a93b43f48b9481acda86d8426da01aa873cd29afce4565ed","serviceTier":"default"}

            usage
            input 2237 cached 1475, output 49 reasoning 21, metadata: {"cacheWriteTokenCount":182}
            """#
        }
    }
}
