import Foundation
import Testing

@testable import LanguageModels

@Suite("Byte lines", .timeLimit(.minutes(1)))
struct ByteLinesTests {
    @Test func `lines split at line feeds, carriage returns and the pair of both`() async throws {
        let bytes = Array("one\r\ntwo\rthree\n\r\rlast".utf8)

        var lines: [String] = []
        for try await line in ByteLines(bytes.async) { lines.append(line) }

        #expect(lines == ["one", "two", "three", "", "", "last"])
    }

    @Test(arguments: ["\u{2028}", "\u{2029}", "\u{85}"])
    func `a Unicode line break stays inside its line`(lineBreak: String) async throws {
        var lines: [String] = []
        for try await line in ByteLines(Array("a\(lineBreak)b\n".utf8).async) { lines.append(line) }

        #expect(lines == ["a\(lineBreak)b"])
    }

    @Test func `a stream ending in a line feed has no empty last line`() async throws {
        var lines: [String] = []
        for try await line in ByteLines(Array("a\nb\n".utf8).async) { lines.append(line) }

        #expect(lines == ["a", "b"])
    }
}

extension Array where Element == UInt8 {
    /// The bytes as an async sequence, like a response body.
    fileprivate var async: AsyncStream<UInt8> {
        let (stream, continuation) = AsyncStream.makeStream(of: UInt8.self)
        for byte in self { continuation.yield(byte) }
        continuation.finish()
        return stream
    }
}
