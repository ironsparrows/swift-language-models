import Foundation
import FoundationModels
import ImageIO
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenRouterLanguageModels

#if canImport(FoundationModels, _version: 2.1.14)
/// Kinds of audio only OpenRouter takes, each with its `input_audio` format.
private let audioFormats: [(UTType, String)] = [
    (.aiff, "aiff"), (.mpeg4Audio, "m4a"), (UTType("com.apple.m4a-audio"), "m4a"), (UTType("public.aac-audio"), "aac"),
    (UTType("org.xiph.flac"), "flac"), (UTType("org.xiph.ogg-audio"), "ogg"),
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
    ([.text], nil, .commaSeparatedText, true),
    ([.text], nil, .utf16PlainText, true),
    ([.text], nil, .utf16ExternalPlainText, true),
    ([.text], nil, .png, false),
    ([.text, .image], nil, .png, true),
    ([.text, .image], nil, .jpeg, true),
    ([.text, .image], nil, .heic, true),
    ([.text, .image], nil, .tiff, true),
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

extension OpenRouterExchangeTests {
    @Suite("Data attachments")
    struct DataAttachments {
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
            #expect(dataURL(content.last) == SentData(mediaType: mediaType, data: video))
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
            let stub = HTTPStub()
            let model = model(stub, inputs: inputs, fallbacks: fallbacks, options: OpenRouterOptions(pdfEngine: engine))
            let request = generationRequest([attachmentPrompt(.data(.init(contentType: type, content: Data([1, 2]))))])

            try await expectRefused { try await requestBody(request, model: model, stub: stub) }
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
}

#endif
