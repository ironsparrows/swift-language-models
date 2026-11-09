import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Attachments")
    struct Attachments {
        @Test func `a labeled image goes as its label, then an image the model sees at the detail it picks`() throws {
            let image = Transcript.ImageAttachment(try #require(TestImage.halves(width: 8, height: 4)))
            let entries = [prompt(text("What's this?"), .attachment(.init(content: .image(image), label: "Photo")))]

            let sent = try ResponsesSentRequest(generationRequest(entries))
            let content = input(sent.body).first?["content"]

            #expect(content?[0] == ["type": "input_text", "text": "What's this?"])
            #expect(content?[1] == ["type": "input_text", "text": "Photo"])
            #expect(keys(content?[2]) == ["type", "image_url", "detail"])
            #expect(content?[2]?["image_url"]?.stringValue?.hasPrefix("data:image/jpeg;base64,") == true)
            #expect(content?[2]?["detail"] == "auto")
            #expect(sent.imageEntries.map(\.id) == entries.map(\.id))
        }

        @Test func `the exchange's check sees an image's web address`() async throws {
            try await withImage(from: .webAddress) { image, address in
                var model = Responses.Model<ResponsesTestExchange>.test()
                let entry = prompt(.attachment(.init(content: .image(image))))

                try await confirmation { checked in
                    model.exchange.checks = { kind, _ in
                        #expect(kind == .image(webAddress: address))
                        checked()
                    }
                    _ = try ResponsesSentRequest(generationRequest([entry]), model: model)
                }
            }
        }

        #if canImport(FoundationModels, _version: 2.1.14)
        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `a kind the format has no part for throws before anything is sent`() {
            let notes = Transcript.DataAttachment(contentType: .rtf, content: Data("{\\rtf1 Soup}".utf8))
            let entries = [prompt(.attachment(.init(content: .data(notes), label: "Notes")))]

            #expect(throws: LanguageModelError.self) { try ResponsesSentRequest(generationRequest(entries)) }
        }
        #endif
    }
}
