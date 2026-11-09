import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

/// Requests to Mistral's API through its preset, for what only Mistral can show: its usage, its tool call ids, its
/// guided answers and its failures. They run on `mistral-small-latest`.
@Suite(
    "Live: Mistral",
    .tags(.live),
    .serialized,
    .requiresAPIKey("MISTRAL_API_KEY"),
    .skipsUnavailableProvider,
    .timeLimit(.minutes(3))
)
struct LiveMistralTests {
    /// A model on the preset with the running test's key, or with the given one.
    static func model(options: OpenAICompatibleOptions = OpenAICompatibleOptions(), key: String? = nil) -> OpenAICompatibleLanguageModel {
        // Foundation Models may call the key closure from a task of its own, where the test's key isn't bound.
        let key = key ?? APIKeyTrait.current ?? ""
        return OpenAICompatibleLanguageModel(
            OpenAICompatibleModel("mistral-small-latest", on: .mistral), options: options, auth: .apiKey { key })
    }

    @Test func `an answer names its model and Mistral's host, with its usage`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "Name one color of the sea.", options: shortAnswer)

        let answer = try #require(lastAnswer(in: response.transcriptEntries))
        #expect(!response.content.isEmpty)
        #expect(answer.providerMetadata.host == "Mistral")
        #expect(response.usage.input.totalTokenCount > 0)
    }

    @Test func `a tool's output reaches the answer on two turns`() async throws {
        let session = try await answerTwoTurnsWithTool(Self.model())

        record(session.transcript, named: "transcript.txt")
    }

    @Test func `a guided answer decodes`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_000))

        #expect(response.content.activities.count == 3)
    }

    @Test func `a key Mistral refuses throws a 401`() async throws {
        let session = LanguageModelSession(model: Self.model(key: "not-a-key"))

        let error = try await #require(throws: OpenAICompatibleError.self) {
            _ = try await session.respond(to: "Say hello.", options: shortAnswer)
        }

        record(error, named: "error.txt")
        #expect(error.status == 401)
    }
}
