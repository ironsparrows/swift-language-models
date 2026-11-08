import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAILanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite("Text")
    struct Text {
        @Test(arguments: [LiveModel.nano, .luna, .mini])
        func `an answer comes with its usage, model, ids, tier and finish reason`(model: LiveModel) async throws {
            let session = LanguageModelSession(model: try model.languageModel())

            let response = try await session.respond(to: "Say hello.", options: LiveTests.short, contextOptions: model.quickContext)

            #expect(response.content.localizedCaseInsensitiveContains("hello"))
            #expect(response.usage.input.totalTokenCount > 0)
            #expect(response.usage.output.totalTokenCount > 0)
            let answer = try #require(lastAnswer(in: response.transcriptEntries))
            record(answer.metadata, named: "metadata.txt")
            #expect(answer.openAI.model?.rawValue.hasPrefix(model.id.rawValue) == true)
            #expect(answer.openAI.responseID?.hasPrefix("resp_") == true)
            #expect(answer.openAI.requestID?.isEmpty == false)
            #expect(answer.openAI.serviceTier != nil)
            #expect(answer.openAI.finishReason == .stop)
        }

        @Test func `a streamed answer grows, and ends as the answer`() async throws {
            let session = LanguageModelSession(model: try LiveModel.nano.languageModel())
            var snapshots: [String] = []

            let stream = session.streamResponse(
                to: "Count from 1 to 10, separated by spaces.", options: GenerationOptions(maximumResponseTokens: 512),
                contextOptions: LiveModel.nano.quickContext)
            for try await snapshot in stream { snapshots.append(snapshot.content) }
            let answer = try await stream.collect().content

            #expect(answer.contains("10"))
            #expect(snapshots.last == answer)
            #expect(snapshots.allSatisfy { answer.hasPrefix($0) })
        }

        @Test(arguments: [LiveModel.nano, .mini])
        func `instructions apply, as a developer message or a system message`(model: LiveModel) async throws {
            let session = LanguageModelSession(
                model: try model.languageModel(), instructions: "Whatever the user asks, reply with only the word PINEAPPLE.")

            let response = try await session.respond(to: "What is 2 + 2?", options: LiveTests.short, contextOptions: model.quickContext)

            #expect(response.content.localizedCaseInsensitiveContains("pineapple"))
        }

        @Test func `a session remembers earlier turns`() async throws {
            let session = LanguageModelSession(model: try LiveModel.nano.languageModel())

            _ = try await session.respond(
                to: "My favorite color is teal. Reply with OK.", options: LiveTests.short, contextOptions: LiveModel.nano.quickContext)
            let response = try await session.respond(
                to: "What is my favorite color? One word.", options: LiveTests.short, contextOptions: LiveModel.nano.quickContext)

            #expect(response.content.localizedCaseInsensitiveContains("teal"))
        }

        @Test func `a token limit ends the answer with length`() async throws {
            let session = LanguageModelSession(model: try LiveModel.luna.languageModel())

            let response = try await session.respond(
                to: "Write a long story about a lighthouse.", options: GenerationOptions(maximumResponseTokens: 16),
                contextOptions: LiveModel.luna.quickContext)

            #expect(!response.content.isEmpty)
            #expect(response.usage.output.totalTokenCount <= 16)
            #expect(lastAnswer(in: response.transcriptEntries)?.openAI.finishReason == .length)
        }

        @Test func `a cancelled stream stops, and the session answers the next turn`() async throws {
            let session = LanguageModelSession(model: try LiveModel.nano.languageModel())
            // The stream is cancelled once its answer starts, however long the request takes to reach OpenAI.
            let (started, start) = AsyncStream<Void>.makeStream()
            let task = Task {
                defer { start.finish() }
                for try await _ in session.streamResponse(
                    to: "Write the numbers from 1 to 300, one per line.", options: GenerationOptions(maximumResponseTokens: 1_000),
                    contextOptions: LiveModel.nano.quickContext)
                {
                    start.yield()
                }
            }
            for await _ in started { break }
            task.cancel()

            if case .failure(let error) = await task.result { #expect(error is CancellationError) }
            // While many sessions run at once, Foundation Models may fail the turn after a cancelled stream itself,
            // before the model's executor sends anything.
            try await withKnownIssue("Foundation Models may fail the next turn after a cancel itself.", isIntermittent: true) {
                let response = try await session.respond(
                    to: "Reply with the word done.", options: GenerationOptions(maximumResponseTokens: 2_000),
                    contextOptions: LiveModel.nano.quickContext)
                #expect(response.content.localizedCaseInsensitiveContains("done"))
            } matching: { issue in
                issue.error.map { "\($0)".contains("empty response") } == true
            }
        }

        @Test(arguments: [LiveModel.mini, .gpt41Mini, .o3])
        func `a model older than GPT-5 refuses a verbosity other than medium, with an error that names it`(
            model: LiveModel
        ) async throws {
            let session = LanguageModelSession(model: try model.languageModel(options: OpenAIOptions(verbosity: .low)))

            let error = try await #require(throws: OpenAIError.self) {
                _ = try await session.respond(
                    to: "Say hello in one word.", options: GenerationOptions(maximumResponseTokens: 2_000),
                    contextOptions: model.quickContext)
            }

            record(error, named: "error.txt")
            #expect(error.status == 400)
            #expect(error.parameter == "text.verbosity")
        }

        @Test func `a low verbosity gives a shorter answer than a high one`() async throws {
            func answer(_ verbosity: OpenAIOptions.Verbosity) async throws -> String {
                let session = LanguageModelSession(model: try LiveModel.nano.languageModel(options: OpenAIOptions(verbosity: verbosity)))
                return try await session.respond(
                    to: "Explain why the sky is blue.", options: GenerationOptions(maximumResponseTokens: 4_000),
                    contextOptions: LiveModel.nano.quickContext
                ).content
            }

            let low = try await answer(.low)
            let high = try await answer(.high)

            record(low.count, named: "low.txt")
            record(high.count, named: "high.txt")
            #expect(Double(high.count) >= Double(low.count) * 1.5)
        }

        @Test func `the flex tier serves the answer and says so`() async throws {
            let session = LanguageModelSession(model: try LiveModel.nano.languageModel(options: OpenAIOptions(serviceTier: .flex)))

            let response = try await session.respond(
                to: "Say hello.", options: LiveTests.short, contextOptions: LiveModel.nano.quickContext)

            #expect(lastAnswer(in: response.transcriptEntries)?.openAI.serviceTier == .flex)
        }

        @Test func `a key with OpenAI's own base URL works as the default does`() async throws {
            let key = APIKeyTrait.current ?? ""
            let url = try #require(URL(string: "https://api.openai.com/v1/"))
            let session = LanguageModelSession(model: try LiveModel.nano.languageModel(auth: .apiKey(baseURL: url) { key }))

            let response = try await session.respond(
                to: "Say hello.", options: LiveTests.short, contextOptions: LiveModel.nano.quickContext)

            #expect(response.content.localizedCaseInsensitiveContains("hello"))
        }

        @Test(arguments: [LiveModel.luna, .mini])
        func `a temperature the model takes only without reasoning is left out rather than rejected`(model: LiveModel) async throws {
            let session = LanguageModelSession(model: try model.languageModel())

            let response = try await session.respond(
                to: "Say hello.", options: GenerationOptions(temperature: 0.5, maximumResponseTokens: 64),
                contextOptions: ContextOptions(reasoningLevel: model.quickLevel == nil ? nil : .light))

            #expect(response.content.localizedCaseInsensitiveContains("hello"))
        }
    }
}
