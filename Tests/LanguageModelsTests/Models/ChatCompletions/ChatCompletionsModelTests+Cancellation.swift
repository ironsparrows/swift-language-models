import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Cancellation")
    struct Cancellation {
        /// Each error policy, and whether it keeps the failed request's prompt.
        private static let policies = [(TranscriptErrorHandlingPolicy.revertTranscript, false), (.preserveTranscript, true)]

        @Test(arguments: policies)
        func `cancelling an answer mid-stream throws CancellationError, and the transcript follows the policy`(
            policy: TranscriptErrorHandlingPolicy,
            keepsPrompt: Bool
        ) async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(textChunk("Earlier."), finishChunk()),
                openAnswer(textChunk("One"), textChunk(" two")),
                chatCompletionsEvents(textChunk("Again."), finishChunk()))
            let session = LanguageModelSession(model: plainModel(stub))
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
            if keepsPrompt {
                #expect(promptText(session.transcript.dropFirst(before.count).first) == "Count.")
            } else {
                #expect(session.transcript == before)
            }
            #expect(try await session.respond(to: "Again?").content == "Again.")
        }
    }
}
