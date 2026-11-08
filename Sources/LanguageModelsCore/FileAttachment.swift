// FoundationModels 2.1.14 comes with Xcode 27.2, the first SDK with data attachments and data entries.
#if canImport(FoundationModels, _version: 2.1.14)
public import Foundation
public import FoundationModels
public import UniformTypeIdentifiers

/// The bytes of a file, such as a PDF, audio, video or text, and their type, as a prompt's data attachment.
///
/// Foundation Models takes data attachments of any type that conforms to `DataAttachmentRepresentable`. This one wraps
/// bytes you already have, or reads a file and tells its type from its extension:
///
/// ```swift
/// let lease = try FileAttachment(contentsOf: leaseURL)
/// let response = try await session.respond {
///     "When does the lease end?"
///     Attachment(lease).label("lease.pdf")
/// }
/// ```
///
/// Whether a model takes the type is up to the model; `supportsDataAttachmentType(_:)` says.
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
public struct FileAttachment: DataAttachmentRepresentable, Equatable {
    /// The attachment as the transcript keeps it.
    public let transcriptRepresentation: Transcript.DataAttachment

    /// Creates an attachment from one a transcript keeps.
    ///
    /// - Parameter attachment: The attachment, with its bytes, type and metadata.
    public init(_ attachment: Transcript.DataAttachment) {
        transcriptRepresentation = attachment
    }

    /// Creates an attachment of bytes of a type.
    ///
    /// - Parameters:
    ///   - data: The bytes.
    ///   - type: Their type, such as `UTType.pdf`.
    public init(_ data: Data, type: UTType) {
        self.init(Transcript.DataAttachment(contentType: type, content: data))
    }

    /// Creates an attachment of a file's bytes, of the type its extension names, such as PDF for `lease.pdf`.
    ///
    /// - Parameter url: The file's URL.
    /// - Throws: ``UnknownTypeError`` when the extension names no type the system knows, before the file is read, or
    ///   the error that reading the file throws.
    public init(contentsOf url: URL) throws {
        // An unknown extension still gets a dynamic type, which says nothing about the bytes.
        guard let type = UTType(filenameExtension: url.pathExtension), !type.isDynamic else {
            throw UnknownTypeError(url: url)
        }
        self.init(try Data(contentsOf: url), type: type)
    }
}

@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
extension FileAttachment {
    /// The error that ``FileAttachment/init(contentsOf:)`` throws when the file's extension names no type the system
    /// knows, such as for a file without one.
    ///
    /// Pass the type yourself with ``FileAttachment/init(_:type:)``.
    public struct UnknownTypeError: Error, Sendable, Equatable, LocalizedError {
        /// The file whose type is unknown.
        public let url: URL

        /// Creates an error for a file whose type is unknown, such as for a test.
        ///
        /// - Parameter url: The file.
        public init(url: URL) {
            self.url = url
        }

        /// Says which file's type is unknown.
        public var errorDescription: String? {
            "The type of \(url.lastPathComponent) isn't known from its extension."
        }
    }
}
#endif
