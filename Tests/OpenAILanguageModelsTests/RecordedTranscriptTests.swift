import CustomDump
import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

/// The transcripts of the recorded exchanges, as apps have saved them, each beside the bytes its next turn sends. They
/// hold what OpenAI really reported, and saved transcripts outlive the code that wrote them, so these files never
/// change.
@Suite("Recorded transcripts", .timeLimit(.minutes(1)))
struct RecordedTranscriptTests {
    static let scenarios: [RecordedScenario] = [.text, .reasoning, .tools, .guided, .plain, .options, .cached]

    /// The transcripts of every Xcode and system, then the one that needs the newer ones to read its attachments.
    static let allScenarios: [RecordedScenario] = {
        #if canImport(FoundationModels, _version: 2.1.14)
        if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) {
            return scenarios + [.attachments]
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
            """
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
            """
        }
    }

    private static func transcript(_ scenario: RecordedScenario) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: Bundle.module.fixture("Transcripts/recorded-\(scenario.name).json"))
    }

    /// The bytes a session sends for one more prompt after a transcript, on the scenario's model.
    static func nextTurn(after transcript: Transcript, of scenario: RecordedScenario) async throws -> Data {
        let stub = HTTPStub(responseStream([created()], [textDelta("Noted."), completed()]))
        let languageModel = model(stub, scenario.details, options: scenario.options)
        _ = try await LanguageModelSession(model: languageModel, tools: scenario.tools, transcript: transcript).respond(to: "And next?")
        return try #require(stub.requests.first).body
    }
}
