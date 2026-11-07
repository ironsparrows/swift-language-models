import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Tagged reasoning")
    struct TaggedReasoning {
        @Test func `a block the model wrote in its answer's text goes back at the start of that text`() throws {
            let reasoning = Transcript.Reasoning(
                metadata: [ReasoningOrigin.metadataKey: "test", LanguageModels.TaggedReasoning.metadataKey: "<think>Count.</think>\n"],
                segments: [text("Count.")])
            let entries: [Transcript.Entry] = [
                prompt(text("Hi")), .reasoning(reasoning), .response(Transcript.Response(assetIDs: [], segments: [text("Seven.")])),
            ]

            let assistant = messages(try ChatCompletionsSentRequest(generationRequest(entries)).body).last

            #expect(assistant?["content"] == "<think>Count.</think>\nSeven.")
        }
    }
}
