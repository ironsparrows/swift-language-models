package import FoundationModels
import LanguageModelsCore

// MARK: - Turns

/// One turn of a conversation, as provider APIs take them: instructions, a prompt, everything one answer wrote, or a
/// tool's output.
enum TranscriptTurn {
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
    static func turns(of transcript: some Sequence<Transcript.Entry>, provider: String) throws -> [TranscriptTurn] {
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
    var text: String? {
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
    var firstPromptID: String? {
        for case .prompt(let prompt) in self {
            return prompt.id
        }
        return nil
    }
}

// MARK: - Segments

/// A transcript's segments as a format's content parts, which the format makes from each piece of content.
///
/// Text goes as text. An attachment's label goes first, as a text part of its own, so the model can name the attachment,
/// as an `ImageReference` does. The exchange first checks that its models take the attachment.
struct SegmentReader<Part> {
    /// The transcript entries whose parts carry an image, which a host's rejection of an image names.
    private(set) var imageEntries: [Transcript.Entry] = []

    /// Whether a part carries a PDF.
    private(set) var carriesPDF = false

    /// The provider's name, for the errors.
    private let provider: String

    /// What the format calls where instructions go, for the errors.
    private let instructions: String

    private let reader: AttachmentReader

    /// Checks that every model takes an attachment.
    private let check: (AttachmentKind, Transcript.Entry) throws(LanguageModelError) -> Void

    /// Makes the format's part for a piece of content of an entry.
    private let makePart: (AttachmentReader.Content, Transcript.Entry) throws -> Part

    /// - Parameters:
    ///   - provider: The provider's name, as the errors name it.
    ///   - encoding: How images sent as data are encoded.
    ///   - instructions: What the format calls where instructions go, as the errors name it.
    ///   - check: Checks that every model takes an attachment.
    ///   - makePart: Makes the format's part for a piece of content of an entry.
    init(
        provider: String,
        encoding: ImageEncoding,
        instructions: String,
        check: @escaping (AttachmentKind, Transcript.Entry) throws(LanguageModelError) -> Void,
        makePart: @escaping (AttachmentReader.Content, Transcript.Entry) throws -> Part
    ) {
        self.provider = provider
        self.instructions = instructions
        reader = AttachmentReader(provider: provider, encoding: encoding)
        self.check = check
        self.makePart = makePart
    }

    /// A prompt's parts: its segments, then, as text, the response schema it recorded, which Foundation Models does when
    /// the schema belongs in the prompt, so every request writes it the same way.
    ///
    /// - Throws: What ``parts(_:of:)`` throws, and `LanguageModelError` for a schema that can't be written.
    mutating func parts(of prompt: Transcript.Prompt, in entry: Transcript.Entry) throws -> [Part] {
        var parts = try parts(prompt.segments, of: entry)
        if case .schema(let schema)? = prompt.responseFormat?.kind {
            parts.append(try makePart(.text(try schema.promptInstructions()), entry))
        }
        return parts
    }

    /// Text, structure and attachment segments as parts, in their order.
    ///
    /// - Throws: The exchange's errors for an attachment a model doesn't take, what the format throws for content it has
    ///   no part for, and `LanguageModelError.unsupportedTranscriptContent` for an attachment that can't be read or a kind
    ///   of segment the format can't take.
    mutating func parts(_ segments: [Transcript.Segment], of entry: Transcript.Entry) throws -> [Part] {
        var parts: [Part] = []
        for segment in segments {
            guard case .attachment(let attachment) = segment else {
                parts += try textParts([segment], of: entry)
                continue
            }
            let content = try reader.content(of: attachment, in: entry) { (kind) throws(LanguageModelError) in try check(kind, entry) }
            if let label = attachment.givenLabel { parts.append(try makePart(.text(label), entry)) }
            parts.append(try makePart(content, entry))
            record(content, of: entry)
        }
        return parts
    }

    /// Text and structure segments as text parts.
    ///
    /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for attachments, which instructions don't take, and for
    ///   a kind of segment the format can't take.
    func textParts(_ segments: [Transcript.Segment], of entry: Transcript.Entry) throws -> [Part] {
        try segments.map { segment in
            if let text = segment.text { return try makePart(.text(text), entry) }
            if case .attachment = segment {
                throw LanguageModelError.unsupported(entry, "\(provider)'s \(instructions) take only text, not attachments.")
            }
            throw LanguageModelError.unsupported(entry, "\(provider) can't take this kind of segment yet.")
        }
    }

    /// Notes which entries carry an image, and whether any part carries a PDF.
    private mutating func record(_ content: AttachmentReader.Content, of entry: Transcript.Entry) {
        switch content {
        case .jpeg, .imageURL:
            if !imageEntries.contains(where: { $0.id == entry.id }) { imageEntries.append(entry) }
        case .pdf:
            carriesPDF = true
        case .text, .data:
            break
        }
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
struct ReasoningOrigin: RawRepresentable, Hashable, Sendable {
    /// The provider's name, as the metadata spells it.
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The provider that wrote a reasoning entry, or `nil` when the entry names none, such as one from a model outside
    /// this package.
    ///
    /// - Parameter reasoning: The entry whose metadata is read.
    init?(of reasoning: Transcript.Reasoning) {
        guard case .string(let name)? = reasoning.metadata[ReasoningKey.origin]?.kind else { return nil }
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
        MetadataValues(metadata).string(ReasoningKey.model)
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
    func metadata(model: String?, taggedBlock: String?) -> [String: any ConvertibleToGeneratedContent] {
        var metadata: [String: any ConvertibleToGeneratedContent] = [ReasoningKey.origin: rawValue]
        metadata[ReasoningKey.model] = model
        metadata[ReasoningKey.taggedBlock] = taggedBlock
        return metadata
    }
}

extension TaggedReasoning {
    /// The block to send back at the start of an answer's text, as its reasoning entry keeps it, or `nil` when the
    /// entry keeps none.
    static func block(of reasoning: Transcript.Reasoning) -> String? {
        if case .string(let block)? = reasoning.metadata[ReasoningKey.taggedBlock]?.kind { block } else { nil }
    }
}

/// The keys of a reasoning entry's metadata. Saved transcripts keep them, so they never change.
private enum ReasoningKey {
    /// Names the provider that wrote the entry.
    static let origin = "reasoningOrigin"

    /// Names the model that wrote the entry.
    static let model = "model"

    /// Keeps the block as the model wrote it, so it goes back where the model put it.
    static let taggedBlock = "taggedReasoning"
}
