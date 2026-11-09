import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

/// Requests to Gemini's API through its preset, for what only Gemini can show: its signatures on later turns, its
/// guided answers and its failures. They run on `gemini-3.1-flash-lite`, within the free tier's 15 requests a minute,
/// so each test waits 20 seconds first.
@Suite(
    "Live: Gemini",
    .tags(.live),
    .serialized,
    .requiresAPIKey("GEMINI_API_KEY"),
    .skipsUnavailableProvider,
    .paced(.seconds(20)),
    .timeLimit(.minutes(3))
)
struct LiveGeminiTests {
    /// A model on the preset with the running test's key, or with the given one.
    static func model(
        _ id: OpenAICompatibleModelID = "gemini-3.1-flash-lite",
        options: OpenAICompatibleOptions = OpenAICompatibleOptions(),
        key: String? = nil
    ) -> OpenAICompatibleLanguageModel {
        // Foundation Models may call the key closure from a task of its own, where the test's key isn't bound.
        let key = key ?? APIKeyTrait.current ?? ""
        return OpenAICompatibleLanguageModel(OpenAICompatibleModel(id, on: .gemini), options: options, auth: .apiKey { key })
    }

    @Test func `an answer names its model and Gemini's host, with its usage`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "Name one color of the sea.", options: shortAnswer)

        let answer = try #require(lastAnswer(in: response.transcriptEntries))
        #expect(!response.content.isEmpty)
        #expect(answer.openAICompatible.model == "gemini-3.1-flash-lite")
        #expect(answer.providerMetadata.host == "Google AI Studio")
        #expect(response.usage.input.totalTokenCount > 0)
    }

    @Test func `parallel calls and their signature go back, and later turns still answer`() async throws {
        let session = LanguageModelSession(model: Self.model(), tools: [WeatherTool()])

        let first = try await session.respond(
            to: "What's the temperature in Lisbon and in Porto? Call the tool for both cities at once.", options: shortAnswer)
        let second = try await session.respond(to: "And in Madrid? Use the tool.", options: shortAnswer)

        #expect(first.content.contains("17"))
        #expect(second.content.contains("17"))
        #expect(Set(try session.transcript.weatherCities()).isSuperset(of: ["Lisbon", "Porto", "Madrid"]))
        #expect(session.transcript.contains { if case .toolCalls(let calls) = $0 { calls.count > 1 } else { false } })
        #expect(reasoningEntries(in: session.transcript).contains { $0.signature?.isEmpty == false })
        record(session.transcript, named: "transcript.txt")
    }

    @Test func `a guided answer decodes`() async throws {
        let response = try await LanguageModelSession(model: Self.model()).respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_000))

        #expect(response.content.activities.count == 3)
        #expect((1...14).contains(response.content.days))
    }

    @Test func `an answer at a high effort carries a signature, which goes back on the next turn`() async throws {
        let session = LanguageModelSession(model: Self.model())

        _ = try await session.respond(
            to: "What is 17 times 23?", options: GenerationOptions(maximumResponseTokens: 1_200),
            contextOptions: ContextOptions(reasoningLevel: .deep))
        let next = try await session.respond(to: "And 17 times 24?", options: shortAnswer)

        #expect(reasoningEntries(in: session.transcript).contains { $0.signature?.isEmpty == false })
        #expect(next.content.contains("408"))
    }

    @Test func `a transcript continued on another Gemini model still answers`() async throws {
        let first = try await answerTwoTurnsWithTool(Self.model())

        let other = LanguageModelSession(model: Self.model("gemini-3.5-flash-lite"), tools: [WeatherTool()], transcript: first.transcript)
        let response = try await other.respond(to: "And in Madrid? Use the tool.", options: shortAnswer)

        #expect(response.content.contains("17"))
    }

    @Test func `a repeated long prefix reads Gemini's cache`() async throws {
        let inputs = try await cachedInputs(Self.model(), copies: 450)

        #expect(inputs.first?.cached == 0)
        #expect(inputs.allSatisfy { $0.cached <= $0.input })
        withKnownIssue("Gemini's cache doesn't always serve a prefix this soon.", isIntermittent: true) {
            #expect(inputs.dropFirst().contains { $0.cached > 0 })
        }
    }

    // Why `OpenAICompatibleOptions.cacheKey` stays out of Gemini's requests.
    @Test func `Gemini refuses prompt_cache_key, naming it`() async throws {
        let options = OpenAICompatibleOptions(additionalMembers: ["prompt_cache_key": GeneratedContent("run-1")])

        let error = try await #require(throws: OpenAICompatibleError.self) {
            _ = try await LanguageModelSession(model: Self.model(options: options)).respond(to: "Say hello.", options: shortAnswer)
        }

        #expect(error.status == 400)
        #expect(error.parameter == "prompt_cache_key")
    }

    @Test func `a key Gemini refuses throws with the code authentication`() async throws {
        let session = LanguageModelSession(model: Self.model(key: "AIza-not-a-key"))

        let error = try await #require(throws: OpenAICompatibleError.self) {
            _ = try await session.respond(to: "Say hello.", options: shortAnswer)
        }

        record(error, named: "error.txt")
        #expect(error.status == 400)
        #expect(error.code == .authentication)
    }

    @Test func `a prompt over the model's context throws an oversized context`() async throws {
        let session = LanguageModelSession(model: Self.model())

        let error = try await #require(throws: LanguageModelError.self) {
            _ = try await session.respond(
                to: String(repeating: "word ", count: 1_100_000), options: GenerationOptions(maximumResponseTokens: 16))
        }

        record(error, named: "error.txt")
        // The free tier's input tokens a minute refuse such a prompt before its size is checked.
        if case .rateLimited = error { try Test.cancel("Gemini's rate limit refused the prompt before its size was checked") }
        guard case .contextSizeExceeded(let context) = error else {
            Issue.record("The answer ended with \(error)")
            return
        }
        #expect(context.contextSize > 0)
    }
}
