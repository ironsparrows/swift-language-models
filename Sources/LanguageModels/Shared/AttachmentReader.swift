import Foundation
import FoundationModels
import ImageIO
import LanguageModelsCore
package import UniformTypeIdentifiers

// MARK: - Reader

/// Reads a transcript's attachments into what a provider sends: images upright as JPEG, or at their web address, text
/// as text, PDFs with a file name, and any other kind as its data. The same attachment gives the same bytes every time.
///
/// Images are encoded once and then kept in a cache, so the images a transcript sends again with each request aren't
/// decoded and encoded each time.
struct AttachmentReader {
    /// What an attachment holds, ready for a provider's content part.
    enum Content: Equatable {
        /// An image's pixels, upright and scaled down to the reader's longest side, as JPEG.
        case jpeg(Data)
        /// An image at an http or https address, already upright.
        case imageURL(URL)
        case text(String)
        /// A PDF document, with a file name that ends in `.pdf`.
        case pdf(Data, fileName: String)
        /// Data of another kind, such as audio or video.
        case data(Data, type: UTType)
    }

    /// The longest side, in pixels, of an image sent as data. A larger image is scaled down to it.
    var maximumImageSide: Int { encoding.encodedMaximumSide }

    /// How images sent as data are encoded: their longest side and JPEG quality.
    private let encoding: ImageEncoding

    /// The provider's name, for the errors.
    private let provider: String

    /// Where encoded images are kept.
    private let cache: EncodedImageCache

    /// - Parameters:
    ///   - provider: The provider's name, as the errors name it.
    ///   - encoding: How images sent as data are encoded, such as the provider's configuration says.
    ///   - cache: Where encoded images are kept, by default the cache that every request shares.
    init(provider: String, encoding: ImageEncoding = .standard, cache: EncodedImageCache = .shared) {
        self.provider = provider
        self.encoding = encoding
        self.cache = cache
    }

    /// The JPEG quality of an image sent as data.
    private var quality: Double { encoding.encodedQuality }

