import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

@Suite("Attachment reader", .timeLimit(.minutes(1)))
struct AttachmentReaderTests {
    /// Where an image attachment's pixels come from.
    enum Source: Sendable, CaseIterable {
        case pixels, file, data
    }

    /// The entry the errors name.
    private let entry = Transcript.Entry.prompt(Transcript.Prompt(segments: []))

    @Test func `images go no larger than 2,048 pixels on their longer side`() {
        #expect(AttachmentReader(provider: "Test").maximumImageSide == 2_048)
    }

    @Test func `the encoding's longest side and quality reach the JPEG`() throws {
        let image = try #require(TestImage.seven(size: 256))
        let read = { (encoding: ImageEncoding) throws -> Data in
            let reader = AttachmentReader(provider: "Test", encoding: encoding, cache: EncodedImageCache())
            guard case .jpeg(let data) = try reader.content(of: Transcript.ImageAttachment(image), in: entry) else { throw ReadError() }
            return data
        }

        let small = try read(ImageEncoding(maximumSide: 64))
        let rough = try read(ImageEncoding(maximumSide: 256, quality: 0.1))
        let fine = try read(ImageEncoding(maximumSide: 256, quality: 1))

        #expect(DecodedImage(small)?.width == 64)
        #expect(rough.count < fine.count)
        #expect(rough == EncodedImage(image, orientation: .up, maximumSide: 256, quality: 0.1)?.data)
    }

    @Test func `an image read at another quality is encoded on its own`() throws {
        let cache = EncodedImageCache()
        let image = try #require(TestImage.seven(size: 64))

        for quality in [0.5, 0.9, 0.5] {
            let reader = AttachmentReader(provider: "Test", encoding: ImageEncoding(quality: quality), cache: cache)
            _ = try reader.content(of: Transcript.ImageAttachment(image), in: entry)
        }

        #expect(cache.count == 2)
    }

    @Test(arguments: Source.allCases)
    func `an image is encoded once and gives the same bytes every time`(source: Source) throws {
        let cache = EncodedImageCache()
        let reader = AttachmentReader(provider: "Test", maximumImageSide: 64, cache: cache)
        let image = try #require(TestImage.seven(size: 128))
        let file = try #require(TestImage.file(of: image, as: .png))
        let url = try temporaryFile(file)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = { () throws -> AttachmentReader.Content in
            switch source {
            case .pixels: try reader.content(of: Transcript.ImageAttachment(image, orientation: .right), in: entry)
            case .file: try reader.content(of: Transcript.ImageAttachment(imageURL: url, orientation: .right), in: entry)
            case .data: try reader.content(of: file, type: .png, label: nil, in: entry)
            }
        }

        let first = try read()
        let second = try read()

        let expected =
            switch source {
            case .pixels: EncodedImage(image, orientation: .right, maximumSide: 64)
            case .file: EncodedImage(contentsOf: url, orientation: .right, maximumSide: 64)
            case .data: EncodedImage(data: file, maximumSide: 64)
            }
        #expect(first == .jpeg(try #require(expected).data))
        #expect(second == first)
        #expect(cache.count == 1)
    }

    @Test func `a kept image isn't encoded again`() {
        let cache = EncodedImageCache()
        let key = EncodedImageCache.Key(data: Data([1, 2, 3]), maximumSide: 64)
        var encodes = 0

        let first = cache.jpeg(for: key) {
            encodes += 1
            return Data([0xFF, 0xD8])
        }
        let second = cache.jpeg(for: key) {
            encodes += 1
            return Data([0xFF, 0xD9])
        }

        #expect(first == Data([0xFF, 0xD8]))
        #expect(second == first)
        #expect(encodes == 1)
    }

