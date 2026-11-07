package import FoundationModels
import LanguageModelsCore

/// One turn of a conversation, as provider APIs take them: instructions, a prompt, everything one answer wrote, or a
/// tool's output.
package enum TranscriptTurn {
    case instructions(Transcript.Instructions, entry: Transcript.Entry)
    case prompt(Transcript.Prompt, entry: Transcript.Entry)
    /// An answer's reasoning, response and tool calls, in their order, which APIs take as one assistant message.
    case answer([Transcript.Entry])
    case toolOutput(Transcript.ToolOutput, entry: Transcript.Entry)

    /// The turns of a transcript.
    ///
    /// Generated data, such as an image, stays in the transcript but isn't a turn, so it isn't billed again as input on
    /// every later request.
    ///
    /// - Parameters:
    ///   - transcript: The entries to send.
    ///   - provider: The provider's name, for the error.
    /// - Returns: The turns, in the transcript's order.
    /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for a kind of entry no turn holds.
    package static func turns(of transcript: some Sequence<Transcript.Entry>, provider: String) throws -> [TranscriptTurn] {
        var turns: [TranscriptTurn] = []
        var answer: [Transcript.Entry] = []
        func endAnswer() {
            if !answer.isEmpty { turns.append(.answer(answer)) }
            answer = []
        }
        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                endAnswer()
                turns.append(.instructions(instructions, entry: entry))
            case .prompt(let prompt):
                endAnswer()
                turns.append(.prompt(prompt, entry: entry))
            case .reasoning, .response, .toolCalls:
                answer.append(entry)
            case .toolOutput(let output):
                endAnswer()
                turns.append(.toolOutput(output, entry: entry))
            default:
                #if canImport(FoundationModels, _version: 2.1.14)
                if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *), case .data = entry { continue }
                #endif
                throw LanguageModelError.unsupported(entry, "\(provider) can't take this kind of transcript entry yet.")
            }
        }
        endAnswer()
        return turns
    }
}

extension Transcript.Segment {
    /// The segment's text: a text segment's own, a structure as JSON, and `nil` for an attachment.
    package var text: String? {
        switch self {
        case .text(let text): text.content
        case .structure(let structure): JSONValue(structure.content).text
        default: nil
        }
    }
}
