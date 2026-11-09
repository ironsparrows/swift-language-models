import CustomDump
import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

/// The transcripts of the recorded exchanges, as apps have saved them, each beside the bytes its next turn sends. They
/// hold what each provider really sent, signatures included, and saved transcripts outlive the code that wrote them, so
/// these files never change.
@Suite("Recorded transcripts", .timeLimit(.minutes(1)))
struct RecordedTranscriptTests {
    @Test(arguments: RecordedScenario.answered)
    func `a recorded transcript sends the same bytes on its next turn`(scenario: RecordedScenario) async throws {
        let saved = try Bundle.module.fixture("Transcripts/recorded-\(scenario.name).next-turn.json")

        let sent = try await Self.nextTurn(after: Self.transcript(scenario), of: scenario)

        expectNoDifference(String(decoding: sent, as: UTF8.self), String(decoding: saved, as: UTF8.self))
    }

    @Test func `a recorded transcript reads the same through the typed readers`() throws {
        let readings = try RecordedScenario.answered.map { scenario in
            let facts = try Self.transcript(scenario).compactMap { entry -> String? in
                switch entry {
                case .response(let response): "response \(Self.facts(response.openAICompatible)), host: \(response.host)"
                case .toolCalls(let calls): "toolCalls \(Self.facts(calls.openAICompatible))"
                default: nil
                }
            }
            return ([scenario.name] + facts).joined(separator: "\n")
        }

        assertInlineSnapshot(of: readings.joined(separator: "\n\n"), as: .lines) {
            """
            gemini-text
            response model: gemini-3.1-flash-lite, responseID: CUzWRFY6bCGlgpa13cm9eh, requestID: nil, finishReason: stop, host: Google AI Studio

            gemini-tools
            toolCalls model: gemini-3.1-flash-lite, responseID: 435AnFdzEs9obB2me8Jw8yY, requestID: nil, finishReason: stop
            response model: gemini-3.1-flash-lite, responseID: H8ZKYk689yB9JwuxXR4FpL, requestID: nil, finishReason: stop, host: Google AI Studio

            gemini-guided
            response model: gemini-3.1-flash-lite, responseID: SqkK2DituwOEXlDiJ3mv9Sf, requestID: nil, finishReason: stop, host: Google AI Studio

            gemini-reasoning
            response model: gemini-3.1-flash-lite, responseID: djN7Rpdyqp0t3J95NjPGRNS, requestID: nil, finishReason: stop, host: Google AI Studio

            gemini-cached
            response model: gemini-3.1-flash-lite, responseID: ldFsNiBxla3-D4g8nFnx1ku, requestID: nil, finishReason: stop, host: Google AI Studio
            response model: gemini-3.1-flash-lite, responseID: P-817tZ6kxBznLNA3SXfml, requestID: nil, finishReason: stop, host: Google AI Studio

            groq-text
            response model: openai/gpt-oss-20b, responseID: chatcmpl-6c3790f0-66ec-353e-435e-79cbf58b8904, requestID: req_015qz8ld8tvjhzmt437ut7mv81, finishReason: stop, host: Groq

            groq-tools
            toolCalls model: openai/gpt-oss-20b, responseID: chatcmpl-98200e69-bdf9-db1f-fa92-a7d5ffd89e8c, requestID: req_0190bp78kxg94b5obylemwhfjv, finishReason: tool_calls
            toolCalls model: openai/gpt-oss-20b, responseID: chatcmpl-8a983ce6-bbb9-c610-dcdc-f3666bfdb862, requestID: req_01ibnie42qgnnk437sxohh6goi, finishReason: tool_calls
            response model: openai/gpt-oss-20b, responseID: chatcmpl-bc66169d-57cd-0951-7f3e-4c47cb53713e, requestID: req_01jo59m8yl9g86phb3gd7gx6re, finishReason: stop, host: Groq

            groq-guided
            response model: openai/gpt-oss-20b, responseID: chatcmpl-76a4f450-377b-11b1-4da0-dab8b41b206a, requestID: req_01nmsodw4x2ai9ocuyybln1t4v, finishReason: stop, host: Groq

            groq-reasoning
            response model: openai/gpt-oss-20b, responseID: chatcmpl-e4af15c4-69ec-8096-d6cb-6a2c43bfa17c, requestID: req_016qim5yjxl1qfg5rgli8biv4e, finishReason: stop, host: Groq

            groq-cached
            response model: openai/gpt-oss-20b, responseID: chatcmpl-7777fce0-aeff-93fa-6147-ec1c7b190d9d, requestID: req_01avt4ljjx5f8bswvc27jahijh, finishReason: stop, host: Groq
            response model: openai/gpt-oss-20b, responseID: chatcmpl-d602f645-f04e-8cef-6081-58b635f0ccc7, requestID: req_01oyyfy080bapourji52vltzbo, finishReason: stop, host: Groq

            ollama-text
            response model: qwen3:0.6b, responseID: chatcmpl-443, requestID: nil, finishReason: stop, host: nil

            ollama-tools
            toolCalls model: qwen3:0.6b, responseID: chatcmpl-000, requestID: nil, finishReason: tool_calls
            response model: qwen3:0.6b, responseID: chatcmpl-618, requestID: nil, finishReason: stop, host: nil

            ollama-guided
            response model: qwen3.5:4b, responseID: chatcmpl-294, requestID: nil, finishReason: stop, host: nil

            ollama-reasoning
            response model: qwen3:0.6b, responseID: chatcmpl-242, requestID: nil, finishReason: stop, host: nil

            ollama-cached
            response model: qwen3:0.6b, responseID: chatcmpl-581, requestID: nil, finishReason: stop, host: nil
            response model: qwen3:0.6b, responseID: chatcmpl-512, requestID: nil, finishReason: stop, host: nil
            """
        }
    }

    private static func transcript(_ scenario: RecordedScenario) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: Bundle.module.fixture("Transcripts/recorded-\(scenario.name).json"))
    }

    /// The bytes a session sends for one more prompt after a transcript, on the scenario's model.
    static func nextTurn(after transcript: Transcript, of scenario: RecordedScenario) async throws -> Data {
        let stub = HTTPStub(chunks(text("Noted."), finish()))
        let session = LanguageModelSession(model: scenario.model(stub), tools: scenario.tools, transcript: transcript)
        _ = try await session.respond(to: "And next?")
        return try #require(stub.requests.first).body
    }

    /// The facts the reader gives that these providers send.
    private static func facts(_ metadata: OpenAICompatibleResponseMetadata) -> String {
        func text(_ value: (some Any)?) -> String { value.map { String(describing: $0) } ?? "nil" }
        return """
            model: \(text(metadata.model?.rawValue)), responseID: \(text(metadata.responseID)), requestID: \(text(metadata.requestID)), \
            finishReason: \(text(metadata.finishReason?.rawValue))
            """
    }
}

extension Transcript.Response {
    /// The host the answer names, or `nil` when it names none.
    fileprivate var host: String {
        providerMetadata.host ?? "nil"
    }
}
