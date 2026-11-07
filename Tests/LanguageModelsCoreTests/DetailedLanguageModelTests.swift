import FoundationModels
import LanguageModelsCore
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@Suite("Detailed language model")
struct DetailedLanguageModelTests {
    @Test(arguments: [(UTType.png, true), (.image, true), (.pdf, false)])
    func `the details accept attachments of their kinds and the kinds that conform to them`(type: UTType, accepted: Bool) {
        #expect(EchoModel<HighLowEffort>(efforts: []).details.supportsDataAttachmentType(type) == accepted)
    }

    @Test func `a model with fallbacks has only the capabilities they all list`() {
        var fallback = EchoModel<HighLowEffort>.Details(reasoningEfforts: [])
        fallback.capabilities = LanguageModelCapabilities([.reasoning, .vision])

        #expect(EchoModel<HighLowEffort>(efforts: []).capabilities.listed == [.toolCalling, .reasoning])
        #expect(EchoModel<HighLowEffort>(efforts: [], fallbacks: [fallback]).capabilities.listed == [.reasoning])
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `Foundation Models reads the data kinds from the details`() async throws {
        let model: any LanguageModel = EchoModel<HighLowEffort>(efforts: [])

        #expect(try await model.supportsDataAttachmentType(.png))
        #expect(try await !model.supportsDataAttachmentType(.pdf))
        #expect(try await !model.supportsDataEntryType(.png))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a model with fallbacks takes and generates only the data kinds they all list`() async throws {
        var fallback = EchoModel<HighLowEffort>.Details(reasoningEfforts: [])
        fallback.dataAttachmentTypes = [.pdf]
        fallback.dataEntryTypes = [.png]
        var model = EchoModel<HighLowEffort>(efforts: [])
        model.details.dataEntryTypes = [.image]
        model.fallbacks = [fallback]

        #expect(try await !model.supportsDataAttachmentType(.png))
        #expect(try await model.supportsDataEntryType(.png))
        #expect(try await !model.supportsDataEntryType(.jpeg))
    }
    #endif
}
