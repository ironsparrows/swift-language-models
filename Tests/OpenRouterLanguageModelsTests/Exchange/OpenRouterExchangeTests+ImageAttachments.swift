import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels
@testable import OpenRouterLanguageModels

/// A tool that returns a chart as an image.
private struct ChartTool: Tool {
    let name = "drawChart"
    let description = "Draws the week's calories as a chart."
    let image: CGImage

    @Generable
    struct Arguments {
        var week: Int
    }

    func call(arguments: Arguments) async throws -> Prompt {
        Prompt {
            "The chart for week \(arguments.week):"
            FoundationModels.Attachment(image).label("chart")
        }
    }
}

/// A prompt entry with text and an image.
private func imagePrompt(_ text: String, _ image: Transcript.ImageAttachment, label: String? = nil) -> Transcript.Entry {
    .prompt(Transcript.Prompt(segments: [.text(.init(content: text)), .attachment(.init(content: .image(image), label: label))]))
}

extension OpenRouterExchangeTests {
    @Suite("Image attachments")
    struct ImageAttachments {
        @Test func `an image goes after its label as an upright JPEG data URL, in the prompt's order`() async throws {
            let stub = HTTPStub(events(text("Seven."), done()))
            let image = try #require(TestImage.halves(width: 40, height: 20))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

            _ = try await session.respond {
                "Which digit is it?"
                FoundationModels.Attachment(image).label("digit")
                "Answer in one word."
            }

            let prompt = try #require(messages(try body(stub)).last)
            let content = parts(prompt)
            #expect(content.count == 4)
            #expect(content[0] == ["type": "text", "text": "Which digit is it?"])
            #expect(content[1] == ["type": "text", "text": "digit"])
            #expect(content[2]["type"] == "image_url")
            #expect(content[3] == ["type": "text", "text": "Answer in one word."])
            let url = try #require(dataURL(content[2]))
            #expect(url.mediaType == "image/jpeg")
            let decoded = try #require(DecodedImage(url.data))
            #expect((decoded.width, decoded.height) == (40, 20))
            #expect(decoded.isRed(x: 5, y: 10))
        }

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

        @Test func `an image without a label goes alone, and a prompt of only an image keeps its parts`() async throws {
            let stub = HTTPStub(events(text("A chart."), done()))
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

            _ = try await session.respond { FoundationModels.Attachment(image) }

            let content = parts(messages(try body(stub)).last)
            #expect(content.map { $0["type"] } == ["image_url"])
        }

        @Test(arguments: [(3_000, 1_500, 2_048, 1_024), (1_200, 4_096, 600, 2_048), (2_048, 2_048, 2_048, 2_048), (300, 200, 300, 200)])
        func `an image over 2,048 pixels on its longer side is scaled down to it, and a smaller one keeps its size`(
            width: Int,
            height: Int,
            sentWidth: Int,
            sentHeight: Int
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let image = try #require(TestImage.halves(width: width, height: height))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

            _ = try await session.respond { FoundationModels.Attachment(image) }

            let decoded = try sentImage(stub)
            #expect((decoded.width, decoded.height) == (sentWidth, sentHeight))
        }

        @Test func `an image goes upright by its orientation`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let image = try #require(TestImage.halves(width: 40, height: 20))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

            _ = try await session.respond { FoundationModels.Attachment(image, orientation: .right) }

            let decoded = try sentImage(stub)
            #expect((decoded.width, decoded.height) == (20, 40))
            #expect(decoded.isRed(x: 10, y: 5))
            #expect(decoded.isBlue(x: 10, y: 35))
        }

        @Test func `an image file goes as its pixels, upright by the orientation it records`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let image = try #require(TestImage.halves(width: 40, height: 20))
            let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jpg")
            try #require(TestImage.file(of: image, as: .jpeg, orientation: .right)).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

            _ = try await session.respond { FoundationModels.Attachment(imageURL: file) }

