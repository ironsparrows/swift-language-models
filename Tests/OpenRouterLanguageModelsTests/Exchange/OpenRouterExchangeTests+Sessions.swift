import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Sessions")
    struct Sessions {
        /// Each error policy, and whether it keeps the failed request's prompt.
        private static let policies = [(TranscriptErrorHandlingPolicy.revertTranscript, false), (.preserveTranscript, true)]

        @Test(arguments: policies)
        func `cancelling an answer mid-stream throws CancellationError, and the transcript follows the policy`(
            policy: TranscriptErrorHandlingPolicy,
            keepsPrompt: Bool
        ) async throws {
            let stub = HTTPStub(
                events(text("Earlier."), done()),
                unfinishedEvents(text("One"), text(" two")).keepingConnectionOpen(),
                events(text("Again."), done())
            )
            let session = LanguageModelSession(model: model(stub))
            session.transcriptErrorHandlingPolicy = policy
            var sentResponses = stub.sentResponses.makeAsyncIterator()
            _ = try await session.respond(to: "Earlier?")
            _ = await sentResponses.next()
            let before = session.transcript

            await #expect(throws: CancellationError.self) {
                try await withThrowingTaskGroup { group in
                    group.addTask { _ = try await session.respond(to: "Count.") }
                    // The stub has sent the answer's start and keeps the connection open, so the answer is in flight.
                    _ = await sentResponses.next()
                    group.cancelAll()
                    try await group.waitForAll()
                }
            }

            #expect(stub.requests.count == 2)
            if !keepsPrompt {
                #expect(session.transcript == before)
            } else {
                let added = session.transcript.dropFirst(before.count)
                guard case .prompt(let prompt)? = added.first else {
                    Issue.record("The prompt wasn't kept: \(session.transcript)")
                    return
                }
                #expect(plainText(prompt.segments) == "Count.")
            }
            #expect(try await session.respond(to: "Again?").content == "Again.")
        }

        @Test(arguments: policies)
        func `a failure mid-stream leaves the transcript as the policy says`(policy: TranscriptErrorHandlingPolicy, keepsPrompt: Bool)
            async throws
        {
            let streamError: JSONValue = ["error": ["code": 500, "message": "Provider crashed"]]
            let stub = HTTPStub(events(text("Earlier."), done()), events(text("Hel"), streamError))
            let session = LanguageModelSession(model: model(stub))
            session.transcriptErrorHandlingPolicy = policy
            _ = try await session.respond(to: "Earlier?")
            let before = session.transcript

            await #expect(throws: OpenRouterError.self) {
                try await session.respond(to: "Hello?")
            }

            if !keepsPrompt {
                #expect(session.transcript == before)
            } else {
                guard case .prompt(let prompt)? = session.transcript.dropFirst(before.count).first else {
                    Issue.record("The prompt wasn't kept: \(session.transcript)")
                    return
                }
                #expect(plainText(prompt.segments) == "Hello?")
            }
        }

        @Test func `a second request while one is in flight throws concurrentRequests`() async throws {
            let stub = HTTPStub(unfinishedEvents(text("One")).keepingConnectionOpen())
            let session = LanguageModelSession(model: model(stub))

            await withThrowingTaskGroup { group in
                group.addTask { _ = try await session.respond(to: "Count.") }
                for await _ in stub.sentResponses { break }

                await #expect(throws: LanguageModelSession.Error.concurrentRequests) {
                    try await session.respond(to: "Again?")
                }
                group.cancelAll()
            }
            #expect(stub.requests.count == 1)
        }

        @Test func `the session's usage adds up every round, including the one that asked for tools`() async throws {
            let stub = HTTPStub(
                events(
                    toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    done("tool_calls", prompt: 100, cached: 10, completion: 7, reasoning: 2)
                ),
                events(text("100 kcal."), done(prompt: 150, cached: 20, completion: 9, reasoning: 3)),
                events(text("Rice too."), done(prompt: 200, cached: 30, completion: 11, reasoning: 4))
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            _ = try await session.respond(to: "Calories in an egg?")

            #expect(session.usage.input.totalTokenCount == 250)
            #expect(session.usage.input.cachedTokenCount == 30)
            #expect(session.usage.output.totalTokenCount == 16)
            #expect(session.usage.output.reasoningTokenCount == 5)

            let second = try await session.respond(to: "And rice?")

            #expect(second.usage.input.totalTokenCount == 200)
            #expect(second.usage.output.totalTokenCount == 11)
            #expect(session.usage.input.totalTokenCount == 450)
            #expect(session.usage.input.cachedTokenCount == 60)
            #expect(session.usage.output.totalTokenCount == 27)
            #expect(session.usage.output.reasoningTokenCount == 9)
        }

        @Test func `a profile's history transform decides which entries are sent`() async throws {
            let stub = HTTPStub(events(text("First answer."), done()), events(text("Second answer."), done()))
            let profile = LanguageModelSession.Profile { Instructions("Be brief.") }
                .model(model(stub))
                .historyTransform { entries in
                    entries.filter { entry in
                        if case .response = entry { false } else { true }
                    }
                }
            let session = LanguageModelSession(profile: profile)

            _ = try await session.respond(to: "One?")
            _ = try await session.respond(to: "Two?")

            #expect(
                messages(try body(stub, 1)) == [
                    ["content": "Be brief.", "role": "system"], ["content": "One?", "role": "user"], ["content": "Two?", "role": "user"],
                ]
            )
            let keepsResponses = session.transcript.contains { entry in
                if case .response = entry { true } else { false }
            }
            #expect(keepsResponses)
        }

        @Test func `after a profile switches models, the other model's reasoning isn't sent`() async throws {
            let stub = HTTPStub(events(text("Yes."), done()))
            let session = LanguageModelSession(profile: SwitchingProfile(openRouter: model(stub)))

            let first = try await session.respond(to: "Calories in an egg?")
            session.properties.usesOpenRouter = true
            let second = try await session.respond(to: "Sure?")

            #expect(first.content == "About 70 kcal.")
            #expect(second.content == "Yes.")
            let hasReasoning = session.transcript.contains { entry in
                if case .reasoning = entry { true } else { false }
            }
            #expect(hasReasoning)
            let assistant = try #require(try assistantMessages(stub).first)
            #expect(assistant == ["content": "About 70 kcal.", "role": "assistant"])
        }
    }
}

