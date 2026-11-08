import Foundation
import FoundationModels
import LanguageModelsCore
import Testing

@Suite("Citations")
struct CitationTests {
    @Test func `a citation built with only its address leaves the rest unknown`() throws {
        let url = try #require(URL(string: "https://swift.org/blog/"))

        let citation = Citation(url: url)

        #expect(citation.url == url)
        #expect(citation.title == nil)
        #expect(citation.excerpt == nil)
        #expect(citation.startOffset == nil)
        #expect(citation.endOffset == nil)
    }

    @Test func `a citation built with every field reads back from an entry's metadata unchanged`() throws {
        let citation = Citation(
            url: try #require(URL(string: "https://swift.org/blog/swift-6.4")), title: "Swift 6.4 Released",
            excerpt: "Swift 6.4 is now available.", startOffset: 0, endOffset: 18)

        let metadata = ProviderResponseMetadata(citations: [citation]).channelMetadata.mapValues { $0.generatedContent }
        #expect(ProviderResponseMetadata(metadata).citations == [citation])
    }
}
