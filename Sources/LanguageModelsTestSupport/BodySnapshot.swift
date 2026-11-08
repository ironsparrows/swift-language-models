package import Foundation
package import InlineSnapshotTesting
import Testing

/// A JSON body's bytes with one member per line.
///
/// Only whitespace outside strings is added, so removing it gives the bytes back: member order, escapes and number
/// spellings are the body's own.
enum BodySnapshot {
    /// A body that isn't compact JSON: it has whitespace outside its strings, which removing the added whitespace wouldn't
    /// give back, or a bracket that closes nothing.
    struct NotCompact: Error {}

    /// The text of a compact JSON body, one member per line.
    ///
    /// - Parameter body: A JSON body without whitespace outside its strings.
    /// - Returns: The body's bytes with whitespace added outside its strings.
    /// - Throws: ``NotCompact`` when the body has whitespace outside its strings, or a bracket that closes nothing.
    static func text(of body: Data) throws -> String {
        let bytes = Array(body)
        var output: [UInt8] = []
        var depth = 0
        var strings = StringTracker()
        var previous: UInt8 = 0
        func newline() {
            output.append(UInt8(ascii: "\n"))
            output.append(contentsOf: repeatElement(UInt8(ascii: " "), count: depth * 2))
        }
        for (index, byte) in bytes.enumerated() {
            defer { previous = byte }
            if strings.holds(byte) {
                output.append(byte)
                continue
            }
            switch byte {
            case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\t"), UInt8(ascii: "\r"):
                throw NotCompact()
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                output.append(byte)
                let next = index + 1 < bytes.count ? bytes[index + 1] : 0
                if next != UInt8(ascii: "}"), next != UInt8(ascii: "]") {
                    depth += 1
                    newline()
                }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                if previous != UInt8(ascii: "{"), previous != UInt8(ascii: "[") {
                    guard depth > 0 else { throw NotCompact() }
                    depth -= 1
                    newline()
                }
                output.append(byte)
            case UInt8(ascii: ","):
                output.append(byte)
                newline()
            case UInt8(ascii: ":"):
                output.append(byte)
                output.append(UInt8(ascii: " "))
            default:
                output.append(byte)
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// The bytes a text of member lines stands for.
    ///
    /// - Parameter text: A body's text from ``text(of:)``.
    /// - Returns: The text without the whitespace outside its strings.
    static func bytes(of text: String) -> Data {
        var output = Data()
        var strings = StringTracker()
        for byte in text.utf8 {
            if strings.holds(byte) || (byte != UInt8(ascii: " ") && byte != UInt8(ascii: "\n")) {
                output.append(byte)
            }
        }
        return output
    }

    /// A body's text for a snapshot. A body whose text can't stand for its bytes fails the test, so it can't be
    /// recorded as if it were right.
    static func snapshotText(of body: Data) -> String {
        guard let text = try? text(of: body), bytes(of: text) == body else {
            let message = "The body isn't compact JSON, so its bytes can't be shown one member per line."
            Issue.record(Comment(rawValue: message))
            return message
        }
        return text
    }

    /// Follows JSON text byte by byte, to tell what's inside a string.
    private struct StringTracker {
        private var inString = false
        private var escaped = false

        /// Takes the next byte and says whether it belongs to a string, its quotes included.
        mutating func holds(_ byte: UInt8) -> Bool {
            guard inString else {
                inString = byte == UInt8(ascii: "\"")
                return inString
            }
            if escaped {
                escaped = false
            } else if byte == UInt8(ascii: "\\") {
                escaped = true
            } else if byte == UInt8(ascii: "\"") {
                inString = false
            }
            return true
        }
    }
}

extension Snapshotting where Value == Data, Format == String {
    /// A request body as its own bytes, one member per line.
    package static var memberLines: Snapshotting<Data, String> {
        Snapshotting<String, String>.lines.pullback(BodySnapshot.snapshotText(of:))
    }
}
