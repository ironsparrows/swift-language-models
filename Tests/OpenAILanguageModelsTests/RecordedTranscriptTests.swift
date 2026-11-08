import CustomDump
import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenAILanguageModels

/// The transcripts of the recorded exchanges, as apps have saved them, each beside the bytes its next turn sends. They
/// hold what OpenAI really reported, and saved transcripts outlive the code that wrote them, so these files never
/// change.
@Suite("Recorded transcripts", .timeLimit(.minutes(1)))
struct RecordedTranscriptTests {
    static let scenarios: [RecordedScenario] = [
        .text, .reasoning, .tools, .guided, .plain, .options, .cached, .webSearch, .webSearchNotStored, .webSearchPlain,
        .webSearchWithSessionTool, .fileSearch,
    ]

    /// The transcripts of every Xcode and system, then the one that needs the newer ones to read its attachments.
    static let allScenarios: [RecordedScenario] = {
        #if canImport(FoundationModels, _version: 2.1.14)
        if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) {
            return scenarios + [.attachments, .imageGeneration]
        }
        #endif
        return scenarios
    }()

    @Test(arguments: allScenarios)
    func `a recorded transcript sends the same bytes on its next turn, its JPEGs aside`(scenario: RecordedScenario) async throws {
        let saved = try Bundle.module.fixture("Transcripts/recorded-\(scenario.name).next-turn.json")

        let sent = try await Self.nextTurn(after: Self.transcript(scenario), of: scenario)

        expectNoDifference(
            ExactExchange.withoutJPEGs(String(decoding: sent, as: UTF8.self)),
            ExactExchange.withoutJPEGs(String(decoding: saved, as: UTF8.self))
        )
    }

    @Test func `a recorded transcript reads the same through the typed readers`() throws {
        let readings = try Self.scenarios.map { scenario in
            let facts = try Self.transcript(scenario).compactMap { entry -> String? in
                switch entry {
                case .response(let response): "response \(SavedTranscriptTests.facts(response.openAI))"
                case .toolCalls(let calls): "toolCalls \(SavedTranscriptTests.facts(calls.openAI))"
                default: nil
                }
            }
            return ([scenario.name] + facts).joined(separator: "\n")
        }

        assertInlineSnapshot(of: readings.joined(separator: "\n\n"), as: .lines) {
            #"""
            text
            response model: gpt-5-nano-2025-08-07, responseID: resp_3cba0b7f18ac52680254e110b223921e34b858ee1d3be7f9bd, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0

            reasoning
            response model: gpt-5-nano-2025-08-07, responseID: resp_7a90aec18ffbe3cfe9235fbf72359ce57f052b047abd003de2, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0

            tools
            toolCalls model: gpt-5-nano-2025-08-07, responseID: resp_eef168ee174906a270b14c6cf7d778e0867bae5e7d6962b1b2, requestID: req_1, finishReason: tool_calls, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0
            response model: gpt-5-nano-2025-08-07, responseID: resp_33556ad7b4c93c74edaa61f8f6d2f1c22bd0d0a6d9c6557c3d, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0

            guided
            response model: gpt-5-nano-2025-08-07, responseID: resp_3f970c12be062f690f8bbb90ce6389fbfb0ecb3b7b21b9ecef, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0

            plain
            response model: gpt-4o-mini-2024-07-18, responseID: resp_bed7e9c7c4ccb46d8bc8fe3ab44e0c906dc39821b53ba4e5ba, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0

            options
            response model: gpt-5-nano-2025-08-07, responseID: resp_3cba0b7f18ac52680254e110b223921e34b858ee1d3be7f9bd, requestID: req_1, finishReason: stop, serviceTier: flex, citations: [], messages: [], cacheWriteTokenCount: 0

            cached
            response model: gpt-5-nano-2025-08-07, responseID: resp_8bf3a4b1a9ba9397462fb944392097e2bca5418e337f5775be, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0
            response model: gpt-5-nano-2025-08-07, responseID: resp_7a90aec18ffbe3cfe9235fbf72359ce57f052b047abd003de2, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0

            web-search
            response model: gpt-6-luna, responseID: resp_ae79c0d2d30b9ce28bd0da6dcf50cf3eef2c22b18f408c38c6, requestID: req_1, finishReason: stop, serviceTier: default, citations: ["https://forums.swift.org/t/announcing-swift-6-4-2/90337?utm_source=openai Announcing Swift 6.4.2 - Announcements - Swift Forums"], messages: ["final_answer 174 nil"], cacheWriteTokenCount: 4455, sources: 40, first https://www.swift.org/blog/, serverToolCalls: ["web_search_call ws_10b349fa4eb3ec0767faeb2628eae9067277d0d2c007ba6ae6 completed search [\"latest stable release Swift programming language official release\"] nil nil nil", "web_search_call ws_eecb54d15323721f327d2c04d38c1d7feac25542b4213db93b completed search [\"site:swift.org/blog \\\"Swift 6.4.2\\\"\", \"site:github.com/swiftlang/swift/releases Swift 6.4.2 release\", \"site:swift.org \\\"6.4.2\\\" Swift release\"] nil nil nil"], webSearchCount: 2
            response model: gpt-6-luna, responseID: resp_bd4c1069fa71fdbfa4350794835730c33a7354ca212d628d28, requestID: req_1, finishReason: stop, serviceTier: default, citations: ["https://forums.swift.org/t/announcing-swift-6-4-2/90337?utm_source=openai Announcing Swift 6.4.2 - Announcements - Swift Forums"], messages: ["final_answer 145 nil"], cacheWriteTokenCount: 231, sources: 27, first https://forums.swift.org/t/announcing-swift-6-4-2/90337, serverToolCalls: ["web_search_call ws_646860155c3e7ad63f2eb1bb2dc3260afb12edad0413a5512b completed search [\"Swift 6.4.2 release date October 30 2026 official\"] nil nil nil"], webSearchCount: 1

            web-search-not-stored
            response model: gpt-6-luna, responseID: resp_e33a63c7af9f263ae4c7308d4eb4e1e51dcdd0923eb854a9f6, requestID: req_1, finishReason: stop, serviceTier: default, citations: ["https://www.visitlisboa.com/en/places/vasco-da-gama-tower?utm_source=openai Vasco da Gama Tower | Visit Lisboa"], messages: ["final_answer 174 nil"], cacheWriteTokenCount: 19, serverToolCalls: ["web_search_call ws_b4b53699db835a93b43f48b9481acda86d8426da01aa873cd2 completed search [\"tallest building in Lisbon Portugal height Torre Vasco da Gama official\"] nil nil nil"], webSearchCount: 1
            response model: gpt-6-luna, responseID: resp_a9e730bf4aabdea72cb13110ede0d391681c84a5531c7e432e, requestID: req_1, finishReason: stop, serviceTier: default, citations: ["https://www.vascodagamatower.com/en/faqs/?utm_source=openai Faqs - Vasco da Gama Tower"], messages: ["final_answer 136 nil"], cacheWriteTokenCount: 110, serverToolCalls: ["web_search_call ws_83c3db96b0ffe27fdb1387f03a875d44333dbaee757f7c5d34 completed search [\"Vasco da Gama Tower Lisbon height 145 metres\"] nil nil nil"], webSearchCount: 1

            web-search-plain
            response model: gpt-4o-mini-2024-07-18, responseID: resp_a9e730bf4aabdea72cb13110ede0d391681c84a5531c7e432e, requestID: req_1, finishReason: stop, serviceTier: default, citations: ["https://en.wikipedia.org/wiki/Eiffel_Tower?utm_source=openai Eiffel Tower"], messages: [], cacheWriteTokenCount: 0, serverToolCalls: ["web_search_call ws_634b68a79cff993cd60d633b4f2bd261c0c2726ab76578852a completed search [\"who designed the Eiffel Tower?\"] nil nil nil"], webSearchCount: 1
            response model: gpt-4o-mini-2024-07-18, responseID: resp_e3089e59d45249fa65328d971a75af87e8442a443c28cc5b72, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 0

            web-search-with-session-tool
            toolCalls model: gpt-6-luna, responseID: resp_816495b11ead0ae100dff36813c272a2a7c272ae4a18a9a18a, requestID: req_1, finishReason: tool_calls, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 4505, serverToolCalls: ["web_search_call ws_27fc3dc5a270b0205b33b577450d1b3ebbdd8e02350b88fbbf completed search [\"calories in one large hard boiled egg USDA\"] nil nil nil"], webSearchCount: 1
            toolCalls model: gpt-6-luna, responseID: resp_251b21b487178075a11227576790ac9255f2620e07595cc650, requestID: req_1, finishReason: tool_calls, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: 70
            response model: gpt-6-luna, responseID: resp_4f2d12126f455cf9e8a29d33ed6227cb98493b955ec6a1ea90, requestID: req_1, finishReason: stop, serviceTier: default, citations: ["https://fdc.nal.usda.gov/food-search/?component=1100&utm_source=openai Food Search | USDA FoodData Central"], messages: ["final_answer 217 nil"], cacheWriteTokenCount: 86, serverToolCalls: ["web_search_call ws_28a7e066747c5d5d6d0667b7016a4e4df933162879f553256b completed search [\"site:fdc.nal.usda.gov hard boiled egg calories 1 large\"] nil nil nil"], webSearchCount: 1

            file-search
            response model: gpt-6-luna, responseID: resp_646860155c3e7ad63f2eb1bb2dc3260afb12edad0413a5512b, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: ["final_answer 71 nil"], cacheWriteTokenCount: 1475, serverToolCalls: ["file_search_call fs_86db36ab33d0065bdb91f1a8c999af47188b99cf8856133a33 completed nil [\"What does Harbor Kitchen serve on Tuesday?\"] nil nil nil"], fileCitations: ["file-Iwjw69k0XQgTmttP4AwqT8 menu.txt 71"]
            response model: gpt-6-luna, responseID: resp_35a93b43f48b9481acda86d8426da01aa873cd29afce4565ed, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: ["final_answer 45 nil"], cacheWriteTokenCount: 182, serverToolCalls: ["file_search_call fs_58c3a69b96b01f0f120ffb843809cbe04eaf6aba9e730bf4aa completed nil [\"When does Harbor Kitchen close?\"] nil nil nil"], fileCitations: ["file-Iwjw69k0XQgTmttP4AwqT8 menu.txt 45"]
            """#
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a recorded image's data entry reads its call and revised prompt`() throws {
        let images = try Self.transcript(.imageGeneration).compactMap { entry -> String? in
            guard case .data(let data) = entry else { return nil }
            return "\(data.contentType.identifier) \(data.openAI.callID ?? "nil") \(data.openAI.revisedPrompt ?? "nil")"
        }

        assertInlineSnapshot(of: images.joined(separator: "\n"), as: .lines) {
            """
            public.png ig_10b349fa4eb3ec0767faeb2628eae9067277d0d2c007ba6ae6 A clean minimalist graphic: one small solid red circle centered on a plain pure white background. No shadow, no outline, no texture, no text. Square canvas.
            public.png ig_c0c99597050c57a3b30da8fde91091f529adfe31b1bf7b8e94 Edit the previous minimalist graphic: keep the exact same plain pure white square background and the same small solid circle in the same centered position and size, but change its fill color from red to a vivid blue. No shadow, no outline, no texture, no text.
            """
        }
    }
    #endif

    private static func transcript(_ scenario: RecordedScenario) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: Bundle.module.fixture("Transcripts/recorded-\(scenario.name).json"))
    }

    /// The bytes a session sends for one more prompt after a transcript, on the scenario's model.
    static func nextTurn(after transcript: Transcript, of scenario: RecordedScenario) async throws -> Data {
        let stub = HTTPStub(responseStream([created()], [textDelta("Noted."), completed()]))
        let languageModel = model(stub, scenario.details, serverTools: scenario.serverTools, options: scenario.options)
        _ = try await LanguageModelSession(model: languageModel, tools: scenario.tools, transcript: transcript).respond(to: "And next?")
        return try #require(stub.requests.first).body
    }
}
