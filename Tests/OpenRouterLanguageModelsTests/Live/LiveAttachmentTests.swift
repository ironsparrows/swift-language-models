import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing
import UniformTypeIdentifiers

/// Attachments sent to real models through OpenRouter: what each host makes of the parts this package sends. Each
/// test costs under $0.0002, except the generated image, which costs about $0.004.
@diagnose(DeprecatedDeclaration, as: warning)
@Suite(
    "Live: attachments",
    .tags(.live),
    .requiresAPIKey("OPENROUTER_API_KEY"),
    .skipsUnavailableHosts,
    .timeLimit(.minutes(2))
)
struct LiveAttachmentTests {
    /// A response limit for answers of a word.
    static let short = GenerationOptions(maximumResponseTokens: 64)

    /// The question for an image or video of the digit.
    static let digitQuestion = "Which digit is shown? Reply with the digit only."

    @Test(arguments: [
        LiveModel(.openaiGpt4_1Nano), LiveModel(.googleGemini2_5FlashLite),
        LiveModel(.anthropicClaudeHaiku5_5),
    ])
    func `a model reads a drawn digit`(model: LiveModel) async throws {
        let image = try #require(TestImage.seven(size: 256))

        let answer = try await respond(model) {
            Self.digitQuestion
            FoundationModels.Attachment(image).label("digit")
        }

        #expect(answer.contains("7"))
    }

    @Test func `a free model with every input reads a drawn digit`() async throws {
        let image = try #require(TestImage.seven(size: 256))

        do {
            let answer = try await respond(LiveModel(.nvidiaNemotron3NanoOmni30bA3bReasoningFree)) {
                Self.digitQuestion
                FoundationModels.Attachment(image)
            }
            #expect(answer.contains("7"))
        } catch LanguageModelError.rateLimited {
            try Test.cancel("The free model's daily quota is used up.")
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [
        (LiveModel(.openaiGpt4_1Nano), UTType.png), (LiveModel(.googleGemini2_5FlashLite), .jpeg),
        (LiveModel(.anthropicClaudeHaiku5_5), .heic),
    ])
    func `a model reads a digit from an image file`(model: LiveModel, type: UTType) async throws {
        let image = try #require(TestImage.seven(size: 256))
        let file = try #require(TestImage.file(of: image, as: type))

        let answer = try await respond(model) {
            Self.digitQuestion
            FoundationModels.Attachment(FileAttachment(file, type: type))
        }

        #expect(answer.contains("7"))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [
        LiveModel(.openaiGpt4_1Nano), LiveModel(.googleGemini2_5FlashLite),
        LiveModel(.mistralaiMistralNemo, options: OpenRouterOptions(pdfEngine: .cloudflareAI)),
    ])
    func `a model reads a word from a PDF, natively or parsed by OpenRouter`(model: LiveModel) async throws {
        let pdf = pdfDocument(showing: "The secret word is PELICAN.")

        let answer = try await respond(model) {
            "What is the secret word in the document? Reply with the word only."
            FoundationModels.Attachment(FileAttachment(pdf, type: .pdf)).label("note")
        }

        #expect(answer.localizedCaseInsensitiveContains("pelican"))
    }

    /// Gemini 2.5 Flash rather than Flash-Lite, which often mishears the number. Voxtral is left out for M4A: Mistral's
    /// host takes only WAV and MP3, and says so in a 400.
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [
        (LiveModel(.googleGemini2_5Flash), "seven.wav", UTType.wav),
        (LiveModel(.googleGemini2_5Flash), "seven.m4a", .mpeg4Audio),
        (LiveModel(.mistralaiVoxtralSmall24b2507), "seven.wav", .wav),
    ])
    func `a model hears a spoken number`(model: LiveModel, fixture: String, type: UTType) async throws {
        let audio = try Bundle.module.fixture(fixture)

        let answer = try await respond(model) {
            // A transcript is steadier than asking for the digit, which one model once answered with "1".
            "Transcribe this audio exactly."
            FoundationModels.Attachment(FileAttachment(audio, type: type))
        }

        #expect(answer.contains("7") || answer.localizedCaseInsensitiveContains("seven"))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [LiveModel(.qwenQwen3_7Flash), LiveModel(.googleGemini2_5FlashLite)])
    func `a model watches a digit in a video`(model: LiveModel) async throws {
        let video = try Bundle.module.fixture("seven.mp4")

        let answer = try await respond(model) {
            "Which digit is shown in the video? Reply with the digit only."
            FoundationModels.Attachment(FileAttachment(video, type: .mpeg4Movie))
        }

        #expect(answer.contains("7") || answer.localizedCaseInsensitiveContains("seven"))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a text-only model takes only PDFs, which OpenRouter reads for it`() async throws {
        let model = LiveModel(.mistralaiMistralNemo).languageModel

        #expect(!model.capabilities.contains(.vision))
        #expect(try await model.supportsDataAttachmentType(.pdf))
        for type in [UTType.png, .wav, .mpeg4Movie] {
            #expect(try await !model.supportsDataAttachmentType(type))
        }
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a model that generates images returns one as a data entry`() async throws {
        let model = LiveModel(.googleGemini2_5FlashImage)
        let session = LanguageModelSession(model: model.languageModel)

        let response = try await session.respond(to: "Draw a small red circle on a white background.")

        let images = response.transcriptEntries.compactMap { entry -> Transcript.DataEntry? in
            if case .data(let data) = entry { data } else { nil }
        }
        Testing.Attachment.record(String(describing: images.map(\.contentType)), named: "images.txt")
        let image = try #require(images.first)
        #expect(image.contentType.conforms(to: .image))
        #expect(DecodedImage(image.content) != nil)
    }
    #endif

    /// Sends one prompt through a new session, with the answer recorded.
    ///
    /// - Returns: The answer's text.
    private func respond(_ model: LiveModel, @PromptBuilder prompt: () throws -> Prompt) async throws -> String {
        let session = LanguageModelSession(model: model.languageModel)
        let response = try await session.respond(
            options: Self.short, contextOptions: model.quickContextOptions, metadata: [:], prompt: prompt)
        Testing.Attachment.record(response.content, named: "answer.txt")
        return response.content
    }
}

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveModel {
    /// Reasoning off where the model reasons by default, so the answer comes quickly and cheaply.
    fileprivate var quickContextOptions: ContextOptions {
        details.reasoning == .onByDefault ? ContextOptions(reasoningLevel: .off) : ContextOptions()
    }
}
