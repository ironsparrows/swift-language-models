import Foundation
import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

extension ChatCompletionRequest {
    /// Prompt and tool-output attachments as the format's content parts.
    ///
    /// A label goes first, as a text part of its own, so the model can name the attachment, as an `ImageReference`
    /// does. Images go as JPEG data URLs in `image_url` parts, or as their web address when they have one. Data
    /// attachments go by kind: text as text, images as images, PDFs as `file` parts, WAV and MP3 audio as
    /// `input_audio` with its format, and the kinds of audio and movies the dialect adds as their parts. The dialect
    /// first checks that its models take the attachment. The same attachment gives the same bytes every time.
    struct AttachmentParts {
        /// The provider's name, for the errors.
        private let provider: String

        private let reader: AttachmentReader

        /// Checks that every model takes an attachment.
        private let check: (AttachmentKind, Transcript.Entry) throws(LanguageModelError) -> Void

        /// The kinds of audio and movies the format takes, then the ones the dialect adds, in the order they're
        /// matched.
        private let media: [MediaPart]

        init<Dialect: ChatCompletionsDialect>(dialect: Dialect) {
            provider = Dialect.name
            reader = AttachmentReader(provider: provider, encoding: dialect.imageEncoding)
            check = { (attachment, entry) throws(LanguageModelError) in try dialect.check(attachment, in: entry) }
            media = Self.formatMedia + Dialect.extraMedia
        }

        /// The kinds of audio `input_audio` takes in the format, WAV and MP3, each with its name.
        private static let formatMedia: [MediaPart] = [.audio(.wav, format: "wav"), .audio(.mp3, format: "mp3")]

        /// The parts for one attachment: its label, when it has one, then the attachment.
        ///
        /// - Throws: The dialect's errors for an attachment a model doesn't take, and
        ///   `LanguageModelError.unsupportedTranscriptContent` for one that can't be read or that neither the format
        ///   nor the dialect has a part for.
        func parts(for segment: Transcript.AttachmentSegment, in entry: Transcript.Entry) throws -> [Part] {
            let content = try reader.content(of: segment, in: entry) { (kind) throws(LanguageModelError) in try check(kind, entry) }
            return (segment.givenLabel.map { [.text($0)] } ?? []) + [try part(for: content, in: entry)]
        }

        /// The content part for an attachment's content: text, an `image_url`, a PDF `file`, or the part of the first
        /// kind of audio or movie it conforms to.
        private func part(for content: AttachmentReader.Content, in entry: Transcript.Entry) throws -> Part {
            switch content {
            case .text(let text):
                return .text(text)
            case .jpeg(let data):
                return .image(url: DataURL(mediaType: MediaType.jpeg, data: data).text)
            case .imageURL(let url):
                return .image(url: url.absoluteString)
            case .pdf(let data, let fileName):
                return .file(name: fileName, data: DataURL(mediaType: MediaType.pdf, data: data).text)
            case .data(let data, let type):
                switch media.first(where: { type.conforms(to: $0.contentType) })?.part {
                case .audio(let format)?:
                    return .audio(data: data.base64EncodedString(), format: format)
                case .video(let mediaType)?:
                    return .video(url: DataURL(mediaType: mediaType, data: data).text)
                case nil:
                    throw LanguageModelError.unsupported(entry, "\(provider) takes no attachments of type \(type.identifier).")
                }
            }
        }
    }
}
