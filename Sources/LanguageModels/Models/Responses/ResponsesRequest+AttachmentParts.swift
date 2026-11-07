import Foundation
import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

extension ResponsesRequest {
    /// Prompt and tool-output attachments as the format's input parts.
    ///
    /// A label goes first, as a text part of its own, so the model can name the attachment, as an `ImageReference`
    /// does. Images go as JPEG data URLs in `input_image` parts, or as their web address when they have one. Data
    /// attachments go by kind: text as text, images as images, and PDFs as `input_file` parts. The format has no part
    /// for other kinds, such as audio or video. The dialect first checks that its models take the attachment. The same
    /// attachment gives the same bytes every time.
    struct AttachmentParts {
        /// The provider's name, for the errors.
        private let provider: String

        private let reader: AttachmentReader

        /// Checks that every model takes an attachment.
        private let check: (AttachmentKind, Transcript.Entry) throws(LanguageModelError) -> Void

        init<Dialect: ResponsesDialect>(dialect: Dialect) {
            provider = Dialect.name
            reader = AttachmentReader(provider: provider, encoding: dialect.imageEncoding)
            check = { (attachment, entry) throws(LanguageModelError) in try dialect.check(attachment, in: entry) }
        }

        /// The parts for one attachment: its label, when it has one, then the attachment.
        ///
        /// - Throws: The dialect's errors for an attachment a model doesn't take, and
        ///   `LanguageModelError.unsupportedTranscriptContent` for one that can't be read or that the format has no
        ///   part for.
        func parts(for segment: Transcript.AttachmentSegment, in entry: Transcript.Entry) throws -> [Part] {
            let content = try reader.content(of: segment, in: entry) { (kind) throws(LanguageModelError) in try check(kind, entry) }
            return (segment.givenLabel.map { [.text($0)] } ?? []) + [try part(for: content, in: entry)]
        }

        /// The input part for an attachment's content: text, an `input_image` or a PDF `input_file`.
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
            case .data(_, let type):
                throw LanguageModelError.unsupported(entry, "\(provider) takes no attachments of type \(type.identifier).")
            }
        }
    }
}
