import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenAILanguageModels

#if canImport(FoundationModels, _version: 2.1.14)
extension OpenAIExchangeTests {
    @Suite("Generated images")
    struct GeneratedImages {
        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `an image becomes a data entry of the kind its format names, which keeps its call`() async throws {
            let image = Data([0x52, 0x49, 0x46, 0x46])
            let call: JSONValue = [
                "type": "image_generation_call", "id": "ig_1", "status": "completed", "output_format": "webp",
                "result": .string(image.base64EncodedString()), "revised_prompt": "A blue circle.",
            ]
            let stub = HTTPStub(
                responseStream([created()], [item("response.output_item.done", at: 0, call), textDelta("Done.", at: 1), completed()]))
            let model = model(
                stub, details(efforts: [ContextOptions.ReasoningLevel.low]), serverTools: [.imageGeneration(format: .webp)])

            let response = try await LanguageModelSession(model: model).respond(to: "Draw a blue circle.")

            let entries = response.transcriptEntries.compactMap { entry -> Transcript.DataEntry? in
                if case .data(let data) = entry { data } else { nil }
            }
            #expect(entries.map(\.contentType) == [.webP])
            #expect(entries.map(\.content) == [image])
            #expect(entries.map(\.openAI.callID) == ["ig_1"])
            #expect(entries.map(\.openAI.revisedPrompt) == ["A blue circle."])
        }
    }
}
#endif
