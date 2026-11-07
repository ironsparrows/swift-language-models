package import FoundationModels
import LanguageModelsCore

// MARK: - Turns

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

extension Transcript {
    /// The id of the transcript's first prompt, which stays the same for the whole session, so a provider that keeps a
    /// session's requests on one host can send it as the session's id; `nil` before the first prompt.
    package var firstPromptID: String? {
        for case .prompt(let prompt) in self {
            return prompt.id
        }
        return nil
    }
}

// MARK: - Reasoning entries

/// The provider and API format that wrote a reasoning entry, as the entry's metadata names it.
///
/// Each provider tags the reasoning entries it writes, and sends back only reasoning with its own tag: a session can
/// switch models, and reasoning that another provider wrote, in its own format, means nothing to this one. A provider
/// that answers through more than one API format, such as Chat Completions and Responses, gives each format its own
/// value, since each sends reasoning back in another shape. Saved transcripts keep the tag, so its key and each
/// value never change.
package struct ReasoningOrigin: RawRepresentable, Hashable, Sendable {
    /// The metadata key under which a reasoning entry names the provider that wrote it.
    package static let metadataKey = "reasoningOrigin"

    /// The provider's name, as the metadata spells it.
    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The provider that wrote a reasoning entry, or `nil` when the entry names none, such as one from a model outside
    /// this package.
    ///
    /// - Parameter reasoning: The entry whose metadata is read.
    package init?(of reasoning: Transcript.Reasoning) {
        guard case .string(let name)? = reasoning.metadata[Self.metadataKey]?.kind else { return nil }
        self.init(rawValue: name)
    }
}

extension Transcript.Reasoning {
    /// The provider and API format that wrote the entry, as its metadata names them, or `nil` when the entry names none,
    /// such as one from a model outside this package.
    package var origin: String? {
        ReasoningOrigin(of: self)?.rawValue
    }

    /// The model that wrote the entry, as its answer named it, or `nil` when the entry doesn't say.
    package var writer: String? {
        MetadataValues(metadata).string(LanguageModelMetadataKey.model)
    }
}

extension ReasoningOrigin {
    /// The metadata of a reasoning entry this provider writes: its origin, the model that wrote it once known, and
    /// the block that opened the answer's text once the answer ended.
    ///
    /// - Parameters:
    ///   - model: The model that wrote the reasoning, as its answer named it, which `Transcript.Reasoning.writer`
    ///     reads back.
    ///   - taggedBlock: The block that opened the answer's text, such as `<think>…</think>`, which goes back there.
    /// - Returns: The metadata.
    package func metadata(model: String?, taggedBlock: String?) -> [String: any ConvertibleToGeneratedContent] {
        var metadata: [String: any ConvertibleToGeneratedContent] = [Self.metadataKey: rawValue]
        metadata[LanguageModelMetadataKey.model] = model
        metadata[TaggedReasoning.metadataKey] = taggedBlock
        return metadata
    }
}

extension TaggedReasoning {
    /// The metadata key under which a reasoning entry keeps the block as the model wrote it, so it goes back where the
    /// model put it.
    package static let metadataKey = "taggedReasoning"

    /// The block to send back at the start of an answer's text, as its reasoning entry keeps it, or `nil` when the
    /// entry keeps none.
    package static func block(of reasoning: Transcript.Reasoning) -> String? {
        if case .string(let block)? = reasoning.metadata[metadataKey]?.kind { block } else { nil }
    }
}
