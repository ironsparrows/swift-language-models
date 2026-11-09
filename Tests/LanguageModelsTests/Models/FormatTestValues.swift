import CoreGraphics
import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

/// A text segment.
func text(_ content: String) -> Transcript.Segment {
    .text(.init(content: content))
}

/// Where an image attachment comes from.
enum ImageSource: Sendable, CaseIterable {
    case webAddress, file, pixels
}

/// Calls a body with an image from a source, and the web address its attachment kind carries, or `nil` for an image
/// whose pixels go. A file is removed once the body returns.
func withImage(from source: ImageSource, _ body: (Transcript.ImageAttachment, URL?) async throws -> Void) async throws {
    let pixels = try #require(TestImage.halves(width: 8, height: 8))
    switch source {
    case .webAddress:
        let address = try #require(URL(string: "https://photos.invalid/cat.png"))
        try await body(Transcript.ImageAttachment(imageURL: address), address)
    case .file:
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try #require(TestImage.file(of: pixels, as: .png)).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try await body(Transcript.ImageAttachment(imageURL: file), nil)
    case .pixels:
        try await body(Transcript.ImageAttachment(pixels), nil)
    }
}

/// The keys of an object, in order.
func keys(_ value: JSONValue?) -> [String] {
    if case .object(let object)? = value { object.members.map(\.key) } else { [] }
}

/// A model a request may reach.
struct Reached: ModelDetails {
    /// The id of a model a request may reach.
    struct ID: ProviderVocabulary {
        let rawValue: String
    }

    /// The day its provider stopped listing the model.
    var removedOn: Date?

    /// Confirms each read of ``removalDate``, which is how a request looks for a removed model.
    var reads: Confirmation?

    let id: ID = "vendor/model"
    let displayName = "Model"
    let capabilities = LanguageModelCapabilities([])
    let reasoning = ModelReasoning.unsupported
    let contextSize: Int? = nil
    let reasoningEfforts: [Efforts.Unsupported] = []
    let defaultReasoningEffort: Efforts.Unsupported? = nil
    var removalDate: Date? {
        reads?()
        return removedOn
    }
    let dataAttachmentTypes: Set<UTType> = []
    let dataEntryTypes: Set<UTType> = []
}
