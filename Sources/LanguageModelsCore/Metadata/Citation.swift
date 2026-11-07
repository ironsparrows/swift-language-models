public import Foundation
package import FoundationModels

/// A web page that an answer cites.
///
/// The response entry of an answer that cites pages lists them in its metadata, under
/// ``LanguageModelMetadataKey/citations``, and a provider module's reader of that metadata reads them as citations.
public struct Citation: Sendable, Hashable {
    /// The page's address.
    public let url: URL

    /// The page's title, when the search reported one.
    public let title: String?

    /// Text from the page that the search returned to the model, which `[...]` separates when it comes from different
    /// parts of the page.
    public let excerpt: String?

    /// Where the text that cites the page starts in the answer's text, as an offset, when the service reported it.
    ///
    /// Services pass on their host's offset without saying what it counts, characters, UTF-16 code units or bytes, so
    /// check that it falls within the text before using it.
    public let startOffset: Int?

    /// Where the text that cites the page ends in the answer's text, as an offset in the same unit as
    /// ``startOffset``, when the service reported it.
    ///
    /// Whether it's the offset of the last cited character or of the one after it isn't documented either.
    public let endOffset: Int?

    /// Creates a citation, such as for a preview or a test.
    ///
    /// - Parameters:
    ///   - url: The page's address.
    ///   - title: The page's title.
    ///   - excerpt: Text from the page that the search returned to the model.
    ///   - startOffset: Where the text that cites the page starts in the answer's text.
    ///   - endOffset: Where the text that cites the page ends in the answer's text.
    public init(url: URL, title: String? = nil, excerpt: String? = nil, startOffset: Int? = nil, endOffset: Int? = nil) {
        self.url = url
        self.title = title
        self.excerpt = excerpt
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

extension Citation {
    /// The citation as a value of an entry's metadata.
    package var metadataValue: GeneratedContent {
        GeneratedContent(properties: [
            Field.url: url.absoluteString,
            Field.title: title,
            Field.excerpt: excerpt,
            Field.startOffset: startOffset,
            Field.endOffset: endOffset,
        ])
    }

    /// A citation read back from an entry's metadata, or `nil` when the value has no valid URL.
    ///
    /// - Parameter content: One element of the list under ``LanguageModelMetadataKey/citations``.
    package init?(metadataValue content: GeneratedContent) {
        guard let address = try? content.value(String.self, forProperty: Field.url), let url = URL(string: address) else {
            return nil
        }
        self.init(
            url: url,
            title: try? content.value(String?.self, forProperty: Field.title),
            excerpt: try? content.value(String?.self, forProperty: Field.excerpt),
            startOffset: try? content.value(Int?.self, forProperty: Field.startOffset),
            endOffset: try? content.value(Int?.self, forProperty: Field.endOffset)
        )
    }

    /// The names of a citation's fields in an entry's metadata.
    private enum Field {
        static let url = "url"
        static let title = "title"
        static let excerpt = "excerpt"
        static let startOffset = "startOffset"
        static let endOffset = "endOffset"
    }
}