extension SessionPropertyValues {
    /// Whether ``SwitchingProfile`` answers with its OpenRouter model.
    @SessionPropertyEntry fileprivate var usesOpenRouter = false
}

/// A profile that answers with ``ReasoningModel`` until the session switches it to an OpenRouter model.
private struct SwitchingProfile: LanguageModelSession.DynamicProfile {
    let openRouter: OpenRouterLanguageModel<Efforts.Unsupported>

    @SessionProperty(\.usesOpenRouter) var usesOpenRouter

    var body: some DynamicProfile {
        if usesOpenRouter {
            Profile { Instructions("Be brief.") }.model(openRouter)
        } else {
            Profile { Instructions("Be brief.") }.model(ReasoningModel())
        }
    }
}

/// A model from another provider, whose answers carry signed reasoning in its own format.
private struct ReasoningModel: LanguageModel {
    struct Executor: LanguageModelExecutor {
        struct Configuration: Hashable, Sendable {}

        init(configuration: Configuration) {}

        func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: ReasoningModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            await channel.send(.reasoning(entryID: "reasoning", action: .appendText("Eggs are light.", tokenCount: 1)))
            await channel.send(.reasoning(entryID: "reasoning", action: .updateSignature(Data("opaque".utf8), tokenCount: 0)))
            await channel.send(.response(entryID: "response", action: .appendText("About 70 kcal.", tokenCount: 1)))
        }
    }

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.reasoning]) }

    var executorConfiguration: Executor.Configuration { Executor.Configuration() }
}
