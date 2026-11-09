// snippet.hide
import Foundation
import FoundationModels
import OpenAICompatibleLanguageModels

func level() async throws {
    // snippet.show
    // snippet.level
    // A model that always reasons, at the three efforts it takes.
    let model = OpenAICompatibleLanguageModel(
        OpenAICompatibleModel("openai/gpt-oss-20b", on: .groq, reasoning: .mandatory, efforts: [.high, .medium, .low]),
        auth: .apiKey { try await keyStore.groqKey() }
    )
    let session = LanguageModelSession(model: model)
    let response = try await session.respond(
        to: "Is 1,001 prime?",
        contextOptions: ContextOptions(reasoningLevel: .medium)
    )
    print("Reasoning tokens:", response.usage.output.reasoningTokenCount)
    // snippet.end
    // snippet.hide
}

func reading(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.reading
    let response = try await session.respond(to: "Is 1,001 prime?")
    for case .reasoning(let reasoning) in response.transcriptEntries {
        for case .text(let text) in reasoning.segments {
            print(text.content)
        }
    }
    // snippet.end
    // snippet.hide
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func groqKey() async throws -> String { "" }
}

let keyStore = KeyStore()
