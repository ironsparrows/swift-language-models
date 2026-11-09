import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

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

extension ChatCompletionsModelTests {
    @Suite("Attachments")
    struct Attachments {
        @Test func `an image goes after its label as a JPEG data URL, in the prompt's order`() async throws {
            let stub = HTTPStub(answer)
            let image = try #require(TestImage.halves(width: 40, height: 20))

            _ = try await LanguageModelSession(model: plainModel(stub)).respond {
                "Which digit is it?"
                FoundationModels.Attachment(image).label("digit")
                "Answer in one word."
            }

            let content = try parts(of: stub)
            #expect(content.count == 4)
            #expect(content[0] == ["type": "text", "text": "Which digit is it?"])
            #expect(content[1] == ["type": "text", "text": "digit"])
            #expect(content[2]["type"] == "image_url")
            #expect(content[3] == ["type": "text", "text": "Answer in one word."])
            let decoded = try decodedImage(content[2], mediaType: "image/jpeg")
            #expect((decoded.width, decoded.height) == (40, 20))
            #expect(decoded.isRed(x: 5, y: 10))
        }

        @Test func `an image without a label goes alone, and a prompt of only an image keeps its parts`() async throws {
            let stub = HTTPStub(answer)
            let image = try #require(TestImage.halves(width: 8, height: 8))

            _ = try await LanguageModelSession(model: plainModel(stub)).respond { FoundationModels.Attachment(image) }

            #expect(try parts(of: stub).map { $0["type"] } == ["image_url"])
        }

