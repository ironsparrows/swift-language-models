// snippet.hide
import Foundation
import FoundationModels
import OpenAICompatibleLanguageModels

func cacheKey() {
    // snippet.show
    // snippet.cacheKey
    // Each session's requests share a key, so xAI serves them from the same cache.
    let model = OpenAICompatibleLanguageModel(
        OpenAICompatibleModel("grok-4.3", on: .xAI),
        options: OpenAICompatibleOptions(cacheKey: .session),
        auth: .apiKey { try await keyStore.xAIKey() }
    )
    // snippet.end
    // snippet.hide
    _ = model
}

func usage(model: OpenAICompatibleLanguageModel, handbook: String) async throws {
    // snippet.show
    // snippet.usage
    let session = LanguageModelSession(model: model, instructions: handbook)
    let response = try await session.respond(to: "What's the refund policy?")

    print("Input tokens:", response.usage.input.totalTokenCount)
    print("Read from the cache:", response.usage.input.cachedTokenCount)
    // snippet.end
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func xAIKey() async throws -> String { "" }
}

let keyStore = KeyStore()