    @Test func `a file that changed is read and encoded again`() throws {
        let cache = EncodedImageCache()
        let reader = AttachmentReader(provider: "Test", cache: cache)
        let halves = try #require(TestImage.halves(width: 40, height: 20))
        let seven = try #require(TestImage.seven(size: 30))
        let url = try temporaryFile(try #require(TestImage.file(of: halves, as: .png)))
        defer { try? FileManager.default.removeItem(at: url) }
        let attachment = Transcript.ImageAttachment(imageURL: url, orientation: .up)
        let before = try reader.content(of: attachment, in: entry)

        try #require(TestImage.file(of: seven, as: .png)).write(to: url)
        let later = Date.now.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: url.path(percentEncoded: false))
        let after = try reader.content(of: attachment, in: entry)

        let changed = try #require(EncodedImage(contentsOf: url, orientation: .up, maximumSide: 2_048))
        #expect(after == .jpeg(changed.data))
        #expect(after != before)
        #expect((changed.width, changed.height) == (30, 30))
    }

    @Test func `the images used least recently go first once the cache holds too many`() {
        let cache = EncodedImageCache(entryLimit: 2)
        let keys = (1...3).map { EncodedImageCache.Key(data: Data([$0]), maximumSide: 64) }
        var encodes = 0
        let read = { (key: EncodedImageCache.Key) in
            _ = cache.jpeg(for: key) {
                encodes += 1
                return Data([0xFF])
            }
        }

        read(keys[0])
        read(keys[1])
        read(keys[0])
        read(keys[2])
        #expect(encodes == 3)
        #expect(cache.count == 2)

        read(keys[0])
        #expect(encodes == 3)
        read(keys[1])
        #expect(encodes == 4)
    }

    @Test func `the images used least recently go first once the cache holds too many bytes`() {
        let cache = EncodedImageCache(byteLimit: 10)
        let first = EncodedImageCache.Key(data: Data([1]), maximumSide: 64)
        let second = EncodedImageCache.Key(data: Data([2]), maximumSide: 64)
        var encodes = 0
        let read = { (key: EncodedImageCache.Key) in
            _ = cache.jpeg(for: key) {
                encodes += 1
                return Data(repeating: 0xFF, count: 6)
            }
        }

        read(first)
        read(second)
        read(second)
        read(first)

        #expect(encodes == 3)
        #expect(cache.count == 1)
    }

    @Test func `an emptied cache encodes its images again`() {
        let cache = EncodedImageCache()
        let key = EncodedImageCache.Key(data: Data([1]), maximumSide: 64)
        var encodes = 0
        let read = {
            _ = cache.jpeg(for: key) {
                encodes += 1
                return Data(repeating: 0xFF, count: 6)
            }
        }

        read()
        cache.removeAll()
        read()

        #expect(encodes == 2)
        #expect(cache.count == 1)
    }

    @Test func `an image over the byte limit on its own is encoded each time`() {
        let cache = EncodedImageCache(byteLimit: 4)
        let key = EncodedImageCache.Key(data: Data([1]), maximumSide: 64)
        var encodes = 0

        for _ in 1...2 {
            _ = cache.jpeg(for: key) {
                encodes += 1
                return Data(repeating: 0xFF, count: 6)
            }
        }

        #expect(encodes == 2)
        #expect(cache.count == 0)
    }

    @Test func `the decoded pixels a cache keeps alive count toward its byte limit`() throws {
        let image = try #require(TestImage.halves(width: 64, height: 64))
        let cache = EncodedImageCache(byteLimit: image.bytesPerRow * image.height)
        let reader = AttachmentReader(provider: "Test", cache: cache)

        _ = try reader.content(of: Transcript.ImageAttachment(image), in: entry)

        #expect(cache.count == 0)
    }

    @Test func `an image read with another longest side or orientation is encoded on its own`() throws {
        let cache = EncodedImageCache()
        let image = try #require(TestImage.halves(width: 128, height: 64))
        let large = AttachmentReader(provider: "Test", maximumImageSide: 64, cache: cache)
        let small = AttachmentReader(provider: "Test", maximumImageSide: 32, cache: cache)

        let sizes = try [
            (large, Transcript.ImageAttachment(image, orientation: .up)),
            (small, Transcript.ImageAttachment(image, orientation: .up)),
            (small, Transcript.ImageAttachment(image, orientation: .right)),
        ]
        .map { reader, attachment in
            guard case .jpeg(let data) = try reader.content(of: attachment, in: entry), let decoded = DecodedImage(data) else {
                throw ReadError()
            }
            return [decoded.width, decoded.height]
        }

        #expect(sizes == [[64, 32], [32, 16], [16, 32]])
        #expect(cache.count == 3)
    }

