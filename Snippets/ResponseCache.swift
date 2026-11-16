// snippet.hide
import FoundationModels
import OpenRouterLanguageModels

func responseCache() async throws {
    // snippet.show
    // snippet.cache
    var model = OpenRouterLanguageModel(.openaiGpt5_4Mini, auth: .apiKey { try await keyStore.openRouterKey() })
    model.responseCache = OpenRouterResponseCache(timeToLive: .seconds(600))

    let session = LanguageModelSession(model: model, instructions: "Suggest one recipe.")
    let response = try await session.respond(to: "Something with lentils.")

    if case .response(let answer)? = response.transcriptEntries.last, answer.openRouter.responseCacheStatus == .hit {
        print("A kept answer, at no cost.")
    }
    // snippet.end
    // snippet.hide

    // snippet.show
    // snippet.refresh
    var refreshing = model
    refreshing.responseCache?.refreshes = true
    // snippet.end
    // snippet.hide
    _ = refreshing
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func openRouterKey() async throws -> String { "" }
}

let keyStore = KeyStore()
