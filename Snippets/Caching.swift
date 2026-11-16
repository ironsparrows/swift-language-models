// snippet.hide
import FoundationModels
import OpenRouterLanguageModels

func usage(handbook: String) async throws {
    // snippet.show
    // snippet.usage
    let model = OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey { try await keyStore.openRouterKey() })
    let session = LanguageModelSession(model: model, instructions: handbook)
    let response = try await session.respond(to: "What's the refund policy?")

    print("Read from the cache:", response.usage.input.cachedTokenCount)
    if let written = response.usage.openRouter.cacheWriteTokenCount {
        print("Written to the cache:", written)
    }
    // snippet.end
    // snippet.hide
}

func oneHour() {
    // snippet.show
    // snippet.oneHour
    let model = OpenRouterLanguageModel(
        .anthropicClaudeHaiku5_5,
        cacheControl: .automatic(timeToLive: .oneHour),
        auth: .apiKey { try await keyStore.openRouterKey() }
    )
    // snippet.end
    // snippet.hide
    _ = model
}

func always() {
    // snippet.show
    // snippet.always
    let model = OpenRouterLanguageModel(
        .anthropicClaudeHaiku5_5,
        fallbacks: .openaiGpt5_4Mini,
        cacheControl: .always,
        auth: .apiKey { try await keyStore.openRouterKey() }
    )
    // snippet.end
    // snippet.hide
    _ = model
}

func unmarked() {
    // snippet.show
    // snippet.unmarked
    var model = OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey { try await keyStore.openRouterKey() })
    model.cacheControl = nil
    // snippet.end
    // snippet.hide
    _ = model
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func openRouterKey() async throws -> String { "" }
}

let keyStore = KeyStore()