        @Test func `an image file goes as its pixels, upright by the orientation it records`() async throws {
            let stub = HTTPStub(answer)
            let image = try #require(TestImage.halves(width: 40, height: 20))
            let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jpg")
            try #require(TestImage.file(of: image, as: .jpeg, orientation: .right)).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }

            _ = try await LanguageModelSession(model: plainModel(stub)).respond { FoundationModels.Attachment(imageURL: file) }

            let decoded = try decodedImage(try #require(try parts(of: stub).first), mediaType: "image/jpeg")
            #expect((decoded.width, decoded.height) == (20, 40))
            #expect(decoded.isRed(x: 10, y: 5))
        }

        // A session loads an image at a web address before its model sees the prompt, so this builds the request straight
        // from a transcript, with an address that never resolves.
        @Test func `an image at a web address goes as that address`() throws {
            let address = "https://photos.invalid/cat.png?size=large"
            let image = Transcript.ImageAttachment(imageURL: try #require(URL(string: address)))
            let entry = prompt(text("What's this?"), .attachment(.init(content: .image(image))))

            let content = messages(try ChatCompletionsSentRequest(generationRequest([entry])).body).last?["content"]

            #expect(content?[1] == ["type": "image_url", "image_url": ["url": .string(address)]])
        }

        @Test(arguments: ImageSource.allCases)
        func `the exchange's check sees whether an image is at a web address, before the image is read`(source: ImageSource) async throws {
            try await withImage(from: source) { image, address in
                var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
                let entry = prompt(.attachment(.init(content: .image(image))))

                try await confirmation { checked in
                    model.exchange.checks = { kind, _ in
                        #expect(kind == .image(webAddress: address))
                        checked()
                    }
                    _ = try ChatCompletionsSentRequest(generationRequest([entry]), model: model)
                }
            }
        }

        @Test func `the exchange's check runs before the image is read, so its error is the one thrown`() throws {
            let missing = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
            let entry = prompt(.attachment(.init(content: .image(Transcript.ImageAttachment(imageURL: missing)))))
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.checks = { _, _ throws(LanguageModelError) in throw .unsupported(.vision, "Test takes no images.") }

            let error = try #require(throws: LanguageModelError.self) {
                try ChatCompletionsSentRequest(generationRequest([entry]), model: model)
            }

            guard case .unsupportedCapability = error else {
                Issue.record("Expected the check's error, got \(error)")
                return
            }
        }

        @Test func `an image sends the same bytes with every request, so the prompt cache stays valid`() async throws {
            let stub = HTTPStub(answer, answer)
            let image = try #require(TestImage.seven(size: 300))
            let session = LanguageModelSession(model: plainModel(stub))

            _ = try await session.respond {
                "Which digit?"
                FoundationModels.Attachment(image, orientation: .left).label("digit")
            }
            _ = try await session.respond(to: "Sure?")

            let first = try #require(try sentMessages(stub, 0).first { $0["role"] == "user" })
            let second = try #require(try sentMessages(stub, 1).first { $0["role"] == "user" })
            #expect(first == second)
        }

        @Test func `an attachment in the instructions is refused, since system messages take only text`() async throws {
            let stub = HTTPStub(answer)
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let session = LanguageModelSession(
                model: plainModel(stub),
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

        @Test func `a tool output with an image sends its parts`() async throws {
            let call: JSONValue = [
                "choices": [
                    [
                        "delta": [
                            "tool_calls": [["index": 0, "id": "call_1", "function": ["name": "drawChart", "arguments": #"{"week":3}"#]]]
                        ],
                        "finish_reason": "tool_calls",
                    ]
                ]
            ]
            let stub = HTTPStub(chatCompletionsEvents(call), answer)
            let image = try #require(TestImage.halves(width: 16, height: 8))
            let session = LanguageModelSession(model: plainModel(stub), tools: [ChartTool(image: image)])

            _ = try await session.respond(to: "How did week 3 go?")

            let output = try #require(try sentMessages(stub, 1).first { $0["role"] == "tool" })
            #expect(output["tool_call_id"] == "call_1")
            #expect(output["content"]?[0]?["type"] == "text")
            #expect(output["content"]?[1] == ["type": "text", "text": "chart"])
            #expect(output["content"]?[2]?["type"] == "image_url")
        }

        @Test func `an image on an answer isn't sent back`() throws {
            let image = try #require(TestImage.halves(width: 8, height: 8))
            let answer = Transcript.Response(
                assetIDs: [], segments: [text("Here's the chart."), .attachment(.init(content: .image(.init(image))))])

            let sent = messages(
                try ChatCompletionsSentRequest(generationRequest([prompt(text("Chart it.")), .response(answer), prompt(text("Thanks."))]))
                    .body)

            #expect(sent.map { $0["role"] } == ["user", "assistant", "user"])
            #expect(sent[1] == ["role": "assistant", "content": "Here's the chart."])
        }

        #if canImport(FoundationModels, _version: 2.1.14)
        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `a PDF goes as a named file part and WAV audio as input_audio, after their labels`() throws {
            let pdf = Transcript.DataAttachment(contentType: .pdf, content: Data("%PDF-1.4".utf8))
            let audio = Transcript.DataAttachment(contentType: .wav, content: Data("RIFF".utf8))
            let entry = prompt(.attachment(.init(content: .data(pdf), label: "Menu")), .attachment(.init(content: .data(audio))))

            let parts = messages(try ChatCompletionsSentRequest(generationRequest([entry])).body).first?["content"]

            #expect(
                parts == [
                    ["type": "text", "text": "Menu"],
                    ["type": "file", "file": ["filename": "Menu.pdf", "file_data": "data:application/pdf;base64,JVBERi0xLjQ="]],
                    ["type": "input_audio", "input_audio": ["data": "UklGRg==", "format": "wav"]],
                ])
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test(arguments: [(UTType.wav, "wav"), (.mp3, "mp3")])
        func `the format's audio goes as bare base64 with its format`(type: UTType, format: String) throws {
            let audio = Transcript.DataAttachment(contentType: type, content: Data([0x52, 0x49, 0x46, 0x46, 0x00, 0xFF]))
            let entry = prompt(.attachment(.init(content: .data(audio))))

            let parts = messages(try ChatCompletionsSentRequest(generationRequest([entry])).body).first?["content"]

            #expect(parts?[0] == ["type": "input_audio", "input_audio": ["data": "UklGRgD/", "format": .string(format)]])
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `text goes as text, after its label`() throws {
            let notes = Transcript.DataAttachment(contentType: .utf8PlainText, content: Data("Oats, 2 cups".utf8))
            let entry = prompt(text("Sum the calories."), .attachment(.init(content: .data(notes), label: "log")))

            let parts = messages(try ChatCompletionsSentRequest(generationRequest([entry])).body).first?["content"]

            #expect(
                parts == [
                    ["type": "text", "text": "Sum the calories."], ["type": "text", "text": "log"],
                    ["type": "text", "text": "Oats, 2 cups"],
                ])
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `generated data isn't sent back, while the answer's text is`() throws {
            let cat = Transcript.DataEntry(contentType: .png, content: Data([0x89, 0x50, 0x4E, 0x47]))
            let answer = Transcript.Response(assetIDs: [], segments: [text("Here's a cat.")])

            let sent = messages(
                try ChatCompletionsSentRequest(
                    generationRequest([prompt(text("Draw a cat.")), .data(cat), .response(answer), prompt(text("Which color is it?"))])
                )
                .body)

            #expect(sent.map { $0["role"] } == ["user", "assistant", "user"])
            #expect(sent[1] == ["role": "assistant", "content": "Here's a cat."])
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `data of a kind neither the format nor the provider has a part for throws`() {
            let movie = Transcript.DataAttachment(contentType: .mpeg4Movie, content: Data([1, 2]))

            #expect(throws: LanguageModelError.self) {
                try ChatCompletionsSentRequest(generationRequest([prompt(.attachment(.init(content: .data(movie))))]))
            }
        }
        #endif

        /// An answer to one prompt.
        private var answer: StubResponse {
            chatCompletionsEvents(["choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]]])
        }

        /// The messages of a request to a stub.
        private func sentMessages(_ stub: HTTPStub, _ index: Int) throws -> [JSONValue] {
            messages(try JSONValue(json: stub.requests[index].body))
        }

        /// The content parts of the last message of a stub's first request.
        private func parts(of stub: HTTPStub) throws -> [JSONValue] {
            guard case .array(let parts)? = try sentMessages(stub, 0).last?["content"] else { return [] }
            return parts
        }

        /// The image of an `image_url` part, which holds it as a data URL of a media type.
        private func decodedImage(_ part: JSONValue, mediaType: String) throws -> DecodedImage {
            let url = try #require(part["image_url"]?["url"]?.stringValue.flatMap(DataURL.init))
            #expect(url.mediaType == mediaType)
            return try #require(DecodedImage(url.data))
        }
    }
}
