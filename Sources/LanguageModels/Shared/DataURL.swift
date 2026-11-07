package import Foundation

/// Bytes written inline as a URL, `data:<media type>;base64,<bytes>`, as chat APIs take attachments and return
/// generated images.
package struct DataURL: Sendable, Equatable {
    /// The media type of the bytes, such as `image/png`, without parameters.
    package let mediaType: String

    /// The bytes.
    package let data: Data

    /// A data URL for bytes of a media type.
    ///
    /// - Parameters:
    ///   - mediaType: The media type, such as `application/pdf`.
    ///   - data: The bytes.
    package init(mediaType: String, data: Data) {
        self.mediaType = mediaType
        self.data = data
    }

    /// Reads a base64 data URL, or fails for any other URL, a data URL that isn't base64, or bytes that aren't valid
    /// base64.
    ///
    /// - Parameter text: The URL, such as `data:image/png;base64,iVBORw0KGgo=`.
    package init?(_ text: String) {
        guard text.hasPrefix("data:"), let comma = text.firstIndex(of: ",") else { return nil }
        let header = text[text.index(text.startIndex, offsetBy: 5)..<comma].split(separator: ";", omittingEmptySubsequences: false)
        guard header.count > 1, header.last == "base64", let data = Data(base64Encoded: String(text[text.index(after: comma)...])) else {
            return nil
        }
        self.init(mediaType: String(header.first ?? ""), data: data)
    }

    /// The URL's text.
    package var text: String {
        "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
}
