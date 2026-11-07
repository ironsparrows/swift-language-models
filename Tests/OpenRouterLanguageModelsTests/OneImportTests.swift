// This file imports only the module an app imports, so it stops compiling when a vocabulary, a model's details or a
// type from the re-exported core need another import.
import Foundation
import FoundationModels
import OpenRouterLanguageModels
import Testing
import UniformTypeIdentifiers

/// Each vocabulary's word as a string literal, as the value prints, and the literal itself.
private let words: [(printed: String, literal: String)] = [
    (("anthropic/claude-haiku-5.5" as OpenRouterModelID).description, "anthropic/claude-haiku-5.5"),
    (("Anthropic" as OpenRouterProviderName).description, "Anthropic"),
    (("top_p" as OpenRouterParameter).description, "top_p"),
    (("image" as OpenRouterInputModality).description, "image"),
    (("image" as OpenRouterOutputModality).description, "image"),
    (("flex" as OpenRouterServiceTier).description, "flex"),
    (("low" as OpenRouterOptions.Verbosity).description, "low"),
    (("cloudflare-ai" as OpenRouterOptions.PDFEngine).description, "cloudflare-ai"),
    (("price" as OpenRouterRouting.Sort).description, "price"),
    (("fp8" as OpenRouterQuantization).description, "fp8"),
    (("cli-agent" as OpenRouterApp.Category).description, "cli-agent"),
    (("high" as OpenRouterSearchContextSize).description, "high"),
    (("exa" as OpenRouterWebSearchEngine).description, "exa"),
    (("fast" as OpenRouterWebSearchMode).description, "fast"),
    (("openrouter" as OpenRouterWebFetchEngine).description, "openrouter"),
    (("medium" as OpenRouterOptions.AutoRouter.CostTier).description, "medium"),
    (("payment_required" as OpenRouterError.Code).description, "payment_required"),
    (("nitro" as OpenRouterRouting.Variant).description, "nitro"),
    (("length" as FinishReason).description, "length"),
]

@Suite("One import", .timeLimit(.minutes(1)))
struct OneImportTests {
    @Test(arguments: words)
    func `every vocabulary takes a string literal and prints it, with only this module imported`(printed: String, literal: String) {
        #expect(printed == literal)
    }

    @Test func `a model's details answer for the data kinds they list, with only this module imported`() throws {
        let details = OpenRouterLanguageModel(.googleGemini2_5FlashImage, auth: .apiKey { "sk-or-test" }).details

        #expect(details.supportsDataAttachmentType(try #require(details.dataAttachmentTypes.first)))
        #expect(details.supportsDataEntryType(try #require(details.dataEntryTypes.first)))
    }

    @Test func `the core's efforts, profile modifier and generic details work, with only this module imported`() {
        let model = OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey { "sk-or-test" })
        let profile = HaikuProfile(model: model)

        #expect(model.details.reasoningEfforts.contains(Efforts.Of<OpenRouterCatalog.AnthropicClaudeHaiku5_5>.xhigh))
        #expect(displayName(of: model) == model.details.displayName)
        _ = profile.body
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `the core's file attachment works, with only this module imported`() {
        let attachment = FileAttachment(Data("%PDF".utf8), type: .pdf)

        #expect(attachment.transcriptRepresentation.contentType == .pdf)
    }
    #endif

    /// A Dynamic Profile that sets a typed effort, through the core's `model(_:effort:)`.
    private struct HaikuProfile: LanguageModelSession.DynamicProfile {
        let model: OpenRouterLanguageModel<Efforts.Of<OpenRouterCatalog.AnthropicClaudeHaiku5_5>>

        var body: some LanguageModelSession.DynamicProfile {
            LanguageModelSession.Profile { Instructions("Be brief.") }.model(model, effort: .xhigh)
        }
    }

    /// A model's display name, read through the core's `DetailedLanguageModel`.
    private func displayName(of model: some DetailedLanguageModel) -> String {
        model.details.displayName
    }
}
