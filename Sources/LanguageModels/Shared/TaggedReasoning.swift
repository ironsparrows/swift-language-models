package import FoundationModels
import LanguageModelsCore

/// Reasoning that a model writes at the start of its answer's text, between `<think>` and `</think>` or `<thinking>`
/// and `</thinking>`, instead of sending it as reasoning.
///
/// The answer's text goes through ``split(_:)`` delta by delta, and comes out as the block's reasoning and the answer
/// after it. Only a block that opens the text counts, after any whitespace, so a tag later in the answer stays text.
/// The tags and the whitespace before and after the block leave the answer, and the whole block stays in ``block`` as
/// the model wrote it. A tag may be split across deltas anywhere, so text that may still be one is held back until
/// it's clear: the start of the text until it does or doesn't open a block, and the end of the reasoning while it may
/// begin the closing tag. Text that turns out not to open a block comes out unchanged.
///
/// A block that the answer never closes, such as one cut off at the token limit, is reasoning to the end, as it was
/// shown while it streamed.
package struct TaggedReasoning {
    /// The metadata key under which a reasoning entry keeps the block as the model wrote it, so it goes back where the
    /// model put it.
    package static let metadataKey = "taggedReasoning"

    /// The block to send back at the start of an answer's text, as its reasoning entry keeps it, or `nil` when the
    /// entry keeps none.
    package static func block(of reasoning: Transcript.Reasoning) -> String? {
        if case .string(let block)? = reasoning.metadata[metadataKey]?.kind { block } else { nil }
    }

    /// The block that opened the text, as the model wrote it: the whitespace before it, its tags and reasoning, and
    /// the whitespace after it. It's set once ``finish()`` ends the text, and `nil` when the text didn't open with a
    /// block.
    package private(set) var block: String?

    private var state = State.opening(held: "")

    /// The block's text so far, as the model wrote it.
    private var written = ""

    /// Starts reading an answer's text.
    package init() {}

    /// Splits the next delta of the answer's text.
    ///
    /// - Returns: The reasoning and the answer text the delta completes; either may be empty while text is held back.
    package mutating func split(_ delta: String) -> Split {
        var split = Split()
        var rest = Substring(delta)
        while !rest.isEmpty {
            switch state {
            case .opening(let held):
                let text = held + rest
                rest = ""
                let start = text.drop { $0.isWhitespace }
                if let tag = Tag.all.first(where: { start.hasPrefix($0.opening) }) {
                    rest = start.dropFirst(tag.opening.count)
                    written = String(text[..<rest.startIndex])
                    state = .inside(closing: tag.closing, held: "")
                } else if start.isEmpty || Tag.all.contains(where: { $0.opening.hasPrefix(start) }) {
                    state = .opening(held: text)
                } else {
                    split.text += text
                    state = .answer
                }
            case .inside(let closing, let held):
                let text = held + rest
                rest = ""
                if let range = text.firstRange(of: closing) {
                    split.reasoning += text[..<range.lowerBound]
                    written += text[..<range.upperBound]
                    rest = text[range.upperBound...]
                    state = .closed
                } else {
                    let end = text.index(text.endIndex, offsetBy: -Self.partialLength(of: text, toward: closing))
                    split.reasoning += text[..<end]
                    written += text[..<end]
                    state = .inside(closing: closing, held: String(text[end...]))
                }
            case .closed:
                let answer = rest.drop { $0.isWhitespace }
                written += rest[..<answer.startIndex]
                rest = answer
                if !answer.isEmpty { state = .answer }
            case .answer:
                split.text += rest
                rest = ""
            }
        }
        return split
    }

    /// Ends the text, giving back what was held: the start of the text as answer text, or the end of a block that
    /// never closed as reasoning.
    package mutating func finish() -> Split {
        defer { state = .answer }
        switch state {
        case .opening(let held):
            return Split(text: held)
        case .inside(_, let held):
            written += held
            block = written
            return Split(reasoning: held)
        case .closed, .answer:
            block = written.isEmpty ? nil : written
            return Split()
        }
    }

    /// How many characters at the end of the text begin the tag, and may be the first part of a tag split across
    /// deltas.
    private static func partialLength(of text: String, toward tag: String) -> Int {
        (1..<tag.count).reversed().first { text.hasSuffix(tag.prefix($0)) } ?? 0
    }
}

extension TaggedReasoning {
    /// What a delta of the answer's text holds: the reasoning, which comes first, and the answer text after it.
    package struct Split: Equatable {
        package var reasoning = ""
        package var text = ""

        package init(reasoning: String = "", text: String = "") {
            self.reasoning = reasoning
            self.text = text
        }
    }

    private enum State {
        /// Before the text shows whether it opens a block, holding the text so far.
        case opening(held: String)

        /// Inside a block, holding the end of its text while it may begin the closing tag.
        case inside(closing: String, held: String)

        /// After the closing tag, dropping whitespace.
        case closed

        /// In the answer, where text passes through.
        case answer
    }

    /// A pair of tags that encloses a block.
    private struct Tag {
        static let all = [Tag(name: "think"), Tag(name: "thinking")]

        let opening: String
        let closing: String

        init(name: String) {
            opening = "<\(name)>"
            closing = "</\(name)>"
        }
    }
}
