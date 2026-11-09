import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

/// Requests to an Ollama server on this Mac through its preset, for what only the server can show: its reasoning out
/// and back, its guided answers, what it does with a prompt over the model's context, and its failures. They run on
/// `qwen3:0.6b`, and on `qwen3.5:4b` for a schema, which the server must have pulled, and only with
/// `LIVE_LOCAL_SERVERS=1` in the environment.
@Suite(
    "Live: Ollama",
    .tags(.live),
    .serialized,
    .requiresLocalServersRequested,
    .enabled("Ollama isn't running at http://localhost:11434 with qwen3:0.6b and qwen3.5:4b") {
        await LocalServer.isReady(at: OpenAICompatibleProvider.ollama.url, with: ["qwen3:0.6b", "qwen3.5:4b"])
    },
    .timeLimit(.minutes(3))
)
struct LiveOllamaTests {
    /// A model on the preset, which reasons unless a request turns reasoning off.
    static func model(_ id: OpenAICompatibleModelID = "qwen3:0.6b") -> OpenAICompatibleLanguageModel {
        OpenAICompatibleLanguageModel(OpenAICompatibleModel(id, on: .ollama, reasoning: .onByDefault), auth: .unauthenticated)
    }

    @Test func `an answer with reasoning off has no reasoning, and names its model`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "Name one color of the sea.", options: shortAnswer, contextOptions: ContextOptions(reasoningLevel: .off))

        let answer = try #require(lastAnswer(in: response.transcriptEntries))
        #expect(!response.content.isEmpty)
        #expect(reasoningEntries(in: response.transcriptEntries).isEmpty)
        #expect(answer.openAICompatible.model == "qwen3:0.6b")
        #expect(answer.providerMetadata.host == nil)
        #expect(response.usage.output.totalTokenCount > 0)
    }

    @Test func `an answer that reasons keeps its reasoning`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "What is 12 plus 30? Reply with the number only.", options: GenerationOptions(maximumResponseTokens: 1_500))

        #expect(reasoningEntries(in: response.transcriptEntries).contains { !$0.segments.isEmpty })
        #expect(response.content.contains("42"))
    }

    @Test func `a call's reasoning goes back with it, and later turns still answer`() async throws {
        let session = try await answerTwoTurnsWithTool(Self.model())

        #expect(!reasoningEntries(in: session.transcript).isEmpty)
        record(session.transcript, named: "transcript.txt")
    }

    @Test func `a guided answer decodes`() async throws {
        let response = try await LanguageModelSession(model: Self.model("qwen3.5:4b")).respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_500),
            contextOptions: ContextOptions(reasoningLevel: .off))

        #expect(response.content.activities.count == 3)
        #expect((1...14).contains(response.content.days))
    }

    // Over the 40,960 tokens `qwen3:0.6b` was trained on, so over any context the server loads it with.
    @Test func `a prompt over the model's context is cut to fit, with no error`() async throws {
        let words = 60_000

        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: String(repeating: "word ", count: words) + "\nReply with OK.", options: GenerationOptions(maximumResponseTokens: 200),
            contextOptions: ContextOptions(reasoningLevel: .off))

        record(response.usage, named: "usage.txt")
        #expect(response.usage.input.totalTokenCount < words)
    }

    @Test func `a repeated long prefix reads the loaded model's cache`() async throws {
        let inputs = try await cachedInputs(Self.model(), copies: 200, contextOptions: ContextOptions(reasoningLevel: .off))

        let repeated = try #require(inputs.dropFirst().first)
        #expect(repeated.cached > repeated.input / 2)
        #expect(repeated.cached <= repeated.input)
    }

    @Test func `a model the server doesn't have throws with the code not found`() async throws {
        let session = LanguageModelSession(
            model: OpenAICompatibleLanguageModel(OpenAICompatibleModel("no-such-model:1b", on: .ollama), auth: .unauthenticated))

        let error = try await #require(throws: OpenAICompatibleError.self) {
            _ = try await session.respond(to: "Say hello.", options: shortAnswer)
        }

        #expect(error.status == 404)
        #expect(error.code == .notFound)
    }
}
