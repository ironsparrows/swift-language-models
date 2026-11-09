// This file imports only the module an app imports, so it stops compiling when a vocabulary, a model's details or a
// type from the re-exported core need another import.
import Foundation
import FoundationModels
import OpenAICompatibleLanguageModels
import Testing
import UniformTypeIdentifiers

/// Each vocabulary's word as a string literal, as the value prints, and the literal itself.
private let words: [(printed: String, literal: String)] = [
    (("local-model" as OpenAICompatibleModelID).description, "local-model"),
    (("invalid_api_key" as OpenAICompatibleError.Code).description, "invalid_api_key"),
    (("length" as FinishReason).description, "length"),
]

@Suite("One import", .timeLimit(.minutes(1)))
struct OneImportTests {
    @Test(arguments: words)
    func `every vocabulary takes a string literal and prints it, with only this module imported`(printed: String, literal: String) {
        #expect(printed == literal)
    }

    @Test func `a model's details, the core's efforts and the profile modifier work, with only this module imported`() throws {
        let provider = OpenAICompatibleProvider(name: "Local", url: try #require(URL(string: "http://localhost:8080/v1")))
        let model = OpenAICompatibleLanguageModel(
            OpenAICompatibleModel("local-model", on: provider, reasoning: .onByDefault, efforts: [.high, .low, .off]),
            auth: .unauthenticated)
        let profile = LocalProfile(model: model)

        #expect(model.details.reasoningEfforts.contains(.high))
        #expect(model.details.supportsDataAttachmentType(.png))
        #expect(model.capabilities.contains(.reasoning))
        _ = profile.body
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `the core's file attachment works, with only this module imported`() {
        let attachment = FileAttachment(Data("%PDF".utf8), type: .pdf)

        #expect(attachment.transcriptRepresentation.contentType == .pdf)
    }
    #endif

    /// A Dynamic Profile that sets an effort, through the core's `model(_:effort:)`.
    private struct LocalProfile: LanguageModelSession.DynamicProfile {
        let model: OpenAICompatibleLanguageModel

        var body: some LanguageModelSession.DynamicProfile {
            LanguageModelSession.Profile { Instructions("Be brief.") }.model(model, effort: .low)
        }
    }
}
