import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Sessions")
    struct Sessions {
        @Test(arguments: [(TranscriptErrorHandlingPolicy.revertTranscript, false), (.preserveTranscript, true)])
        func `a failure mid-stream leaves the transcript as the policy says`(policy: TranscriptErrorHandlingPolicy, keepsPrompt: Bool)
            async throws
        {
            let stub = HTTPStub(
                chatCompletionsEvents(textChunk("Earlier."), finishChunk()),
                chatCompletionsEvents(textChunk("Hel"), ["error": ["message": "Overloaded."]]))
            let session = LanguageModelSession(model: plainModel(stub))
            session.transcriptErrorHandlingPolicy = policy
            _ = try await session.respond(to: "Earlier?")
            let before = session.transcript

            await #expect(throws: RequestFailure<APIErrorBody>.self) {
                try await session.respond(to: "Hello?")
            }

            if keepsPrompt {
                #expect(promptText(session.transcript.dropFirst(before.count).first) == "Hello?")
            } else {
                #expect(session.transcript == before)
            }
        }

        @Test func `a second request while one is in flight throws concurrentRequests`() async throws {
            let stub = HTTPStub(openAnswer(textChunk("One")))
            let session = LanguageModelSession(model: plainModel(stub))

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
                chatCompletionsEvents(
                    toolCallChunk(id: "call_1", name: "lookUp", arguments: #"{"word":"egg"}"#),
                    finishChunk("tool_calls", usage: usage(prompt: 100, cached: 10, completion: 7, reasoning: 2))),
                chatCompletionsEvents(
                    textChunk("An oval."), finishChunk(usage: usage(prompt: 150, cached: 20, completion: 9, reasoning: 3))),
                chatCompletionsEvents(
                    textChunk("A grain."), finishChunk(usage: usage(prompt: 200, cached: 30, completion: 11, reasoning: 4))))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])

            _ = try await session.respond(to: "Define egg.")

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
            let stub = HTTPStub(
                chatCompletionsEvents(textChunk("First answer."), finishChunk()),
                chatCompletionsEvents(textChunk("Second answer."), finishChunk()))
            let profile = LanguageModelSession.Profile { Instructions("Be brief.") }
                .model(plainModel(stub))
                .historyTransform { entries in
                    entries.filter { entry in
                        if case .response = entry { false } else { true }
                    }
                }
            let session = LanguageModelSession(profile: profile)

            _ = try await session.respond(to: "One?")
            _ = try await session.respond(to: "Two?")

            let sent = try #require(stub.requests.last)
            #expect(
                messages(try JSONValue(json: sent.body)) == [
                    ["content": "Be brief.", "role": "system"], ["content": "One?", "role": "user"], ["content": "Two?", "role": "user"],
                ]
            )
            let keepsResponses = session.transcript.contains { entry in
                if case .response = entry { true } else { false }
            }
            #expect(keepsResponses)
        }

        @Test func `after a profile switches models, the other model's reasoning isn't sent`() async throws {
            let stub = HTTPStub(chatCompletionsEvents(textChunk("Yes."), finishChunk()))
            var chatCompletions = model(stub)
            chatCompletions.exchange.reasoningMember = "reasoning"
            let session = LanguageModelSession(profile: SwitchingProfile(chatCompletions: chatCompletions))

            let first = try await session.respond(to: "Define egg.")
            session.properties.usesChatCompletions = true
            let second = try await session.respond(to: "Sure?")

            #expect(first.content == "An oval.")
            #expect(second.content == "Yes.")
            #expect(!reasoningEntries(in: session.transcript).isEmpty)
            let assistant = try #require(try assistantMessages(stub, request: 0).first)
            #expect(assistant == ["content": "An oval.", "role": "assistant"])
        }

        @Test func `reasoning after the answer's text starts isn't shown`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(reasoningChunk("Think."), textChunk("Hi"), reasoningChunk(" Late."), finishChunk()))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hello")

            #expect(reasoningTexts(response.transcriptEntries) == ["Think."])
        }

        /// The usage of a chunk, with its cached and reasoning tokens.
        private func usage(prompt: Int, cached: Int, completion: Int, reasoning: Int) -> JSONValue {
            [
                "prompt_tokens": .integer(prompt), "completion_tokens": .integer(completion),
                "prompt_tokens_details": ["cached_tokens": .integer(cached)],
                "completion_tokens_details": ["reasoning_tokens": .integer(reasoning)],
            ]
        }
    }
}

extension SessionPropertyValues {
    /// Whether ``SwitchingProfile`` answers with its Chat Completions model.
    @SessionPropertyEntry fileprivate var usesChatCompletions = false
}

/// A profile that answers with ``ReasoningModel`` until the session switches it to a Chat Completions model.
private struct SwitchingProfile: LanguageModelSession.DynamicProfile {
    let chatCompletions: ChatCompletions.Model<ChatCompletionsTestExchange>

    @SessionProperty(\.usesChatCompletions) var usesChatCompletions

    var body: some DynamicProfile {
        if usesChatCompletions {
            Profile { Instructions("Be brief.") }.model(chatCompletions)
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
            await channel.send(.reasoning(entryID: "reasoning", action: .appendText("An egg is food.", tokenCount: 1)))
            await channel.send(.reasoning(entryID: "reasoning", action: .updateSignature(Data("opaque".utf8), tokenCount: 0)))
            await channel.send(.response(entryID: "response", action: .appendText("An oval.", tokenCount: 1)))
        }
    }

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.reasoning]) }

    var executorConfiguration: Executor.Configuration { Executor.Configuration() }
}
