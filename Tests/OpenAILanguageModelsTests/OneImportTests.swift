// This file imports only the module an app imports, so it stops compiling when a vocabulary, a model's details or a
// type from the re-exported core need another import.
import Foundation
import FoundationModels
import OpenAILanguageModels
import Testing
import UniformTypeIdentifiers

/// Each vocabulary's word as a string literal, as the value prints, and the literal itself.
private let words: [(printed: String, literal: String)] = [
    (("gpt-6-luna" as OpenAIModelID).description, "gpt-6-luna"),
    (("top_p" as OpenAIParameter).description, "top_p"),
    (("pdf" as OpenAIInputModality).description, "pdf"),
    (("flex" as OpenAIServiceTier).description, "flex"),
    (("low" as OpenAIOptions.Verbosity).description, "low"),
    (("auto" as OpenAIOptions.ReasoningSummary).description, "auto"),
    (("invalid_api_key" as OpenAIError.Code).description, "invalid_api_key"),
    (("length" as FinishReason).description, "length"),
]

@Suite("One import", .timeLimit(.minutes(1)))
struct OneImportTests {
    @Test(arguments: words)
    func `every vocabulary takes a string literal and prints it, with only this module imported`(printed: String, literal: String) {
        #expect(printed == literal)
    }

    @Test func `a catalog model, its typed efforts, the profile modifier and its data kinds work with only this module imported`() {
        let model = OpenAILanguageModel(.gpt6Luna, auth: .apiKey { "sk-test" })
        let profile = LunaProfile(model: model)

        #expect(model.details.reasoningEfforts.contains(Efforts.Of<OpenAICatalog.Gpt6Luna>.low))
        #expect(model.details.supportsDataAttachmentType(.pdf))
        #expect(model.capabilities.contains(.reasoning))
        _ = profile.body
    }

    /// A Dynamic Profile that sets a typed effort, through the core's `model(_:effort:)`.
    private struct LunaProfile: LanguageModelSession.DynamicProfile {
        let model: OpenAILanguageModel<Efforts.Of<OpenAICatalog.Gpt6Luna>>

        var body: some LanguageModelSession.DynamicProfile {
            LanguageModelSession.Profile { Instructions("Be brief.") }.model(model, effort: .low)
        }
    }
}
