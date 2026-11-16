// snippet.hide
import FoundationModels
import OpenRouterLanguageModels

func fallbacks() async throws {
    // snippet.show
    // snippet.fallbacks
    let model = OpenRouterLanguageModel(
        .anthropicClaudeSonnet4_6,
        fallbacks: .openaiGpt5_4Nano, .googleGemini3_1FlashLite,
        routing: OpenRouterRouting(dataCollection: .deny, zeroDataRetention: .required, sort: .price),
        auth: .apiKey { try await keyStore.openRouterKey() }
    )
    let response = try await LanguageModelSession(model: model).respond(to: "Plan a picnic for Saturday.")

    if case .response(let answer)? = response.transcriptEntries.last, let answeredBy = answer.openRouter.model {
        print("\(answeredBy) answered.")
    }
    // snippet.end
    // snippet.hide
}

func runtimeFallbacks(savedIDs: [OpenRouterModelID]) {
    // snippet.show
    // snippet.runtime
    var model = OpenRouterLanguageModel(.anthropicClaudeSonnet4_6, auth: .apiKey { try await keyStore.openRouterKey() })
    model.fallbacks = savedIDs.compactMap { OpenRouterModel(catalogID: $0) }
    // snippet.end
    // snippet.hide
    _ = model
}

func routing() {
    // snippet.show
    // snippet.routing
    let model = OpenRouterLanguageModel(
        .anthropicClaudeSonnet4_6,
        routing: OpenRouterRouting(
            order: ["anthropic", "amazon-bedrock"],
            fallbackProviders: .disallowed,
            maximumPrice: OpenRouterRouting.MaximumPrice(prompt: 5, completion: 20)  // US dollars per million tokens
        ),
        auth: .apiKey { try await keyStore.openRouterKey() }
    )
    // snippet.end
    // snippet.hide
    _ = model
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func openRouterKey() async throws -> String { "" }
}

let keyStore = KeyStore()
