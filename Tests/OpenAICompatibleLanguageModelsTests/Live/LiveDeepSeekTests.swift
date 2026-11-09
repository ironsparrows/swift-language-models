import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

/// Requests to DeepSeek's API through its preset, for what only DeepSeek can show: its reasoning out and back on later
/// turns with tools, its `thinking` switch and its failures. They run on `deepseek-flash`.
@Suite(
    "Live: DeepSeek",
    .tags(.live),
    .serialized,
    .requiresAPIKey("DEEPSEEK_API_KEY"),
    .skipsUnavailableProvider,
    .timeLimit(.minutes(3))
)
struct LiveDeepSeekTests {
    /// A model on the preset, which reasons unless a request turns reasoning off, with the running test's key or the
    /// given one.
    static func model(key: String? = nil) -> OpenAICompatibleLanguageModel {
        // Foundation Models may call the key closure from a task of its own, where the test's key isn't bound.
        let key = key ?? APIKeyTrait.current ?? ""
        return OpenAICompatibleLanguageModel(OpenAICompatibleModel("deepseek-flash", on: .deepSeek), auth: .apiKey { key })
    }

    @Test func `an answer keeps its reasoning and names DeepSeek's host`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "What is 12 plus 30?", options: GenerationOptions(maximumResponseTokens: 2_000))

        let answer = try #require(lastAnswer(in: response.transcriptEntries))
        #expect(response.content.contains("42"))
        #expect(reasoningEntries(in: response.transcriptEntries).contains { !$0.segments.isEmpty })
        #expect(answer.providerMetadata.host == "DeepSeek")
    }

    @Test func `an answer with reasoning off has no reasoning`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "What is 12 plus 30?", options: shortAnswer, contextOptions: ContextOptions(reasoningLevel: .off))

        #expect(reasoningEntries(in: response.transcriptEntries).isEmpty)
        #expect(response.content.contains("42"))
    }

    @Test(arguments: [ContextOptions.ReasoningLevel.light, .off])
    func `a tool's output reaches the answer, and reasoning goes back on later turns`(level: ContextOptions.ReasoningLevel) async throws {
        let session = try await answerTwoTurnsWithTool(
            Self.model(), contextOptions: ContextOptions(reasoningLevel: level), options: GenerationOptions(maximumResponseTokens: 3_000))

        record(session.transcript, named: "transcript.txt")
    }

    @Test func `a key DeepSeek refuses throws a 401`() async throws {
        let session = LanguageModelSession(model: Self.model(key: "sk-not-a-key"))

        let error = try await #require(throws: OpenAICompatibleError.self) {
            _ = try await session.respond(to: "Say hello.", options: shortAnswer)
        }

        record(error, named: "error.txt")
        #expect(error.status == 401)
    }
}
