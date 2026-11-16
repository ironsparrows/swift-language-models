// snippet.hide
import FoundationModels
import OpenRouterLanguageModels

func capabilities() {
    // snippet.show
    // snippet.capabilities
    let model = OpenRouterLanguageModel(
        .anthropicClaudeHaiku5_5,
        fallbacks: .openaiGpt5_4Mini,
        auth: .apiKey { try await keyStore.openRouterKey() }
    )
    print(model.capabilities.contains(.toolCalling))  // Every model lists `tools`
    print(model.capabilities.contains(.guidedGeneration))  // Every model lists `structured_outputs`
    // snippet.end
    // snippet.hide
}

// snippet.show
// snippet.feature
@Generable
struct Dinner {
    @Guide(description: "The dish's name.")
    var name: String

    @Guide(description: "The minutes it takes to cook.", .range(5...120))
    var minutes: Int
}

/// Finds recipes in the app's own collection.
struct RecipeSearch: Tool {
    let name = "searchRecipes"
    let description = "Finds recipes that use an ingredient."

    @Generable
    struct Arguments {
        @Guide(description: "An ingredient the recipe uses.")
        var ingredient: String
    }

    func call(arguments: Arguments) async throws -> String {
        "Lentil soup with carrots and cumin, 30 minutes."
    }
}

func suggestDinner(using model: some LanguageModel) async throws -> Dinner {
    let session = LanguageModelSession(model: model, tools: [RecipeSearch()], instructions: "Suggest one dinner.")
    let response = try await session.respond(to: "Something with lentils.", generating: Dinner.self)

    for case .toolCalls(let calls) in response.transcriptEntries {
        print(calls.map(\.toolName), "from", calls.openRouter.model?.rawValue ?? "an unnamed model")
    }
    return response.content
}
// snippet.end

// snippet.hide
func required(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.required
    do {
        let response = try await session.respond(
            to: "Find a recipe with lentils.",
            options: GenerationOptions(toolCallingMode: .required)
        )
        print(response.content)
    } catch LanguageModelError.unsupportedCapability(let unsupported) {
        print("A model can't be made to call a tool:", unsupported.debugDescription)
    }
    // snippet.end
    // snippet.hide
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func openRouterKey() async throws -> String { "" }
}

let keyStore = KeyStore()
