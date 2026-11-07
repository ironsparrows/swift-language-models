import CustomDump
import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

/// The transcripts of the exact exchanges, as apps have saved them, each beside the bytes its next turn sends. Saved
/// transcripts outlive the code that wrote them, so these files never change.
@Suite("Saved transcripts", .timeLimit(.minutes(1)))
struct SavedTranscriptTests {
    static let names = ["text-with-options", "tool-round", "plain", "real-stream"]

    /// The transcripts of every Xcode and system, then the one that needs the newer ones to read its attachments.
    static let allNames: [String] = {
        #if canImport(FoundationModels, _version: 2.1.14)
        if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) {
            return names + ["attachments"]
        }
        #endif
        return names
    }()

    @Test(arguments: allNames)
    func `a saved transcript sends the same bytes on its next turn, its JPEGs aside`(name: String) async throws {
        let saved = try Bundle.module.fixture("Transcripts/\(name).next-turn.json")

        let sent = try await Self.nextTurn(after: name)

        expectNoDifference(
            ExactExchange.withoutJPEGs(String(decoding: sent, as: UTF8.self)),
            ExactExchange.withoutJPEGs(String(decoding: saved, as: UTF8.self))
        )
    }

    @Test func `a saved transcript reads the same through the typed readers`() throws {
        let readings = try Self.names.map { name in
            let facts = try Self.transcript(name).compactMap { entry -> String? in
                switch entry {
                case .response(let response): "response \(Self.facts(response.openAI))"
                case .toolCalls(let calls): "toolCalls \(Self.facts(calls.openAI))"
                default: nil
                }
            }
            return ([name] + facts).joined(separator: "\n")
        }

        assertInlineSnapshot(of: readings.joined(separator: "\n\n"), as: .lines) {
            """
            text-with-options
            response model: gpt-test-2026-10-01, responseID: resp_1, requestID: req_1, finishReason: stop, serviceTier: default, citations: [], messages: ["final_answer 13 nil"], cacheWriteTokenCount: nil

            tool-round
            toolCalls model: gpt-test-2026-10-01, responseID: resp_1, requestID: nil, finishReason: tool_calls, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: nil
            response model: gpt-test-2026-10-01, responseID: resp_1, requestID: nil, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: nil

            plain
            response model: gpt-plain, responseID: resp_1, requestID: nil, finishReason: stop, serviceTier: default, citations: [], messages: [], cacheWriteTokenCount: nil

            real-stream
            response model: gpt-6-luna, responseID: resp_021ee27c8790196a016ae9a56d688887d290214057379e9b39, requestID: nil, finishReason: stop, serviceTier: default, citations: [], messages: ["final_answer 3 nil"], cacheWriteTokenCount: 0
            """
        }
    }

    /// A saved transcript.
    static func transcript(_ name: String) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: Bundle.module.fixture("Transcripts/\(name).json"))
    }

    /// The bytes a session sends for one more prompt after a saved transcript, on the model that wrote it, since OpenAI's
    /// reasoning goes back only to that model.
    static func nextTurn(after name: String) async throws -> Data {
        let transcript = try transcript(name)
        let hasCalls = transcript.contains { if case .toolCalls = $0 { true } else { false } }
        let stub = HTTPStub(responseStream([created()], [textDelta("Noted."), completed()]))
        func respond(with model: some LanguageModel) async throws {
            let session = LanguageModelSession(model: model, tools: hasCalls ? [FoodTool()] : [], transcript: transcript)
            _ = try await session.respond(to: "And next?")
        }
        switch name {
        case "plain":
            try await respond(with: plainModel(stub))
        case "real-stream":
            let details: OpenAIModel<ContextOptions.ReasoningLevel> = details(id: "gpt-6-luna", efforts: [.high, .off])
            try await respond(with: model(stub, details))
        default:
            try await respond(with: reasoningModel(stub))
        }
        return try #require(stub.requests.first).body
    }

    /// Every fact the reader gives.
    static func facts(_ metadata: OpenAIResponseMetadata) -> String {
        func text(_ value: (some Any)?) -> String { value.map { String(describing: $0) } ?? "nil" }
        let citations = metadata.citations.map { "\($0.url) \(text($0.title))" }
        let messages = metadata.messages.map { "\(text($0.phase?.rawValue)) \($0.length) \(text($0.heldText))" }
        return """
            model: \(text(metadata.model?.rawValue)), responseID: \(text(metadata.responseID)), requestID: \(text(metadata.requestID)), \
            finishReason: \(text(metadata.finishReason?.rawValue)), serviceTier: \(text(metadata.serviceTier?.rawValue)), \
            citations: \(citations), messages: \(messages), cacheWriteTokenCount: \(text(metadata.usage.cacheWriteTokenCount))
            """
    }
}
