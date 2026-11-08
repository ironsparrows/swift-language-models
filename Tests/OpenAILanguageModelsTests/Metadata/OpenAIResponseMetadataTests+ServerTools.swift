import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

extension OpenAIResponseMetadataTests {
    @Test func `each kind of server tool call reads its own facts, and each source once`() throws {
        let calls: [JSONValue] = [
            [
                "type": "web_search_call", "id": "ws_1", "status": "completed",
                "action": [
                    "type": "search", "queries": ["swift release"],
                    "sources": [["type": "url", "url": "https://swift.org/blog"], ["type": "url", "url": "https://swift.org"]],
                ],
            ],
            [
                "type": "web_search_call", "id": "ws_2", "status": "completed",
                "action": ["type": "search", "query": "swift 6", "sources": [["type": "url", "url": "https://swift.org"]]],
            ],
            [
                "type": "web_search_call", "id": "ws_3", "status": "completed",
                "action": ["type": "open_page", "url": "https://swift.org/blog"],
            ],
            [
                "type": "web_search_call", "id": "ws_4", "status": "failed",
                "action": ["type": "find_in_page", "url": "https://swift.org/blog", "pattern": "6.4"],
            ],
            ["type": "file_search_call", "id": "fs_1", "status": "completed", "queries": ["menu"], "results": JSONValue.null],
            ["type": "image_generation_call", "id": "ig_1", "status": "completed", "result": JSONValue.null, "revised_prompt": "A cat."],
        ]
        let response = Transcript.Response(
            metadata: ["openAI.serverTools": GeneratedContent(properties: ["calls": calls.map(\.text)])], segments: [])

        let metadata = response.openAI

        let readings = metadata.serverToolCalls.map { call in
            [
                call.id, call.kind.rawValue, call.status?.rawValue ?? "nil", call.action?.rawValue ?? "nil", "\(call.queries)",
                call.url?.absoluteString ?? "nil", call.pattern ?? "nil", call.revisedPrompt ?? "nil",
            ]
            .joined(separator: " ")
        }
        #expect(
            readings == [
                #"ws_1 web_search_call completed search ["swift release"] nil nil nil"#,
                #"ws_2 web_search_call completed search ["swift 6"] nil nil nil"#,
                "ws_3 web_search_call completed open_page [] https://swift.org/blog nil nil",
                "ws_4 web_search_call failed find_in_page [] https://swift.org/blog 6.4 nil",
                #"fs_1 file_search_call completed nil ["menu"] nil nil nil"#,
                "ig_1 image_generation_call completed nil [] nil nil A cat.",
            ])
        #expect(metadata.sources.map(\.absoluteString) == ["https://swift.org/blog", "https://swift.org"])
    }
}
