import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// A prompt entry with text and an image.
private func imagePrompt(_ text: String, _ image: Transcript.ImageAttachment, label: String? = nil) -> Transcript.Entry {
    .prompt(Transcript.Prompt(segments: [.text(.init(content: text)), .attachment(.init(content: .image(image), label: label))]))
}

extension OpenRouterExchangeTests {
    @Suite("Image attachments")
    struct ImageAttachments {
        @Test func `an image goes no larger than the configuration's encoding allows`() async throws {
            let stub = HTTPStub(events(text("Seven."), done()))
            let image = try #require(TestImage.halves(width: 40, height: 20))
            let configuration = OpenRouterConfiguration(images: ImageEncoding(maximumSide: 10))
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, inputs: [.text, .image], configuration: configuration)
            let session = LanguageModelSession(model: model)

            _ = try await session.respond { FoundationModels.Attachment(image) }

            let decoded = try sentImage(stub)
            #expect((decoded.width, decoded.height) == (10, 5))
        }

        @Test(arguments: ["unsupported_image_format", "invalid_image", "image_too_large", "image_too_small"])
        func `an image the host rejects throws unsupported transcript content, naming the entries with images`(type: String)
            async throws
        {
            let body = #"{"error":{"code":400,"message":"Bad image","metadata":{"error_type":"\#(type)"}}}"#
            let stub = HTTPStub(.json(body, status: 400))
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

            let error = await #expect(throws: LanguageModelError.self) {
                try await session.respond {
                    "Which digit is it?"
                    FoundationModels.Attachment(image)
                }
            }

            guard case .unsupportedTranscriptContent(let info)? = error else {
                Issue.record("Expected unsupported transcript content, got \(String(describing: error))")
                return
            }
            #expect(info.unsupportedContent.count == 1)
            #expect(info.metadata[LanguageModelMetadataKey.errorCode] as? String == type)
        }

        @Test func `an image the host rejects in the stream names the entries with images too`() async throws {
            let rejection: JSONValue = ["error": ["code": 400, "message": "Bad image", "metadata": ["error_type": "invalid_image"]]]
            let stub = HTTPStub(events(rejection))
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

            let error = await #expect(throws: LanguageModelError.self) {
                try await session.respond {
                    "Which digit is it?"
                    FoundationModels.Attachment(image)
                }
            }

            guard case .unsupportedTranscriptContent(let info)? = error else {
                Issue.record("Expected unsupported transcript content, got \(String(describing: error))")
                return
            }
            #expect(info.unsupportedContent.count == 1)
        }

        @Test func `an image is refused with the vision capability before any request when the model doesn't take images`()
            async throws
        {
            let stub = HTTPStub(events(text("Hi"), done()))
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let transcript = Transcript(entries: [
                imagePrompt("What's this?", Transcript.ImageAttachment(image)),
                .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "A flag."))])),
            ])
            let session = LanguageModelSession(model: model(stub), transcript: transcript)

            try await expectVisionRefused(stub) { try await session.respond(to: "Which colors?") }
            #expect(!model(stub).capabilities.contains(.vision))
        }

        @Test func `an image is refused when a fallback doesn't take images, though the model does`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let model = model(stub, inputs: [.text, .image], fallbacks: [fallback(inputs: [.text, .file])])
            let session = LanguageModelSession(model: model)

            try await expectVisionRefused(stub) { try await session.respond { FoundationModels.Attachment(image) } }
            #expect(!model.capabilities.contains(.vision))
        }

        /// The first image of the last message of the stub's first request, decoded.
        private func sentImage(_ stub: HTTPStub) throws -> DecodedImage {
            let url = try #require(dataURL(parts(messages(try body(stub)).last).first { $0["type"] == "image_url" }))
            return try #require(DecodedImage(url.data))
        }

        /// Expects an image to be refused with the vision capability, before any request.
        private func expectVisionRefused(_ stub: HTTPStub, _ respond: () async throws -> some Any) async throws {
            let error = try await #require(throws: LanguageModelError.self) { _ = try await respond() }
            guard case .unsupportedCapability(let info) = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(info.capability == .vision)
            #expect(stub.requests.isEmpty)
        }
    }
}
