// snippet.hide
import CoreGraphics
import Foundation
import FoundationModels
import OpenAICompatibleLanguageModels
import UniformTypeIdentifiers

func image(session: LanguageModelSession, receipt: CGImage) async throws {
    // snippet.show
    // snippet.image
    let response = try await session.respond {
        "What did I spend on dinner?"
        Attachment(receipt).label("receipt")
    }
    // snippet.end
    // snippet.hide
    _ = response
}

func kinds() {
    // swift-format-ignore: NeverForceUnwrap
    let provider = OpenAICompatibleProvider(name: "Gateway", url: URL(string: "https://llm.example.com/v1")!)
    // snippet.show
    // snippet.kinds
    // A model that reads PDFs and plain text besides images.
    let details = OpenAICompatibleModel("my-model", on: provider, attachments: [.image, .pdf, .plainText])
    print(details.supportsDataAttachmentType(.pdf))  // true
    print(details.supportsDataAttachmentType(.wav))  // false
    // snippet.end
}

// FoundationModels 2.1.14 comes with Xcode 27.2, the first SDK with data attachments.
#if canImport(FoundationModels, _version: 2.1.14)
// snippet.show
// snippet.file
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
func leaseEnd(of lease: URL, in session: LanguageModelSession) async throws -> String {
    let file = try FileAttachment(contentsOf: lease)
    let response = try await session.respond {
        "When does the lease end?"
        Attachment(file).label(lease.lastPathComponent)
    }
    return response.content
}
// snippet.end
// snippet.hide
#endif
