import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite(
        "Free models",
        .enabled(
            if: ProcessInfo.processInfo.environment["LIVE_FREE"]?.isEmpty == false,
            "Set LIVE_FREE to spend the account's daily free requests"
        )
    )
    struct FreeModels {
        /// A variant on a free model's id makes an id such as `nvidia/nemotron-3.5-lightning:free:nitro`.
        @Test(arguments: [nil, OpenRouterRouting.Variant.nitro])
        func `a free model answers at no cost, with or without a variant`(variant: OpenRouterRouting.Variant?) async throws {
            let model = LiveModel(.nvidiaNemotron3_5LightningFree).languageModel(routing: OpenRouterRouting(variant: variant))
            let session = LanguageModelSession(model: model)

            do {
                let response = try await session.respond(
                    to: "Reply with the single word: hello",
                    options: GenerationOptions(maximumResponseTokens: 64),
                    contextOptions: ContextOptions(reasoningLevel: .off)
                )
                record(answerMetadata(response), named: "metadata.txt")
                #expect(!response.content.isEmpty)
                #expect(response.usage.openRouter.cost == 0)
                let answer = try #require(lastAnswer(in: response.transcriptEntries))
                #expect(answer.openRouter.model?.rawValue.hasPrefix("nvidia/nemotron-3.5-lightning") == true)
            } catch let error as LanguageModelError {
                guard case .rateLimited = error else { throw error }
                record(error, named: "error.txt")
                try Test.cancel("The free model is rate limited: \(error)")
            }
        }
    }
}
