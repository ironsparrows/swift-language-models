package import UniformTypeIdentifiers

/// The kind of an attachment, which a dialect's `check(_:in:)` hook reads to check that its models take it.
package enum AttachmentKind: Sendable, Equatable {
    /// An image attachment.
    case image

    /// A data attachment of a content type, such as a PDF or audio.
    case data(UTType)
}
