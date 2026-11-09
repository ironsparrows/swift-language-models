// snippet.hide
import Foundation
import FoundationModels
import OpenAICompatibleLanguageModels

// snippet.show
// snippet.feature
@Generable
struct Dinner {
    @Guide(description: "The dish's name.")
    var name: String

    @Guide(description: "The minutes it takes to cook.", .range(5...120))
    var minutes: Int
}

func suggestDinner(using model: OpenAICompatibleLanguageModel) async throws -> Dinner {
    let session = LanguageModelSession(model: model, tools: [RecipeSearch()], instructions: "Suggest one dinner.")
    return try await session.respond(to: "Something with lentils.", generating: Dinner.self).content
}
// snippet.end

// snippet.hide
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

func refused() async throws {
    // snippet.show
    // snippet.refused
    // Groq refuses a schema in a request that also sends tools, so the request is refused before it's sent.
    let model = OpenAICompatibleLanguageModel(
        OpenAICompatibleModel("openai/gpt-oss-20b", on: .groq, reasoning: .mandatory, efforts: [.high, .medium, .low]),
        auth: .apiKey { try await keyStore.groqKey() }
    )
    let session = LanguageModelSession(model: model, tools: [RecipeSearch()])
    do {
        _ = try await session.respond(to: "Something with lentils.", generating: Dinner.self)
    } catch LanguageModelError.unsupportedCapability(let unsupported) {
        print("Not on this provider:", unsupported.debugDescription)
    }
    // snippet.end
    // snippet.hide
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func groqKey() async throws -> String { "" }
}

let keyStore = KeyStore()
