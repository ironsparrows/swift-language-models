import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite("Text")
    struct Text {
        @Test func `a cheap model answers with its usage, cost and host`() async throws {
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel)

            let response = try await session.respond(to: "Reply with the single word: hello", options: LiveTests.short)

            record(response, named: "response.txt")
            #expect(response.content.localizedCaseInsensitiveContains("hello"))
            #expect(response.usage.input.totalTokenCount > 0)
            #expect(response.usage.output.totalTokenCount > 0)
            #expect((response.usage.openRouter.cost ?? 0) > 0)
            let answer = try #require(lastAnswer(in: response.transcriptEntries))
            #expect(answer.openRouter.model?.rawValue.hasPrefix("openai/gpt-4.1-nano") == true)
            #expect(answer.openRouter.provider?.rawValue != nil)
            #expect(answer.openRouter.responseID?.hasPrefix("gen-") == true)
            #expect(answer.openRouter.finishReason?.rawValue == "stop")
        }

        @Test func `a streamed answer grows with each snapshot`() async throws {
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel)

            var snapshots: [String] = []
            let stream = session.streamResponse(
                to: "Count from 1 to 10, separated by spaces.",
                options: GenerationOptions(maximumResponseTokens: 64)
            )
            for try await snapshot in stream {
                snapshots.append(snapshot.content)
            }

            let answer = try #require(snapshots.last)
            #expect(answer.contains("10"))
            #expect(snapshots.allSatisfy { answer.hasPrefix($0) })
        }

        @Test func `a session remembers its earlier turns`() async throws {
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel)

            _ = try await session.respond(to: "My favorite color is teal. Reply with OK.", options: LiveTests.short)
            let response = try await session.respond(to: "What is my favorite color? Reply with one word.", options: LiveTests.short)

            #expect(response.content.localizedCaseInsensitiveContains("teal"))
        }

        @Test func `an answer cut short by the token limit keeps its text`() async throws {
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel)

            let response = try await session.respond(to: "Count from 1 to 200, separated by spaces.", options: LiveTests.short)

            #expect(!response.content.isEmpty)
            #expect(response.usage.output.totalTokenCount <= 16)
            let answer = try #require(lastAnswer(in: response.transcriptEntries))
            #expect(answer.openRouter.finishReason?.rawValue == "length")
        }

        /// Foundation Models ends a cancelled stream without throwing, so only the stop and the next answer count.
        @Test func `a cancelled stream stops at once and the session answers again`() async throws {
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel)
            let (snapshots, snapshotArrived) = AsyncStream.makeStream(of: Void.self)

            let streaming = Task {
                defer { snapshotArrived.finish() }
                let stream = session.streamResponse(
                    to: "Count from 1 to 300, separated by spaces.",
                    options: GenerationOptions(maximumResponseTokens: 1_000)
                )
                for try await _ in stream {
                    snapshotArrived.yield()
                }
            }
            var count = 0
            for await _ in snapshots {
                count += 1
                if count == 3 { break }
            }
            let cancelledAt = ContinuousClock.now
            streaming.cancel()
            let result = await streaming.result
            let wait = ContinuousClock.now - cancelledAt

            record(wait, named: "wait.txt")
            if case .failure(let error) = result, !(error is CancellationError) { throw error }
            #expect(count == 3)
            #expect(wait < .seconds(2))
            // While many sessions run at once, Foundation Models may fail the turn after a cancelled stream itself, before
            // the model's executor sends anything.
            try await withKnownIssue("Foundation Models may fail the next turn after a cancel itself.", isIntermittent: true) {
                let again = try await session.respond(to: "Reply with the single word: done", options: LiveTests.short)
                #expect(again.content.localizedCaseInsensitiveContains("done"))
            } matching: { issue in
                issue.error.map { "\($0)".contains("empty response") } == true
            }
        }

        @Test func `a low verbosity gives a shorter answer than a high one`() async throws {
            func answer(_ verbosity: OpenRouterOptions.Verbosity) async throws -> String {
                let model = LiveModel(.openaiGpt5Nano).languageModel(options: OpenRouterOptions(verbosity: verbosity))
                let response = try await LanguageModelSession(model: model).respond(
                    to: "Why is the sky blue?",
                    options: GenerationOptions(maximumResponseTokens: 4_000),
                    contextOptions: ContextOptions(reasoningLevel: .minimal)
                )
                record(response.content, named: "\(verbosity.rawValue).txt")
                let entry = try #require(lastAnswer(in: response.transcriptEntries))
                #expect(entry.openRouter.finishReason?.rawValue == "stop")
                return response.content
            }

            let low = try await answer(.low)
            let high = try await answer(.high)

            // Verbosity is a hint, so the high answer only has to be clearly longer.
            #expect(Double(high.count) >= 1.5 * Double(low.count))
        }
    }
}
