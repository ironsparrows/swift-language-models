import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

/// Requests to Groq's API through its preset, for what only Groq can show: its reasoning out and back, its guided
/// answers and its failures. They run on `openai/gpt-oss-20b`, which always reasons, and `qwen/qwen3.8-27b`, which
/// reasons when asked, within the free plan's limits, so each test waits 5 seconds first.
@Suite(
    "Live: Groq",
    .tags(.live),
    .serialized,
    .requiresAPIKey("GROQ_API_KEY"),
    .skipsUnavailableProvider,
    .paced(.seconds(5)),
    .timeLimit(.minutes(3))
)
struct LiveGroqTests {
    /// GPT-OSS 20B, which always reasons, at the efforts it takes.
    static func gptOSS(options: OpenAICompatibleOptions = OpenAICompatibleOptions(), key: String? = nil) -> OpenAICompatibleLanguageModel {
        model(
            OpenAICompatibleModel("openai/gpt-oss-20b", on: .groq, reasoning: .mandatory, efforts: [.high, .medium, .low]),
            options: options, key: key)
    }

    /// Qwen3.8 27B, which reasons when asked, at the efforts it takes.
    static func qwen() -> OpenAICompatibleLanguageModel {
        model(OpenAICompatibleModel("qwen/qwen3.8-27b", on: .groq, efforts: [.high, .medium, .low, .off]))
    }

    private static func model(
        _ details: OpenAICompatibleModel, options: OpenAICompatibleOptions = OpenAICompatibleOptions(), key: String? = nil
    ) -> OpenAICompatibleLanguageModel {
        // Foundation Models may call the key closure from a task of its own, where the test's key isn't bound.
        let key = key ?? APIKeyTrait.current ?? ""
        return OpenAICompatibleLanguageModel(details, options: options, auth: .apiKey { key })
    }

    @Test func `an answer keeps its reasoning and names Groq's host and request`() async throws {
        let response = try await LanguageModelSession(model: Self.gptOSS()).respond(
            to: "Name one color of the sea.", options: shortAnswer, contextOptions: ContextOptions(reasoningLevel: .light))

        let answer = try #require(lastAnswer(in: response.transcriptEntries))
        #expect(!response.content.isEmpty)
        #expect(reasoningEntries(in: response.transcriptEntries).contains { !$0.segments.isEmpty })
        #expect(answer.providerMetadata.host == "Groq")
        #expect(answer.openAICompatible.requestID?.hasPrefix("req_") == true)
        #expect(response.usage.output.reasoningTokenCount > 0)
    }

    @Test(arguments: ["gpt-oss", "qwen"])
    func `a tool's output reaches the answer, and reasoning goes back on later turns`(model: String) async throws {
        try await withKnownIssue("Groq doesn't always read a model's call, which fails with tool_use_failed.", isIntermittent: true) {
            let session = try await answerTwoTurnsWithTool(
                model == "qwen" ? Self.qwen() : Self.gptOSS(), contextOptions: ContextOptions(reasoningLevel: .light))

            #expect(reasoningEntries(in: session.transcript).contains { !$0.segments.isEmpty })
            record(session.transcript, named: "transcript.txt")
        } matching: { issue in
            (issue.error as? OpenAICompatibleError)?.code == "tool_use_failed"
        }
    }

    @Test func `qwen reasons when asked, and not with the effort none`() async throws {
        let asked = try await LanguageModelSession(model: Self.qwen()).respond(
            to: "What is 12 plus 30?", options: GenerationOptions(maximumResponseTokens: 1_500),
            contextOptions: ContextOptions(reasoningLevel: .light))
        let off = try await LanguageModelSession(model: Self.qwen()).respond(
            to: "What is 12 plus 30?", options: shortAnswer, contextOptions: ContextOptions(reasoningLevel: .off))

        #expect(!reasoningEntries(in: asked.transcriptEntries).isEmpty)
        #expect(reasoningEntries(in: off.transcriptEntries).isEmpty)
        #expect(off.content.contains("42"))
    }

    @Test func `a guided answer decodes`() async throws {
        let response = try await LanguageModelSession(model: Self.gptOSS()).respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_500),
            contextOptions: ContextOptions(reasoningLevel: .light))

        #expect(response.content.activities.count == 3)
        #expect((1...14).contains(response.content.days))
    }

    // The free plan reported no cached tokens on 9 November 2026, for `openai/gpt-oss-20b` and `openai/gpt-oss-120b`,
    // streamed or not.
    @Test func `a repeated long prefix reads Groq's cache, when Groq reports one`() async throws {
        let inputs = try await cachedInputs(Self.gptOSS(), copies: 150, contextOptions: ContextOptions(reasoningLevel: .light))

        #expect(inputs.first?.cached == 0)
        #expect(inputs.allSatisfy { $0.cached <= $0.input })
        withKnownIssue("Groq's free plan reports no cached tokens.", isIntermittent: true) {
            #expect(inputs.dropFirst().contains { $0.cached > 0 })
        }
    }

    @Test func `a key Groq refuses throws its code`() async throws {
        let session = LanguageModelSession(model: Self.gptOSS(key: "gsk-not-a-key"))

        let error = try await #require(throws: OpenAICompatibleError.self) {
            _ = try await session.respond(to: "Say hello.", options: shortAnswer, contextOptions: ContextOptions(reasoningLevel: .light))
        }

        record(error, named: "error.txt")
        #expect(error.status == 401)
        #expect(error.code == .invalidAPIKey)
    }

    // On the free plan, `openai/gpt-oss-20b` takes 8,000 tokens a minute; a plan that takes more answers the prompt.
    @Test func `a prompt over the tokens a minute throws Groq's error with its wait, not a rate limit`() async throws {
        let session = LanguageModelSession(model: Self.gptOSS())

        do {
            _ = try await session.respond(
                to: String(repeating: "word ", count: 12_000), options: GenerationOptions(maximumResponseTokens: 16),
                contextOptions: ContextOptions(reasoningLevel: .light))
            try Test.cancel("The account takes more than 12,000 tokens a minute.")
        } catch let error as OpenAICompatibleError {
            record(error, named: "error.txt")
            #expect(error.status == 413)
            #expect(error.code == "rate_limit_exceeded")
            #expect(error.retryAfter != nil)
        }
    }
}
