import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Tagged reasoning")
    struct TaggedReasoning {
        @Test func `a block that a fallback wrote isn't sent back`() async throws {
            let stub = HTTPStub(
                events(from: "vendor/fallback", text("<think>Plan.</think>Hello!"), done()),
                events(text("Bye."), done())
            )
            let session = LanguageModelSession(model: model(stub, fallbacks: [fallback()]))

            _ = try await session.respond(to: "Say hello.")
            _ = try await session.respond(to: "Say bye.")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant == ["content": "Hello!", "role": "assistant"])
        }

        @Test func `a block goes back only in the answer's text when details go back beside it`() async throws {
            let detail: JSONValue = ["type": "reasoning.text", "text": "One.", "format": "openai-responses-v1"]
            let stub = HTTPStub(
                events(reasoning(detail), text("<think>Two.</think>Hello!"), done()),
                events(text("Bye."), done())
            )
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Say hello.")
            _ = try await session.respond(to: "Say bye.")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["content"] == "<think>Two.</think>Hello!")
            #expect(assistant["reasoning_details"] == [detail])
            #expect(assistant["reasoning"] == nil)
        }

        @Test func `a block goes back from a saved transcript whose entry names OpenRouter`() async throws {
            let stub = HTTPStub(events(text("Bye."), done()))
            let metadata = ["reasoningOrigin": "openrouter", "taggedReasoning": "<think>Plan.</think>"]
            let transcript = Transcript(entries: [
                .prompt(Transcript.Prompt(segments: [.text(.init(content: "Say hello."))])),
                .reasoning(Transcript.Reasoning(metadata: metadata, segments: [.text(.init(content: "Plan."))])),
                .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Hello!"))])),
            ])
            let session = LanguageModelSession(model: model(stub), transcript: transcript)

            _ = try await session.respond(to: "Say bye.")

            let assistant = try #require(try assistantMessages(stub).first)
            #expect(assistant == ["content": "<think>Plan.</think>Hello!", "role": "assistant"])
        }

        @Test func `streamed reasoning names OpenRouter as its origin`() async throws {
            let stub = HTTPStub(events(text("<think>Plan.</think>Hello!"), done()))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Say hello.")

            let reasoning = try #require(reasoningEntries(in: response.transcriptEntries).first)
            #expect(metadataString(reasoning.metadata, "reasoningOrigin") == "openrouter")
        }
    }
}
