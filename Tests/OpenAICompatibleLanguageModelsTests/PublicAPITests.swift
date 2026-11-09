// This file has no `@testable` import: it goes where an app goes, from a provider it describes and a key through a
// session to the transcript's typed readers.
import Foundation
import FoundationModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

@Suite("Public API", .tags(.loopback), .timeLimit(.minutes(1)))
struct PublicAPITests {
    @Test func `a model on a provider the app describes answers in a session, with its reasoning and facts`() async throws {
        // Groq's answer, ids swapped, as a provider described by its name and URL gets it.
        let recorded = String(decoding: try Bundle.module.fixture("Captured/groq-text.sse"), as: UTF8.self)
        let server = try await LoopbackServer(
            LoopbackReply(
                headers: ["Content-Type": "text/event-stream", "x-request-id": "req_01test00000000000000000001"],
                writes: [Data(recorded.utf8)]))
        let provider = OpenAICompatibleProvider(name: "Groq", url: server.baseURL, headers: ["X-Team": "meals"])
        let details = OpenAICompatibleModel("openai/gpt-oss-20b", on: provider, efforts: [.high, .medium, .low])
        let model = OpenAICompatibleLanguageModel(details, auth: .apiKey { "gsk-test" })
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(
            to: "Write one unusual English word, nothing else.", contextOptions: ContextOptions(reasoningLevel: .light))

        #expect(response.content == "quixotry")
        #expect(response.usage.input.totalTokenCount == 80)
        guard case .response(let answer)? = session.transcript.last else {
            Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
            return
        }
        #expect(answer.openAICompatible.model == "openai/gpt-oss-20b")
        #expect(answer.openAICompatible.requestID == "req_01test00000000000000000001")
        #expect(answer.openAICompatible.finishReason == .stop)
        #expect(session.transcript.contains { if case .reasoning = $0 { true } else { false } })
        let request = try #require(server.requests.first)
        #expect(request.request.url?.path == "/chat/completions")
        #expect(request.request.value(forHTTPHeaderField: "Authorization") == "Bearer gsk-test")
        #expect(request.request.value(forHTTPHeaderField: "X-Team") == "meals")
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["reasoning_effort"] as? String == "low")
        #expect((body["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
    }
}