    /// An attachment's content, once the provider checked that its models take it: an image's, or a data attachment's.
    ///
    /// - Parameters:
    ///   - segment: The attachment.
    ///   - entry: The entry that carries it, which the errors name.
    ///   - check: Checks that the models take the attachment, before it's read.
    /// - Returns: What the attachment holds.
    /// - Throws: What `check` throws, and `LanguageModelError.unsupportedTranscriptContent` for an attachment that
    ///   can't be read or of a kind the package doesn't know.
    func content(
        of segment: Transcript.AttachmentSegment,
        in entry: Transcript.Entry,
        checking check: (AttachmentKind) throws(LanguageModelError) -> Void
    ) throws -> Content {
        switch segment.content {
        case .image(let image):
            try check(.image)
            return try content(of: image, in: entry)
        default:
            #if canImport(FoundationModels, _version: 2.1.14)
            if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *), case .data(let attachment) = segment.content {
                try check(.data(attachment.contentType))
                return try content(of: attachment.content, type: attachment.contentType, label: segment.givenLabel, in: entry)
            }
            #endif
            throw LanguageModelError.unsupported(entry, "\(provider) can't take this kind of attachment.")
        }
    }

    /// An image attachment's content: its web address, or its pixels upright as JPEG.
    ///
    /// A file is read here rather than through the attachment's pixels, which a missing file has none of.
    ///
    /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for an image that can't be read, or at an address
    ///   that isn't http or https, or that isn't upright.
    func content(of image: Transcript.ImageAttachment, in entry: Transcript.Entry) throws -> Content {
        switch image.url {
        case let url? where url.isFileURL:
            let orientation = image.orientation
            let key = EncodedImageCache.Key(file: url, orientation: orientation, maximumSide: maximumImageSide, quality: quality)
            return try jpeg(key, in: entry) {
                EncodedImage(contentsOf: url, orientation: orientation, maximumSide: maximumImageSide, quality: quality)
            }
        case let url?:
            guard ["http", "https"].contains(url.scheme?.lowercased()) else {
                throw LanguageModelError.unsupported(entry, "\(provider) takes images only at http and https addresses.")
            }
            guard image.orientation == .up else {
                throw LanguageModelError.unsupported(
                    entry, "\(provider) can't turn an image at a web address upright; attach the image itself instead.")
            }
            return .imageURL(url)
        case nil:
            let (pixels, orientation) = (image.cgImage, image.orientation)
            // An attachment made from a pixel buffer draws a new image each time it's asked, which the cache could only
            // keep alive, never find again.
            let key =
                pixels === image.cgImage
                ? EncodedImageCache.Key(image: pixels, orientation: orientation, maximumSide: maximumImageSide, quality: quality) : nil
            return try jpeg(key, in: entry) {
                EncodedImage(pixels, orientation: orientation, maximumSide: maximumImageSide, quality: quality)
            }
        }
    }

    /// A data attachment's content: text decoded, an image as JPEG, a PDF named by its label, or `document.pdf` without
    /// one, and any other kind as its data.
    ///
    /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for text or an image that can't be read.
    func content(of data: Data, type: UTType, label: String?, in entry: Transcript.Entry) throws -> Content {
        if type.conforms(to: .plainText) {
            guard let text = String(data: data, encoding: Self.textEncoding(of: data, type: type)) else {
                throw LanguageModelError.unsupported(entry, "The text attachment isn't valid \(type.identifier).")
            }
            return .text(text)
        }
        if EncodedImage.readableTypes.contains(where: { type.conforms(to: $0) }) {
            return try jpeg(EncodedImageCache.Key(data: data, maximumSide: maximumImageSide, quality: quality), in: entry) {
                EncodedImage(data: data, maximumSide: maximumImageSide, quality: quality)
            }
        }
        if type.conforms(to: .pdf) {
            let name = label ?? "document"
            return .pdf(data, fileName: name.lowercased().hasSuffix(".pdf") ? name : "\(name).pdf")
        }
        return .data(data, type: type)
    }

    /// The encoding of a text attachment: UTF-16 for the UTF-16 kinds, in the byte order its byte-order mark names, or
    /// without one, native order for the plain kind and big-endian for the external kind; UTF-8 for every other kind.
    private static func textEncoding(of data: Data, type: UTType) -> String.Encoding {
        let hasByteOrderMark = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        if type.conforms(to: .utf16ExternalPlainText) { return .utf16 }
        if type.conforms(to: .utf16PlainText) { return hasByteOrderMark ? .utf16 : .utf16LittleEndian }
        return .utf8
    }

    /// An image's JPEG content, from the cache, or encoded and kept there.
    ///
    /// - Parameters:
    ///   - key: What the image is kept by, or `nil` to encode it without keeping it.
    ///   - entry: The entry that carries the image, which the error names.
    ///   - encode: Encodes the image, or gives `nil` when it can't be read or encoded.
    /// - Returns: The image's JPEG content.
    /// - Throws: `LanguageModelError.unsupportedTranscriptContent` when the image couldn't be read or encoded.
    private func jpeg(_ key: EncodedImageCache.Key?, in entry: Transcript.Entry, encode: () -> EncodedImage?) throws -> Content {
        guard let data = cache.jpeg(for: key, encode: { encode()?.data }) else {
            throw LanguageModelError.unsupported(entry, "The image couldn't be read or encoded as JPEG.")
        }
        return .jpeg(data)
    }
}

extension Transcript.AttachmentSegment {
    /// The attachment's label, or `nil` when it has none or an empty one.
    var givenLabel: String? {
        label.flatMap { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - Kinds

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

// MARK: - Data URLs

/// Bytes written inline as a URL, `data:<media type>;base64,<bytes>`, as provider APIs take attachments and return
/// generated images.
struct DataURL: Sendable, Equatable {
    /// The media type of the bytes, such as `image/png`, without parameters.
    let mediaType: String

    /// The bytes.
    let data: Data

    /// A data URL for bytes of a media type.
    ///
    /// - Parameters:
    ///   - mediaType: The media type, such as `application/pdf`.
    ///   - data: The bytes.
    init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }

    /// Reads a base64 data URL, or fails for any other URL, a data URL that isn't base64, or bytes that aren't valid
    /// base64.
    ///
    /// - Parameter text: The URL, such as `data:image/png;base64,iVBORw0KGgo=`.
    init?(_ text: String) {
        guard text.hasPrefix("data:"), let comma = text.firstIndex(of: ",") else { return nil }
        let header = text[text.index(text.startIndex, offsetBy: 5)..<comma].split(separator: ";", omittingEmptySubsequences: false)
        guard header.count > 1, header.last == "base64", let data = Data(base64Encoded: String(text[text.index(after: comma)...])) else {
            return nil
        }
        self.init(mediaType: String(header.first ?? ""), data: data)
    }

    /// The URL's text.
    var text: String {
        "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
}
