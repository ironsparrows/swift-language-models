import Foundation
import FoundationModels
import ImageIO
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels
@testable import OpenRouterLanguageModels

#if canImport(FoundationModels, _version: 2.1.14)
/// Kinds of audio, each with its `input_audio` format.
private let audioFormats: [(UTType, String)] = [
    (.wav, "wav"), (.mp3, "mp3"), (.aiff, "aiff"), (.mpeg4Audio, "m4a"), (UTType("com.apple.m4a-audio"), "m4a"),
    (UTType("public.aac-audio"), "aac"), (UTType("org.xiph.flac"), "flac"), (UTType("org.xiph.ogg-audio"), "ogg"),
].compactMap { type, format in type.map { ($0, format) } }

/// Kinds of movie, each with the media type of its `video_url` data URL.
private let videoTypes: [(UTType, String)] = [
    (.mpeg4Movie, "video/mp4"), (.mpeg, "video/mpeg"), (.quickTimeMovie, "video/mov"),
    (UTType("org.webmproject.webm"), "video/webm"),
].compactMap { type, mediaType in type.map { ($0, mediaType) } }

/// Whether a model with the given inputs, and with or without the native PDF engine, takes a kind of attachment.
private let acceptedKinds: [(Set<OpenRouterInputModality>, OpenRouterOptions.PDFEngine?, UTType, Bool)] = [
    ([.text], nil, .pdf, true),
    ([.text], .native, .pdf, false),
    ([.text, .file], .native, .pdf, true),
    ([.text], nil, .utf8PlainText, true),
    ([.text], nil, .png, false),
    ([.text, .image], nil, .heic, true),
    ([.text, .image], nil, .image, false),
    ([.text], nil, .wav, false),
    ([.text, .audio], nil, .wav, true),
    ([.text, .audio], nil, .midi, false),
    ([.text, .video], nil, .mpeg4Movie, true),
    ([.text, .video], nil, .avi, false),
    ([.text, .image, .file, .audio, .video], nil, .zip, false),
]

/// Kinds of data a request refuses, with the inputs of the model and of its fallback, if any, and the PDF engine.
private let refusedAttachments: [(Set<OpenRouterInputModality>, Set<OpenRouterInputModality>?, OpenRouterOptions.PDFEngine?, UTType)] = [
    ([.text], nil, .native, .pdf),
    ([.text], nil, nil, .png),
    ([.text, .audio], [.text, .image], nil, .wav),
    ([.text, .image, .video], [.text, .image], nil, .mpeg4Movie),
    ([.text, .image, .file, .audio, .video], nil, nil, .zip),
]

@Suite("Executor: data attachments")
struct ExecutorDataAttachmentTests {
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a PDF goes as a file named by its label, after the label`() async throws {
        let stub = HTTPStub(events(text("Pancakes."), done()))
        let pdf = pdfDocument(showing: "Breakfast: pancakes")
        let session = LanguageModelSession(model: model(stub, inputs: [.text, .file]))

        _ = try await session.respond {
            "What's for breakfast?"
            FoundationModels.Attachment(FileAttachment(pdf, type: .pdf)).label("menu")
        }

        let content = parts(messages(try body(stub)).last)
        #expect(content.count == 3)
        #expect(content[1] == ["type": "text", "text": "menu"])
        #expect(content[2]["type"] == "file")
        #expect(content[2]["file"]?["filename"] == "menu.pdf")
        #expect(dataURL(content[2]) == DataURL(mediaType: "application/pdf", data: pdf))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [(String?.none, "document.pdf"), ("Menu.PDF", "Menu.PDF"), ("week 3", "week 3.pdf")])
    func `a PDF's file name is its label, ending in pdf, or document`(label: String?, fileName: String) async throws {
        let stub = HTTPStub(events(text("Hi"), done()))
        let attachment = FoundationModels.Attachment(FileAttachment(pdfDocument(showing: "Hi"), type: .pdf))
        let session = LanguageModelSession(model: model(stub, inputs: [.text, .file]))

        _ = try await session.respond { if let label { attachment.label(label) } else { attachment } }

        let file = parts(messages(try body(stub)).last).first { $0["type"] == "file" }
        #expect(file?["file"]?["filename"] == .string(fileName))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a model that can't read PDFs still takes one, which OpenRouter reads, with no plugin by default`() async throws {
        let stub = HTTPStub(events(text("Pancakes."), done()))
        let model = model(stub, inputs: [.text])
        #expect(try await model.supportsDataAttachmentType(.pdf))

        _ = try await LanguageModelSession(model: model).respond {
            "What's for breakfast?"
            FoundationModels.Attachment(FileAttachment(pdfDocument(showing: "Breakfast: pancakes"), type: .pdf))
        }