            let url = try #require(dataURL(parts(messages(try body(stub)).last).first))
            #expect(url.mediaType == "image/jpeg")
            let decoded = try #require(DecodedImage(url.data))
            #expect((decoded.width, decoded.height) == (20, 40))
            #expect(decoded.isRed(x: 10, y: 5))
        }

        // A session loads an image at a web address before its model sees the prompt, so these build the request straight
        // from a transcript, with an address that never resolves.

        @Test func `an image at a web address goes as that address`() throws {
            let address = "https://photos.invalid/cat.png?size=large"
            let image = Transcript.ImageAttachment(imageURL: try #require(URL(string: address)))

            let body = try requestBody([imagePrompt("What's this?", image)], model: model(HTTPStub(), inputs: [.text, .image]))

            let content = parts(messages(body).last)
            #expect(content.last == ["type": "image_url", "image_url": ["url": .string(address)]])
        }

        @Test func `an image at a web address that needs turning is refused, since only its pixels could be turned`() throws {
            let image = Transcript.ImageAttachment(
                imageURL: try #require(URL(string: "https://photos.invalid/cat.png")), orientation: .left)

            let error = try #require(throws: LanguageModelError.self) {
                try requestBody([imagePrompt("What's this?", image)], model: model(HTTPStub(), inputs: [.text, .image]))
            }

            guard case .unsupportedTranscriptContent = error else {
                Issue.record("Expected unsupported transcript content, got \(error)")
                return
            }
        }

        @Test func `a missing image file is refused instead of read`() throws {
            let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
            let image = Transcript.ImageAttachment(imageURL: file, orientation: .up)

            let error = try #require(throws: LanguageModelError.self) {
                try requestBody([imagePrompt("What's this?", image)], model: model(HTTPStub(), inputs: [.text, .image]))
            }

            guard case .unsupportedTranscriptContent = error else {
                Issue.record("Expected unsupported transcript content, got \(error)")
                return
            }
        }

        @Test func `an image sends the same bytes with every request, so the prompt cache stays valid`() async throws {
            let stub = HTTPStub(events(text("Seven."), done()), events(text("Yes."), done()))
            let image = try #require(TestImage.seven(size: 300))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

            _ = try await session.respond {
                "Which digit?"
                FoundationModels.Attachment(image, orientation: .left).label("digit")
            }
            _ = try await session.respond(to: "Sure?")

            let first = try #require(messages(try body(stub, 0)).first { $0["role"] == "user" })
            let second = try #require(messages(try body(stub, 1)).first { $0["role"] == "user" })
            #expect(first == second)
            #expect(parts(first).count == 3)
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

        @Test func `an attachment in the instructions is refused, since system messages take only text`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let session = LanguageModelSession(
                model: model(stub, inputs: [.text, .image]),
                instructions: Instructions {
                    "Describe the logo."
                    FoundationModels.Attachment(image).label("logo")
                }
            )

            let error = try await #require(throws: LanguageModelError.self) { try await session.respond(to: "Go.") }

            guard case .unsupportedTranscriptContent(let info) = error else {
                Issue.record("Expected unsupported transcript content, got \(error)")
                return
            }
            #expect(info.unsupportedContent.count == 1)
            #expect(stub.requests.isEmpty)
        }

        @Test func `a tool output with an image sends its parts, while text alone stays a string`() async throws {
            let stub = HTTPStub(
                events(toolCall(0, id: "call_1", name: "drawChart", arguments: #"{"week":3}"#), done("tool_calls")),
                events(text("Calories fell."), done())
            )
            let image = try #require(TestImage.halves(width: 16, height: 8))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]), tools: [ChartTool(image: image)])

            _ = try await session.respond(to: "How did week 3 go?")

            let output = try #require(messages(try body(stub, 1)).first { $0["role"] == "tool" })
            let content = parts(output)
            #expect(output["tool_call_id"] == "call_1")
            #expect(content.map { $0["type"] } == ["text", "text", "image_url"])
            #expect(content[1] == ["type": "text", "text": "chart"])
        }

        @Test func `an image on an answer isn't sent back`() async throws {
            let stub = HTTPStub(events(text("Yes."), done()))
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let answer = Transcript.Response(
                assetIDs: [], segments: [.text(.init(content: "Here's the chart.")), .attachment(.init(content: .image(.init(image))))])
            let transcript = Transcript(entries: [
                .prompt(Transcript.Prompt(segments: [.text(.init(content: "Chart it."))])), .response(answer),
            ])
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]), transcript: transcript)

            _ = try await session.respond(to: "Thanks.")

            #expect(try assistantMessages(stub) == [["role": "assistant", "content": "Here's the chart."]])
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
