// snippet.hide
import FoundationModels
import OpenRouterLanguageModels

func webSearch() async throws {
    // snippet.show
    // snippet.search
    let model = OpenRouterLanguageModel(
        .openaiGpt5_4Mini,
        serverTools: [.webSearch(maximumResults: 5, maximumSearches: 3), .webFetch(), .datetime(timeZone: .current)],
        auth: .apiKey { try await keyStore.openRouterKey() }
    )
    let response = try await LanguageModelSession(model: model).respond(to: "What's on in Athens this weekend?")

    for case .response(let answer) in response.transcriptEntries {
        for citation in answer.openRouter.citations {
            print(citation.title ?? "Untitled", citation.url)
        }
    }
    // snippet.end
    // snippet.hide
}

func searchOptions() {
    // snippet.show
    // snippet.options
    let model = OpenRouterLanguageModel(
        .openaiGpt5_4Mini,
        serverTools: [
            .webSearch(engine: .exa, searchContextSize: .high, allowedDomains: ["swift.org", "developer.apple.com"]),
            .webFetch(engine: .openRouter, excludedDomains: ["example.com"]),
        ],
        auth: .apiKey { try await keyStore.openRouterKey() }
    )
    // snippet.end
    // snippet.hide
    _ = model
}

func otherModels() {
    // snippet.show
    // snippet.models
    let model = OpenRouterLanguageModel(
        .openaiGpt5_4Mini,
        serverTools: [
            .advisor(model: "~anthropic/claude-opus-latest", forwardsTranscript: true),
            .subagent(model: "~anthropic/claude-haiku-latest", tools: [.webSearch()]),
        ],
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
