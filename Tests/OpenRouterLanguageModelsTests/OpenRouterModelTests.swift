import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenRouterLanguageModels

@Suite("OpenRouter model", .timeLimit(.minutes(1)))
struct OpenRouterModelTests {
    @Test func `capabilities come from the parameters, inputs and reasoning the model has`() {
        let model = model(parameters: [.tools, .structuredOutputs], inputs: [.text, .image], reasoning: .mandatory)

        #expect(model.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
    }

    @Test func `JSON mode alone isn't guided generation, since the host doesn't hold the answer to the schema`() {
        #expect(!model(parameters: [.responseFormat], inputs: [.text], reasoning: .unsupported).capabilities.contains(.guidedGeneration))
    }

    @Test func `a text-only model without tools, schemas or reasoning has no capabilities`() {
        #expect(model(parameters: [.temperature], inputs: [.text], reasoning: .unsupported).capabilities.listed.isEmpty)
    }

    @Test func `a model takes the attachments of its input kinds and generates the data of its output kinds`() {
        let model = OpenRouterModel<Efforts.Unsupported>(
            id: "vendor/model",
            displayName: "Vendor: Model",
            releaseDate: .distantPast,
            inputModalities: [.text, .image, "hologram"],
            outputModalities: [.text, .image, .audio, .embeddings],
            supportedParameters: []
        )

        #expect(model.dataAttachmentTypes == OpenRouterInputModality.image.contentTypes.union([.plainText, .pdf]))
        #expect(model.dataEntryTypes == [.image])
        #expect([UTType.png, .jpeg, .heic, .utf8PlainText, .pdf].allSatisfy(model.supportsDataAttachmentType))
        #expect(![UTType.mp3, .mpeg4Movie, .zip].contains(where: model.supportsDataAttachmentType))
        #expect(model.supportsDataEntryType(.png))
        #expect(!model.supportsDataEntryType(.wav))
    }

    @Test(arguments: [
        (OpenRouterInputModality.text, UTType.utf8PlainText), (.image, .heic), (.file, .pdf), (.audio, .mp3), (.audio, .wav),
        (.video, .quickTimeMovie),
    ])
    func `each kind of data belongs to one input kind`(input: OpenRouterInputModality, type: UTType) {
        #expect(OpenRouterInputModality(carrying: type) == input)
        #expect(input.contentTypes.contains { type.conforms(to: $0) })
    }

    @Test func `a text-only model takes PDFs, which OpenRouter reads for it, but no images, audio or video`() {
        let model = model(parameters: [.temperature], inputs: [.text], reasoning: .unsupported)

        #expect(model.supportsDataAttachmentType(.pdf))
        #expect(![UTType.png, .wav, .mpeg4Movie].contains(where: model.supportsDataAttachmentType))
        #expect(OpenRouterInputModality(rawValue: "hologram").contentTypes.isEmpty)
    }

    @Test func `a typed model turns into its open form`() {
        let typed = model(parameters: [.reasoning], inputs: [.text], reasoning: .onByDefault)

        let open = OpenRouterModel<ContextOptions.ReasoningLevel>(typed)

        #expect(open.id == typed.id)
        #expect(open.aliasTarget == typed.aliasTarget)
        #expect(open.reasoning == typed.reasoning)
        #expect(open.reasoningEfforts == [.max, .low, .off])
        #expect(open.defaultReasoningEffort == .low)
        #expect(open.knowledgeCutoff == typed.knowledgeCutoff)
        #expect(open.cachesOnlyMarkedPrompts)
    }

    @Test func `the catalog lookup gives nil for an unknown id`() {
        #expect(OpenRouterModel(catalogID: "vendor/not-a-model") == nil)
    }

    @Test func `the catalog list has each model the lookup finds, once and sorted by id`() {
        let models = OpenRouterModel.catalogModels
        let ids = models.map(\.id.rawValue)

        #expect(!models.isEmpty)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count)
        #expect(models.allSatisfy { OpenRouterModel(catalogID: $0.id) == $0 })
    }

    @Test func `a model id encodes as its raw value`() throws {
        let id: OpenRouterModelID = "typesafe/jev-router"
        let data = try JSONEncoder().encode(id)

        #expect(String(decoding: data, as: UTF8.self) == #""typesafe\/jev-router""#)
        #expect(try JSONDecoder().decode(OpenRouterModelID.self, from: data) == id)
    }

    private func model(
        parameters: Set<OpenRouterParameter>,
        inputs: Set<OpenRouterInputModality>,
        reasoning: ModelReasoning
    ) -> OpenRouterModel<MaxHighLowOff> {
        OpenRouterModel(
            id: "vendor/model",
            displayName: "Vendor: Model",
            releaseDate: Date(timeIntervalSince1970: 1_793_000_000),
            aliasTarget: "vendor/model-2",
            knowledgeCutoff: Date(timeIntervalSince1970: 1_782_777_600),
            contextSize: 200_000,
            inputModalities: inputs,
            supportedParameters: parameters,
            reasoning: reasoning,
            reasoningEfforts: [.max, .low, .off],
            defaultReasoningEffort: .low,
            cachesOnlyMarkedPrompts: true
        )
    }
}
