package import UniformTypeIdentifiers

/// The kind of an attachment, which a provider reads to check that its models take it.
package enum AttachmentKind: Sendable, Equatable {
    /// An image attachment.
    case image

    /// A data attachment of a content type, such as a PDF or audio.
    case data(UTType)
}

extension AttachmentKind {
    /// The kinds of data an image attachment may hold: those the system can read as an image.
    package static var readableImageTypes: Set<UTType> {
        EncodedImage.readableTypes
    }
}
