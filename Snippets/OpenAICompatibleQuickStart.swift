// snippet.hide
import Foundation
// snippet.show
// snippet.session
import FoundationModels
import OpenAICompatibleLanguageModels

func planMonday() async throws -> String {
    // snippet.hide
    // swift-format-ignore: NeverForceUnwrap
    // snippet.show
    let provider = OpenAICompatibleProvider(name: "Gateway", url: URL(string: "https://llm.example.com/v1")!)
    let model = OpenAICompatibleLanguageModel(
        OpenAICompatibleModel("my-model", on: provider),
        auth: .apiKey { try await keyStore.gatewayKey() }
    )
    let session = LanguageModelSession(model: model, instructions: "Plan the week's meals.")
    let plan = try await session.respond(to: "Something light for Monday.")
    return plan.content
}
// snippet.end

// snippet.hide
func localServer() {
    // snippet.show
    // snippet.localServer
    // A server on the same Mac that takes no key, with a model that reasons unless a request turns it off.
    // snippet.hide
    // swift-format-ignore: NeverForceUnwrap
    // snippet.show
    let local = OpenAICompatibleProvider(name: "Local", url: URL(string: "http://localhost:8080/v1")!)
    let model = OpenAICompatibleLanguageModel(
        OpenAICompatibleModel(
            "local-model", on: local, contextSize: 32_768, reasoning: .onByDefault, efforts: [.high, .medium, .low, .off]),
        auth: .unauthenticated
    )
    // snippet.end
    // snippet.hide
    _ = model
}

func apiKey() {
    // snippet.show
    // snippet.apiKey
    // During development, from the scheme's environment, which stays out of git when the scheme isn't shared.
    // snippet.hide
    // swift-format-ignore: NeverForceUnwrap
    // snippet.show
    let provider = OpenAICompatibleProvider(name: "Gateway", url: URL(string: "https://llm.example.com/v1")!)
    let model = OpenAICompatibleLanguageModel(
        OpenAICompatibleModel("my-model", on: provider),
        auth: .apiKey {
            ProcessInfo.processInfo.environment["GATEWAY_API_KEY"] ?? ""
        })
    // snippet.end
    // snippet.hide
    _ = model
}

func preset() {
    // snippet.show
    // snippet.preset
    // A model on Gemini, with the key from the scheme's environment during development.
    let model = OpenAICompatibleLanguageModel(
        OpenAICompatibleModel("gemini-3.1-flash-lite", on: .gemini),
        auth: .apiKey { ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? "" }
    )
    // snippet.end
    // snippet.hide
    _ = model
}

func additionalMembers() throws {
    // swift-format-ignore: NeverForceUnwrap
    let provider = OpenAICompatibleProvider(name: "Local", url: URL(string: "http://localhost:8080/v1")!)
    // snippet.show
    // snippet.additionalMembers
    // Settings only the provider has, which every request's body carries as written.
    var options = OpenAICompatibleOptions()
    options.additionalMembers["keep_alive"] = GeneratedContent("10m")
    options.additionalMembers["chat_template_kwargs"] = try GeneratedContent(json: #"{"enable_thinking":false}"#)
    let model = OpenAICompatibleLanguageModel(OpenAICompatibleModel("local-model", on: provider), options: options, auth: .unauthenticated)
    // snippet.end
    // snippet.hide
    _ = model
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func gatewayKey() async throws -> String { "" }
}

let keyStore = KeyStore()
