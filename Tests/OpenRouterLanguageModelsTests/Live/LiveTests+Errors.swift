import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite("Errors")
    struct Errors {
        @Test func `a rejected key throws OpenRouter's 401`() async throws {
            let model = OpenRouterLanguageModel(.openaiGpt4_1Nano, auth: .apiKey { "sk-or-v1-not-a-key" })

            let error = try await #require(throws: OpenRouterError.self) {
                try await LanguageModelSession(model: model).respond(to: "Hi", options: LiveTests.short)
            }

            record(error, named: "error.txt")
            #expect(error.status == 401)
        }

        @Test func `an unknown model is rejected`() async throws {
            let details = OpenRouterModel<ContextOptions.ReasoningLevel>(
                id: "swift-language-models/no-such-model",
                displayName: "No such model",
                supportedParameters: []
            )
            let model = LiveModel(details).languageModel

            let error = try await #require(throws: OpenRouterError.self) {
                try await LanguageModelSession(model: model).respond(to: "Hi")
            }

            record(error, named: "error.txt")
            #expect([400, 404].contains(error.status))
        }

        @Test func `a prompt longer than the context throws with both sizes`() async throws {
            let session = LanguageModelSession(model: LiveModel(.microsoftPhi4).languageModel)

            let error = try await #require(throws: LanguageModelError.self) {
                try await session.respond(to: String(repeating: "word ", count: 20_000), options: LiveTests.short)
            }

            record(error, named: "error.txt")
            guard case .contextSizeExceeded(let context) = error else {
                Issue.record("Expected the context size to be exceeded, got \(error)")
                return
            }
            record(context.metadata, named: "metadata.txt")
            #expect(context.contextSize == 16_384)
            #expect(context.tokenCount > 16_384)
            #expect(context.metadata["status"] as? Int != nil)
        }

        @Test func `a request that gets no data in time throws Foundation Models' timeout`() async throws {
            let key = APIKeyTrait.current ?? ""
            let model = OpenRouterLanguageModel(
                .openaiGpt4_1Nano, configuration: OpenRouterConfiguration(idleTimeout: .milliseconds(1), retries: .disabled),
                auth: .apiKey { key })

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model).respond(to: "Hi", options: LiveTests.short)
            }

            record(error, named: "error.txt")
            guard case .timeout = error else {
                Issue.record("Expected a timeout, got \(error)")
                return
            }
        }
    }
}
