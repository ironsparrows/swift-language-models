// snippet.hide
import FoundationModels
import OpenAILanguageModels

func webSearch() async throws {
    // snippet.show
    // snippet.search
    let model = OpenAILanguageModel(
        .gpt6Luna,
        serverTools: [.webSearch(allowedDomains: ["swift.org"], listsSources: true)],
        options: OpenAIOptions(maximumServerToolCalls: 3),
        auth: .apiKey { try await keyStore.openAIKey() }
    )
    let response = try await LanguageModelSession(model: model).respond(to: "What's new in the latest Swift release?")

    for case .response(let answer) in response.transcriptEntries {
        for citation in answer.openAI.citations {
            print(citation.title ?? "Untitled", citation.url)
        }
        print("Consulted \(answer.openAI.sources.count) pages.")
    }
    // snippet.end
    // snippet.hide
}

#if canImport(FoundationModels, _version: 2.1.14)
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
func images() async throws {
    // snippet.show
    // snippet.images
    let model = OpenAILanguageModel(
        .gpt6Luna,
        serverTools: [.imageGeneration(quality: .low, size: .square1024)],
        auth: .apiKey { try await keyStore.openAIKey() }
    )
    let session = LanguageModelSession(model: model)
    let response = try await session.respond(to: "Draw a lighthouse at dusk.")

    for case .data(let image) in response.transcriptEntries {
        // `image.content` holds the PNG; the revised prompt says what was drawn.
        print(image.contentType, image.content.count, image.openAI.revisedPrompt ?? "")
    }
    // The model sees the image on the next turn, so it can change it.
    _ = try await session.respond(to: "Make the sky darker.")
    // snippet.end
    // snippet.hide
}
#endif

func fileSearch() async throws {
    // snippet.show
    // snippet.files
    let model = OpenAILanguageModel(
        .gpt6Luna,
        serverTools: [.fileSearch(vectorStoreIDs: ["vs_menus"], maximumResults: 5)],
        auth: .apiKey { try await keyStore.openAIKey() }
    )
    let response = try await LanguageModelSession(model: model).respond(to: "When does the kitchen close?")

    for case .response(let answer) in response.transcriptEntries {
        for file in answer.openAI.fileCitations {
            print(file.filename ?? file.fileID, file.offset.map(String.init) ?? "")
        }
    }
    // snippet.end
    // snippet.hide
}

/// Stands in for the app's own Keychain wrapper.
struct KeyStore {
    func openAIKey() async throws -> String { "" }
}

let keyStore = KeyStore()
