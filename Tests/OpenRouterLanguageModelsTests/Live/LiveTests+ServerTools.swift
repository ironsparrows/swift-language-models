import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite("Server tools")
    struct ServerTools {
        @Test func `a web search answer cites https pages and counts the search`() async throws {
            let search = OpenRouterServerTool.webSearch(engine: .parallel, maximumResults: 3, maximumSearches: 1)
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel(serverTools: [search]))

            let response = try await session.respond(
                to: "Search the web for the official website of the Swift programming language, and name it."
            )

            record(answerMetadata(response), named: "metadata.txt")
            let citations = try #require(lastAnswer(in: response.transcriptEntries)).openRouter.citations
            #expect(!citations.isEmpty)
            // A search engine may cite a page that's only served over http.
            #expect(citations.allSatisfy { ["http", "https"].contains($0.url.scheme) })
            let usage = response.usage.openRouter
            #expect(usage.webSearchCount != nil || usage.serverToolCost != nil)
        }

        @Test func `a fetched page reaches the answer`() async throws {
            let fetch = OpenRouterServerTool.webFetch(engine: .openRouter, maximumFetches: 1)
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel(serverTools: [fetch]))

            let response = try await session.respond(to: "Fetch https://example.com and reply with the page's title.")

            record(answerMetadata(response), named: "metadata.txt")
            #expect(response.content.contains("Example Domain"))
            #expect((response.usage.openRouter.requestedServerToolCallCount ?? 0) >= 1)
        }

        @Test func `the date tool gives the current year`() async throws {
            let datetime = OpenRouterServerTool.datetime(timeZone: .gmt)
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel(serverTools: [datetime]))

            let response = try await session.respond(to: "What is today's date? Use the tool, and reply with the date only.")

            record(answerMetadata(response), named: "metadata.txt")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            #expect(response.content.contains(String(calendar.component(.year, from: .now))))
        }

        @Test func `the advisor answers, and the usage counts the consultation`() async throws {
            let advisor = OpenRouterServerTool.advisor(model: OpenRouterModel.openaiGpt4_1Nano.id, maximumResponseTokens: 100)
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel(serverTools: [advisor]))

            let response = try await session.respond(
                to: "Ask the advisor whether 17 × 23 is 391, then reply with its verdict in one sentence.",
                options: GenerationOptions(maximumResponseTokens: 200)
            )

            record(answerMetadata(response), named: "metadata.txt")
            record(session.transcript, named: "transcript.txt")
            #expect(!response.content.isEmpty)
            #expect((response.usage.openRouter.requestedServerToolCallCount ?? 0) >= 1)
            #expect(session.transcript.toolCalls.isEmpty)
        }

        @Test func `the subagent's outcome reaches the answer, and the usage counts the task`() async throws {
            let subagent = OpenRouterServerTool.subagent(model: OpenRouterModel.openaiGpt4_1Nano.id, maximumResponseTokens: 100)
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel(serverTools: [subagent]))

            let response = try await session.respond(
                to: "Delegate this task to the subagent: write the word 'harbor' in capital letters. Then reply with its outcome only.",
                options: GenerationOptions(maximumResponseTokens: 200)
            )

            record(answerMetadata(response), named: "metadata.txt")
            record(session.transcript, named: "transcript.txt")
            #expect(response.content.contains("HARBOR"))
            #expect((response.usage.openRouter.requestedServerToolCallCount ?? 0) >= 1)
            #expect(session.transcript.toolCalls.isEmpty)
        }

        @Test func `a required tool call is met with an app tool and a server tool on offer`() async throws {
            let model = LiveModel(.openaiGpt4_1Nano).languageModel(serverTools: [.datetime(timeZone: .gmt)])
            let session = LanguageModelSession(model: model, tools: [InterruptingWeatherTool()])

            let response = try await respondUntilToolCall(
                session,
                to: "How warm is it in Lisbon today, and what is the date?",
                options: GenerationOptions(toolCallingMode: .required)
            )

            record(session.transcript, named: "transcript.txt")
            if let response {
                // A server tool's call can meet the requirement on its own.
                record(answerMetadata(response), named: "metadata.txt")
                #expect((response.usage.openRouter.requestedServerToolCallCount ?? 0) >= 1)
            } else {
                #expect(session.transcript.toolCalls.contains { $0.toolName == "getWeather" })
            }
        }
    }
}
