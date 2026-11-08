// This file has no `@testable` import: it goes where an app goes, from a catalog model and its authentication through a
// session to the transcript's typed readers.
import Foundation
import FoundationModels
import LanguageModelsTestSupport
import OpenAILanguageModels
import Testing

@Suite("Public API", .tags(.loopback), .timeLimit(.minutes(1)))
struct PublicAPITests {
    @Test func `a catalog model, pointed at a server by its authentication, answers in a session`() async throws {
        let recorded = String(decoding: try Bundle.module.fixture("Recorded/text.1.sse"), as: UTF8.self)
        let server = try await LoopbackServer(.eventStream(recorded))
        let model = OpenAILanguageModel(.gpt6Luna, auth: .apiKey(baseURL: server.baseURL) { "sk-test" })
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(to: "Name one color of the sea.")

        #expect(response.content == "Blue.")
        guard case .response(let answer)? = session.transcript.last else {
            Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
            return
        }
        #expect(answer.openAI.model == "gpt-5-nano-2025-08-07")
        #expect(answer.providerMetadata.model == "gpt-5-nano-2025-08-07")
        let request = try #require(server.requests.first?.request)
        #expect(request.url?.path == "/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }
}
