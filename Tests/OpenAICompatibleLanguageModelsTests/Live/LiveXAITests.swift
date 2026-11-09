import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

/// Requests to xAI's Responses API through its preset, for what only xAI can show: its encrypted reasoning going back
/// on later turns whether or not xAI keeps the response, its guided answers and its failures. They run on `grok-4.3`.
@Suite(
    "Live: xAI",
    .tags(.live),
    .serialized,
    .requiresAPIKey("XAI_API_KEY"),
    .skipsUnavailableProvider,
    .timeLimit(.minutes(5))
)
struct LiveXAITests {
    /// A model on the preset with the running test's key, or with the given one.
    static func model(options: OpenAICompatibleOptions = OpenAICompatibleOptions(), key: String? = nil) -> OpenAICompatibleLanguageModel {
        // Foundation Models may call the key closure from a task of its own, where the test's key isn't bound.
        let key = key ?? APIKeyTrait.current ?? ""
        return OpenAICompatibleLanguageModel(OpenAICompatibleModel("grok-4.3", on: .xAI), options: options, auth: .apiKey { key })
    }

    @Test func `an answer names its model and xAI's host, with its usage`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "Name one color of the sea.", options: shortAnswer, contextOptions: ContextOptions(reasoningLevel: .off))

        let answer = try #require(lastAnswer(in: response.transcriptEntries))
        #expect(!response.content.isEmpty)
        #expect(answer.providerMetadata.host == "xAI")
        #expect(response.usage.input.totalTokenCount > 0)
    }

    @Test(arguments: [OpenAICompatibleOptions.Storage.automatic, .stored])
    func `encrypted reasoning is kept, and later turns still answer, whether or not xAI keeps the response`(
        storage: OpenAICompatibleOptions.Storage
    ) async throws {
        let session = try await answerTwoTurnsWithTool(
            Self.model(options: OpenAICompatibleOptions(storage: storage)), contextOptions: ContextOptions(reasoningLevel: .light),
            options: GenerationOptions(maximumResponseTokens: 2_000))

        #expect(reasoningEntries(in: session.transcript).contains { $0.signature != nil })
        record(session.transcript, named: "transcript.txt")
    }

    @Test func `a repeated long prefix with a cache key reads xAI's cache`() async throws {
        let inputs = try await cachedInputs(
            Self.model(options: OpenAICompatibleOptions(cacheKey: .named(UUID().uuidString))), copies: 300,
            contextOptions: ContextOptions(reasoningLevel: .off))

        #expect(inputs.first?.cached == 0)
        #expect(inputs.allSatisfy { $0.cached <= $0.input })
        withKnownIssue("xAI's cache doesn't always serve a prefix this soon.", isIntermittent: true) {
            #expect(inputs.dropFirst().contains { $0.cached > 0 })
        }
    }

    @Test func `a guided answer decodes`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_000),
            contextOptions: ContextOptions(reasoningLevel: .off))

        #expect(response.content.activities.count == 3)
    }

    @Test func `a key xAI refuses throws with the code authentication`() async throws {
        let session = LanguageModelSession(model: Self.model(key: "xai-not-a-key"))

        let error = try await #require(throws: OpenAICompatibleError.self) {
            _ = try await session.respond(to: "Say hello.", options: shortAnswer)
        }

        record(error, named: "error.txt")
        #expect(error.status == 400)
        #expect(error.code == .authentication)
    }
}
