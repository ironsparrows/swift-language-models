import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

/// Requests to an LM Studio server through its preset, for what only a server can show: its answers, its tools and its
/// guided answers. They run on the first model the server lists that isn't an embedding model, at its default address,
/// and only with `LIVE_LOCAL_SERVERS=1` in the environment.
@Suite(
    "Live: LM Studio",
    .tags(.live),
    .serialized,
    .requiresLocalServersRequested,
    .enabled("LM Studio isn't running at http://localhost:1234 with a model loaded") {
        await LocalServer.isReady(at: OpenAICompatibleProvider.lmStudio.url)
    },
    .timeLimit(.minutes(5))
)
struct LiveLMStudioTests {
    /// The first model the server lists, on the preset.
    static func model() async throws -> OpenAICompatibleLanguageModel {
        let id = try await LocalServer.firstModel(at: OpenAICompatibleProvider.lmStudio.url)
        return OpenAICompatibleLanguageModel(
            OpenAICompatibleModel(OpenAICompatibleModelID(rawValue: id), on: .lmStudio), auth: .unauthenticated)
    }

    @Test func `an answer names its model`() async throws {
        let response = try await LanguageModelSession(model: try await Self.model()).respond(
            to: "Name one color of the sea.", options: shortAnswer)

        let answer = try #require(lastAnswer(in: response.transcriptEntries))
        #expect(!response.content.isEmpty)
        #expect(answer.openAICompatible.model != nil)
        #expect(answer.providerMetadata.host == nil)
    }

    @Test func `a tool's output reaches the answer on two turns`() async throws {
        let session = try await answerTwoTurnsWithTool(try await Self.model())

        record(session.transcript, named: "transcript.txt")
    }

    @Test func `a guided answer decodes`() async throws {
        let response = try await LanguageModelSession(model: try await Self.model()).respond(
            to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 1_500))

        #expect(response.content.activities.count == 3)
    }
}
