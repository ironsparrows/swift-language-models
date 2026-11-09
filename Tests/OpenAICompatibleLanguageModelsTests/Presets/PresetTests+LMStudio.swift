import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    /// LM Studio's preset, written from LM Studio's documentation and what its users report, since none was captured.
    @Suite("LM Studio")
    struct LMStudio {
        @Test func `LM Studio's models take the defaults of a provider described by its name and URL`() throws {
            let details = OpenAICompatibleModel("qwen/qwen3-8b", on: .lmStudio)

            #expect(OpenAICompatibleProvider.lmStudio.name == "LM Studio")
            #expect(OpenAICompatibleProvider.lmStudio.url == URL(string: "http://localhost:1234/v1"))
            #expect(OpenAICompatibleProvider.lmStudio.format == .chatCompletions)
            #expect(OpenAICompatibleProvider.lmStudio.keyHeader == .bearer)
            #expect(details.reasoning == .offByDefault)
            #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["xhigh", "high", "medium", "low", "minimal", "none"])
            #expect(details.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
            #expect(OpenAICompatibleLanguageModel(details, auth: .unauthenticated).configuration == OpenAICompatibleConfiguration())
        }

        @Test func `a request leaves out metadata, which LM Studio's documentation doesn't list`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: .lmStudio.at(stub.baseURL))).respond(
                to: "Hi", options: GenerationOptions(maximumResponseTokens: 50), contextOptions: ContextOptions(reasoningLevel: .light),
                metadata: ["team": "meals"])

            assertInlineSnapshot(of: stub.requests[0].body, as: .memberLines) {
                """
                {
                  "model": "test-model",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Hi"
                    }
                  ],
                  "stream": true,
                  "stream_options": {
                    "include_usage": true
                  },
                  "reasoning_effort": "low",
                  "max_tokens": 50
                }
                """
            }
        }
    }
}
