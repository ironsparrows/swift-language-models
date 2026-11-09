import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenAICompatibleLanguageModels

@Suite("Models", .timeLimit(.minutes(1)))
struct OpenAICompatibleModelTests {
    @Test func `a model described by its id alone takes the provider's defaults`() throws {
        let provider = OpenAICompatibleProvider(name: "Gateway", url: try #require(URL(string: "https://llm.example.com/v1")))

        let details = OpenAICompatibleModel("my-model", on: provider)

        #expect(details.displayName == "my-model")
        #expect(details.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
        #expect(details.reasoning == .offByDefault)
        #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["xhigh", "high", "medium", "low", "minimal", "none"])
        #expect(details.supportsDataAttachmentType(.png))
        #expect(!details.supportsDataAttachmentType(.pdf))
        #expect(details.contextSize == nil)
    }

    @Test func `a model that doesn't reason lists no efforts and no reasoning, and one without vision takes no images`() throws {
        let provider = OpenAICompatibleProvider(name: "Gateway", url: try #require(URL(string: "https://llm.example.com/v1")))

        let plain = OpenAICompatibleModel("plain", on: provider, capabilities: [.toolCalling], reasoning: .unsupported, efforts: [.high])
        let documents = OpenAICompatibleModel("documents", on: provider, capabilities: [.reasoning], attachments: [.pdf])

        #expect(plain.reasoningEfforts.isEmpty)
        #expect(plain.capabilities.listed == [.toolCalling])
        #expect(plain.dataAttachmentTypes.isEmpty)
        #expect(documents.capabilities.listed == [.reasoning])
        #expect(documents.supportsDataAttachmentType(.pdf))
    }

    @Test func `a model created without a configuration takes its provider's, and one created with one keeps it`() throws {
        var provider = OpenAICompatibleProvider(name: "Gateway", url: try #require(URL(string: "https://llm.example.com/v1")))
        provider.configuration = OpenAICompatibleConfiguration(idleTimeout: .seconds(42), retries: .disabled)
        let details = OpenAICompatibleModel("my-model", on: provider)

        let defaulted = OpenAICompatibleLanguageModel(details, auth: .unauthenticated)
        let configured = OpenAICompatibleLanguageModel(
            details, configuration: OpenAICompatibleConfiguration(idleTimeout: .seconds(30)), auth: .unauthenticated)

        #expect(defaulted.configuration == provider.configuration)
        #expect(configured.configuration == OpenAICompatibleConfiguration(idleTimeout: .seconds(30)))
    }

    @Test func `a model is the dated version that answered for it, and not another model`() {
        let id: OpenAICompatibleModelID = "local-model"

        #expect(id.names("local-model"))
        #expect(id.names("local-model-2026-10-01"))
        #expect(!id.names("local-model-v2"))
        #expect(!id.names("other-model"))
    }
}