    @Test func `an image is matched by itself, not by what it shows`() throws {
        let cache = EncodedImageCache()
        let reader = AttachmentReader(provider: "Test", cache: cache)

        for _ in 1...2 {
            _ = try reader.content(of: Transcript.ImageAttachment(try #require(TestImage.seven(size: 32))), in: entry)
        }

        #expect(cache.count == 2)
    }

    @Test func `an image that can't be read isn't kept`() {
        let cache = EncodedImageCache()
        let reader = AttachmentReader(provider: "Test", cache: cache)
        var encodes = 0

        #expect(throws: LanguageModelError.self) { try reader.content(of: Data("not an image".utf8), type: .png, label: nil, in: entry) }
        for _ in 1...2 {
            _ = cache.jpeg(for: EncodedImageCache.Key(data: Data([1]), maximumSide: 64)) {
                encodes += 1
                return nil
            }
        }

        #expect(encodes == 2)
        #expect(cache.count == 0)
    }

    @Test(arguments: [(String?.none, "document.pdf"), ("Menu.PDF", "Menu.PDF"), ("week 3", "week 3.pdf")])
    func `a PDF's file name is its label, ending in pdf, or document`(label: String?, fileName: String) throws {
        let pdf = Data("%PDF-1.4".utf8)

        let content = try AttachmentReader(provider: "Test").content(of: pdf, type: .pdf, label: label, in: entry)

        #expect(content == .pdf(pdf, fileName: fileName))
    }

    @Test(arguments: [
        (UTType.utf8PlainText, "Oats, 2 cups", String.Encoding.utf8), (.commaSeparatedText, "food,kcal\negg,70", .utf8),
        (.utf16PlainText, "Grüße 👋🏽", .utf16), (.utf16PlainText, "Grüße", .utf16LittleEndian),
        (.utf16ExternalPlainText, "Grüße", .utf16), (.utf16ExternalPlainText, "Hi", .utf16BigEndian),
    ])
    func `text is decoded by its kind and byte-order mark`(type: UTType, text: String, encoding: String.Encoding) throws {
        let data = try #require(text.data(using: encoding))

        let content = try AttachmentReader(provider: "Test").content(of: data, type: type, label: nil, in: entry)

        #expect(content == .text(text))
    }

    @Test(arguments: [(UTType.png, Data("not an image".utf8)), (.utf8PlainText, Data([0xFF, 0xFE, 0xFD]))])
    func `data that can't be read as its kind is refused`(type: UTType, data: Data) throws {
        let reader = AttachmentReader(provider: "Test", cache: EncodedImageCache())

        try expectRefused { try reader.content(of: data, type: type, label: nil, in: entry) }
    }

    @Test func `an image at a web address that needs turning is refused, since only its pixels could be turned`() throws {
        let image = Transcript.ImageAttachment(imageURL: try #require(URL(string: "https://photos.invalid/cat.png")), orientation: .left)

        try expectRefused { try AttachmentReader(provider: "Test").content(of: image, in: entry) }
    }

    @Test func `a missing image file is refused instead of read`() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        let image = Transcript.ImageAttachment(imageURL: file, orientation: .up)

        try expectRefused { try AttachmentReader(provider: "Test", cache: EncodedImageCache()).content(of: image, in: entry) }
    }

    /// Expects an attachment to be refused as transcript content.
    private func expectRefused(_ read: () throws -> AttachmentReader.Content) throws {
        let error = try #require(throws: LanguageModelError.self) { try read() }

        guard case .unsupportedTranscriptContent = error else {
            Issue.record("Expected unsupported transcript content, got \(error)")
            return
        }
    }

    /// An image that didn't come back as JPEG that decodes.
    private struct ReadError: Error {}

    /// Writes bytes to a new temporary file.
    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}
