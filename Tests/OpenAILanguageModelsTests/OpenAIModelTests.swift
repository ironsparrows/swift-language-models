import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenAILanguageModels

@Suite("OpenAI model", .timeLimit(.minutes(1)))
struct OpenAIModelTests {
    @Test func `the capabilities come from the settings and inputs the model takes`() {
        let reasoning: OpenAIModel<ContextOptions.ReasoningLevel> = details(inputs: [.text, .image])
        let plain: OpenAIModel<Efforts.Unsupported> = details(parameters: [.maxOutputTokens], inputs: [.text], reasoning: .unsupported)

        #expect(reasoning.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
        #expect(plain.capabilities.listed.isEmpty)
    }

    @Test func `the attachment kinds are those of the inputs`() {
        let model: OpenAIModel<ContextOptions.ReasoningLevel> = details(inputs: [.text, .image, .pdf])

        #expect(model.supportsDataAttachmentType(.pdf))
        #expect(model.supportsDataAttachmentType(.png))
        #expect(model.supportsDataAttachmentType(.utf8PlainText))
        #expect(!model.supportsDataAttachmentType(.wav))
        #expect(!model.supportsDataEntryType(.png))
    }

    @Test func `the catalog finds a model by its id, with its efforts in their open form`() throws {
        let model = try #require(OpenAIModel(catalogID: "gpt-6-luna"))

        #expect(model.displayName == "GPT-6 Luna")
        #expect(model.reasoningEfforts.compactMap(\.effortWord) == ["max", "xhigh", "high", "medium", "low", "none"])
        #expect(OpenAIModel(catalogID: "gpt-unknown") == nil)
        #expect(OpenAIModel.catalogModels.contains { $0.id == "gpt-6-luna" })
    }

    @Test func `a model is the dated snapshot that answered for it, and not another model`() {
        let id: OpenAIModelID = "gpt-5.4-mini"

        #expect(id.names("gpt-5.4-mini"))
        #expect(id.names("gpt-5.4-mini-2026-03-17"))
        #expect(!id.names("gpt-5.4-nano"))
        #expect(!id.names("gpt-5.4-mini-high"))
    }

    @Test(arguments: ModelRemovals.openAI.dates.sorted { $0.key < $1.key })
    func `every model the catalog removed has its removal date`(id: String, date: Date) {
        let model = OpenAIModel<ContextOptions.ReasoningLevel>(id: OpenAIModelID(rawValue: id), displayName: id, supportedParameters: [])

        #expect(model.removalDate == date)
    }
}
