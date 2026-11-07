import Foundation
import FoundationModels
import LanguageModelsCore
import Testing
import UniformTypeIdentifiers

#if canImport(FoundationModels, _version: 2.1.14)
@Suite("File attachment")
final class FileAttachmentTests {
    private let folder = FileManager.default.temporaryDirectory.appending(
        path: "FileAttachmentTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    private let bytes = Data("Lease ends 2027-06-30.".utf8)

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `an attachment of bytes keeps them with their type`() {
        let attachment = FileAttachment(bytes, type: .pdf)

        #expect(attachment.transcriptRepresentation.content == bytes)
        #expect(attachment.transcriptRepresentation.contentType == .pdf)
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `an attachment from a transcript's keeps it whole, metadata included`() {
        let kept = Transcript.DataAttachment(contentType: .plainText, content: bytes, metadata: GeneratedContent(properties: ["page": 2]))

        #expect(FileAttachment(kept).transcriptRepresentation == kept)
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: [
        ("lease.pdf", UTType.pdf), ("LEASE.PDF", .pdf), ("notes.txt", .plainText), ("seven.wav", .wav), ("clip.mp4", .mpeg4Movie),
    ])
    func `a file's bytes come with the type its extension names`(name: String, type: UTType) throws {
        let file = try write(name)

        let attachment = try FileAttachment(contentsOf: file)

        #expect(attachment == FileAttachment(bytes, type: type))
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test(arguments: ["lease", "lease.xyzzy", "lease."])
    func `a file whose extension names no known type throws before it's read`(name: String) {
        let file = folder.appending(path: name)

        #expect(throws: FileAttachment.UnknownTypeError(url: file)) {
            try FileAttachment(contentsOf: file)
        }
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `a missing file of a known type throws the error reading it throws`() {
        let file = folder.appending(path: "missing.pdf")

        let error = #expect(throws: CocoaError.self) {
            try FileAttachment(contentsOf: file)
        }
        #expect(error?.code == .fileReadNoSuchFile)
    }

    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    @Test func `the unknown type error names the file`() {
        let error = FileAttachment.UnknownTypeError(url: folder.appending(path: "lease.xyzzy"))

        #expect(error.errorDescription == "The type of lease.xyzzy isn't known from its extension.")
    }

    /// Writes the bytes to a file of the given name in the test's folder.
    private func write(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: name)
        try bytes.write(to: file)
        return file
    }
}
#endif