        let body = try body(stub)
        #expect(parts(messages(body).last).map { $0["type"] } == ["text", "file"])
        #expect(elements(body["plugins"]) == [["id": "context-compression", "enabled": false]])
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a PDF engine goes as the file parser plugin, only with a request that carries a PDF`() async throws {
        let stub = HTTPStub(events(text("Pancakes."), done()), events(text("Yes."), done()))
        let session = LanguageModelSession(model: model(stub, options: OpenRouterOptions(pdfEngine: .cloudflareAI)))

        _ = try await session.respond(to: "Hi")
        _ = try await session.respond { FoundationModels.Attachment(FileAttachment(pdfDocument(showing: "Breakfast"), type: .pdf)) }

        #expect(elements(try body(stub, 0)["plugins"]) == [["id": "context-compression", "enabled": false]])
        #expect(
            elements(try body(stub, 1)["plugins"]) == [
                ["id": "context-compression", "enabled": false], ["id": "file-parser", "pdf": ["engine": "cloudflare-ai"]],
            ]
        )
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: audioFormats)
    func `audio goes as bare base64 with its format`(type: UTType, format: String) async throws {
        let stub = HTTPStub(events(text("Seven."), done()))
        let audio = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0xFF])
        let session = LanguageModelSession(model: model(stub, inputs: [.text, .audio]))

        _ = try await session.respond {
            "Which number is said?"
            FoundationModels.Attachment(FileAttachment(audio, type: type))
        }

        let content = parts(messages(try body(stub)).last)
        #expect(
            content.last == [
                "type": "input_audio", "input_audio": ["data": .string(audio.base64EncodedString()), "format": .string(format)],
            ])
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: videoTypes)
    func `video goes as a data URL of OpenRouter's media type for it`(type: UTType, mediaType: String) async throws {
        let stub = HTTPStub(events(text("A seven."), done()))
        let video = Data("ftypisom".utf8)
        let session = LanguageModelSession(model: model(stub, inputs: [.text, .video]))

        _ = try await session.respond { FoundationModels.Attachment(FileAttachment(video, type: type)).label("clip") }

        let content = parts(messages(try body(stub)).last)
        #expect(content.map { $0["type"] } == ["text", "video_url"])
        #expect(dataURL(content.last) == DataURL(mediaType: mediaType, data: video))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [UTType.png, .jpeg, .heic, .tiff])
    func `an image file goes as an upright JPEG, as an image attachment does`(type: UTType) async throws {
        let stub = HTTPStub(events(text("Hi"), done()))
        let image = try #require(TestImage.halves(width: 40, height: 20))
        let file = try #require(TestImage.file(of: image, as: type, orientation: .left))
        let session = LanguageModelSession(model: model(stub, inputs: [.text, .image]))

        _ = try await session.respond { FoundationModels.Attachment(FileAttachment(file, type: type)) }

        let url = try #require(dataURL(parts(messages(try body(stub)).last).last))
        #expect(url.mediaType == "image/jpeg")
        let decoded = try #require(DecodedImage(url.data))
        #expect((decoded.width, decoded.height) == (20, 40))
        #expect(decoded.isRed(x: 10, y: 35))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [
        (UTType.utf8PlainText, "Oats, 2 cups", String.Encoding.utf8), (.commaSeparatedText, "food,kcal\negg,70", .utf8),
        (.utf16PlainText, "Grüße 👋🏽", .utf16), (.utf16PlainText, "Grüße", .utf16LittleEndian),
        (.utf16ExternalPlainText, "Grüße", .utf16), (.utf16ExternalPlainText, "Hi", .utf16BigEndian),
    ])
    func `text goes as text`(type: UTType, content: String, encoding: String.Encoding) async throws {
        let stub = HTTPStub(events(text("Hi"), done()))
        let data = try #require(content.data(using: encoding))
        let session = LanguageModelSession(model: model(stub))

        _ = try await session.respond {
            "Sum the calories."
            FoundationModels.Attachment(FileAttachment(data, type: type)).label("log")
        }

        #expect(
            parts(messages(try body(stub)).last) == [
                ["type": "text", "text": "Sum the calories."], ["type": "text", "text": "log"], ["type": "text", "text": .string(content)],
            ]
        )
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: refusedAttachments)
    func `the request refuses data that the model or a fallback doesn't take, images included, as a session does`(
        inputs: Set<OpenRouterInputModality>,
        fallbackInputs: Set<OpenRouterInputModality>?,
        engine: OpenRouterOptions.PDFEngine?,
        type: UTType
    ) async throws {
        let fallbacks = fallbackInputs.map { [fallback(inputs: $0)] } ?? []
        let model = model(HTTPStub(), inputs: inputs, fallbacks: fallbacks, options: OpenRouterOptions(pdfEngine: engine))

        try await expectRefused {
            try requestBody([attachmentPrompt(.data(.init(contentType: type, content: Data([1, 2]))))], model: model)
        }
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [(UTType.png, Data("not an image".utf8)), (.utf8PlainText, Data([0xFF, 0xFE, 0xFD]))])
    func `data of a kind the model takes is refused when it can't be read as that kind`(type: UTType, data: Data) async throws {
        let model = model(HTTPStub(), inputs: [.text, .image])

        try await expectRefused { try requestBody([attachmentPrompt(.data(.init(contentType: type, content: data)))], model: model) }
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a kind no input takes is refused through the session before any request`() async throws {
        let stub = HTTPStub(events(text("Hi"), done()))
        let session = LanguageModelSession(model: model(stub, inputs: [.text, .image, .file, .audio, .video]))

        try await expectRefused {
            try await session.respond { FoundationModels.Attachment(FileAttachment(Data([0x50, 0x4B]), type: .zip)) }
        }
        #expect(stub.requests.isEmpty)
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: acceptedKinds)
    func `a kind of attachment is supported exactly when the request takes it`(
        inputs: Set<OpenRouterInputModality>,
        engine: OpenRouterOptions.PDFEngine?,
        type: UTType,
        isSupported: Bool
    ) async throws {
        let model = model(HTTPStub(), inputs: inputs, options: OpenRouterOptions(pdfEngine: engine))

        #expect(try await model.supportsDataAttachmentType(type) == isSupported)
    }

    /// Expects a data attachment to be refused as transcript content.
    private func expectRefused(_ work: () async throws -> some Any) async throws {
        let error = try await #require(throws: LanguageModelError.self) { _ = try await work() }
        guard case .unsupportedTranscriptContent = error else {
            Issue.record("Expected unsupported transcript content, got \(error)")
            return
        }
    }
}
#endif
