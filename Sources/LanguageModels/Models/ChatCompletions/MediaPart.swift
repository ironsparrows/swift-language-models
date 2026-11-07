package import UniformTypeIdentifiers

/// A kind of data a provider takes beyond the format's, and the content part it goes in.
package struct MediaPart: Sendable {
    /// The part a kind of data goes in.
    enum Part: Sendable, Equatable {
        /// An `input_audio` part, with the provider's name for the format.
        case audio(format: String)

        /// A `video_url` part, holding the movie as a data URL of the media type.
        case video(mediaType: String)
    }

    /// The kind of data, which the attachment's content type conforms to.
    let contentType: UTType

    let part: Part

    /// Audio of a kind, sent as `input_audio` with the format's name.
    package static func audio(_ contentType: UTType, format: String) -> Self {
        Self(contentType: contentType, part: .audio(format: format))
    }

    /// A movie of a kind, sent as a `video_url` data URL of the media type.
    package static func video(_ contentType: UTType, mediaType: String) -> Self {
        Self(contentType: contentType, part: .video(mediaType: mediaType))
    }
}
