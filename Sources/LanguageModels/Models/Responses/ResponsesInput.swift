import Foundation
import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

// MARK: - Turns

extension Responses {
    /// A transcript as the format's `input` items.
    ///
    /// Instructions become a message in the model's instructions role, and prompts `user` messages. One answer
    /// becomes its `reasoning` items, an `assistant` message for each of its messages, with its text and `phase`, and a
    /// reasoning block that the model wrote in its answer's text back at the start of the first, and a `function_call`
    /// item for each of its tool calls, in the order they came, or with the `reasoning` items first when the order
    /// isn't known. An answer with neither text nor tool calls, as one cut off while it reasoned, sends no reasoning
    /// back, since a reasoning item needs an item after it. Each tool output becomes a `function_call_output` item,
    /// matched to its call by `call_id`. Prompts and tool outputs carry their attachments as input parts;
    /// generated data and an answer's attachments aren't sent back. Every entry turns into the same JSON each time, so
    /// a provider's prompt cache stays valid from one request to the next.
    struct Input {
        private var items: [Item] = []

        /// The transcript entries whose items carry an image, which a host's rejection of an image names.
        private(set) var imageEntries: [Transcript.Entry] = []

        private let attachments: AttachmentParts

        /// The provider's name, for the errors.
        private let provider: String

        /// The role of the instructions' messages.
        private let instructionsRole: MessageRole

        /// The metadata key under which an answer's response entry keeps the phases of its messages.
        private let phasesKey: String

        /// Whether a reasoning entry goes back: one of the provider's own that its exchange sends back.
        private let replays: (Transcript.Reasoning) -> Bool

        /// The items for a transcript.
        ///
        /// A prompt that recorded a response schema, which Foundation Models does when the schema belongs in the
        /// prompt, carries the schema as text after its own, so every request writes it the same way.
        ///
        /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for content the format or a model can't take,
        ///   and the exchange's errors for an attachment a model doesn't take.
        init<Exchange: Responses.Exchange>(
            _ transcript: some Sequence<Transcript.Entry>,
            model: Responses.Model<Exchange>,
            exchange: Exchange
        ) throws {
            attachments = AttachmentParts(model: model, exchange: exchange)
            provider = model.providerName
            instructionsRole = MessageRole(rawValue: model.instructionsRole.rawValue)
            phasesKey = model.phasesKey
            let origin = model.reasoningOrigin
            replays = { $0.origin == origin && exchange.replays($0) }
            for turn in try TranscriptTurn.turns(of: transcript, provider: provider) { try append(turn) }
        }

        /// The `input` member: the items a request with this storage sends.
        ///
        /// - Parameter storage: Whether the provider keeps the response.
        /// - Returns: The items, as JSON.
        /// - Throws: An error when an item can't be encoded.
        func json(for storage: Request.Storage) throws -> JSONValue {
            try JSONValueEncoder.encode(storage == .notStored ? withEncryptedReasoningOnly : items)
        }

        /// The items without the `reasoning` items that carry no encrypted reasoning, which a request the provider
        /// doesn't store can't send back, since the provider can't look them up by their ids.
        private var withEncryptedReasoningOnly: [Item] {
            items.filter { item in
                if case .reasoning(let reasoning) = item { reasoning.hasEncryptedContent } else { true }
            }
        }

        private mutating func append(_ turn: TranscriptTurn) throws {
            switch turn {
            case .instructions(let instructions, let entry):
                // A session without instructions still has an empty instructions entry, which hosts reject.
                let parts = try textParts(instructions.segments, of: entry)
                guard !parts.isEmpty else { return }
                items.append(.message(role: instructionsRole, content: Content(parts), phase: nil))
            case .prompt(let prompt, let entry):
                var parts = try parts(prompt.segments, of: entry)
                if case .schema(let schema)? = prompt.responseFormat?.kind {
                    parts.append(.text(try schema.promptInstructions()))
                }
                guard !parts.isEmpty else { return }
                items.append(.message(role: .user, content: Content(parts), phase: nil))
            case .answer(let entries):
                try appendAnswer(entries)
            case .toolOutput(let output, let entry):
                let parts = try parts(output.segments, of: entry)
                let texts = parts.compactMap { part -> String? in
                    if case .text(let text) = part { text } else { nil }
                }
                // Text alone goes as one string, a line per part, so a label doesn't run into its text; attachments need
                // the parts.
                let content: Content = texts.count == parts.count ? .text(texts.joined(separator: "\n")) : .parts(parts)
                items.append(.functionCallOutput(callID: output.id, output: content))
            }
        }

        /// Adds one answer's items: its `reasoning` items, messages and function calls, in the order its signatures
        /// keep, with any message or call they don't place after them.
        private mutating func appendAnswer(_ entries: [Transcript.Entry]) throws {
            var order: [OutputItem] = []
            var block = ""
            var text = ""
            var phases: [MessagePhase] = []
            var calls: [Item] = []
            for entry in entries {
                switch entry {
                case .reasoning(let entry):
                    // Reasoning that another provider wrote is in its own format, so only the provider's own goes back.
                    guard replays(entry) else { continue }
                    // A block the model wrote in its answer's text goes back there, as it was written.
                    block = (TaggedReasoning.block(of: entry) ?? "") + block
                    order += OutputItem.items(inSignatureOf: entry)
                case .response(let response):
                    // An answer's attachments aren't sent back, since the format's assistant messages here take only text.
                    text += response.segments.compactMap(\.text).joined()
                    phases += MetadataValues(response.metadata).structures(phasesKey).compactMap(MessagePhase.init)
                case .toolCalls(let toolCalls):
                    // An answer that ends in tool calls keeps its facts, its messages' phases among them, on its first call.
                    if phases.isEmpty, let first = toolCalls.first {
                        phases = MetadataValues(first.metadata).structures(phasesKey).compactMap(MessagePhase.init)
                    }
                    calls += toolCalls.map { call in
                        .functionCall(callID: call.id, name: call.toolName, arguments: JSONValue(call.arguments).text)
                    }
                default:
                    continue
                }
            }
            var messages = MessagePhase.split(text, into: phases).enumerated().map { index, message in
                Item.message(role: .assistant, content: .text(index == 0 ? block + message.text : message.text), phase: message.phase)
            }[...]
            // A reasoning item needs an item after it, which a block alone isn't.
            if messages.isEmpty, calls.isEmpty { order = [] }
            if messages.isEmpty, !block.isEmpty {
                messages = [.message(role: .assistant, content: .text(block), phase: nil)]
            }
            var rest = calls[...]
            for item in order {
                switch item {
                case .reasoning(let reasoning): items.append(.reasoning(reasoning))
                case .message: if let message = messages.popFirst() { items.append(message) }
                case .functionCall: if let call = rest.popFirst() { items.append(call) }
                }
            }
            items += messages
            items += rest
        }

        /// Text, structure and attachment segments as input parts, in their order.
        ///
        /// - Throws: The attachments' errors, and `LanguageModelError.unsupportedTranscriptContent` for a kind of
        ///   segment the format can't take.
        private mutating func parts(_ segments: [Transcript.Segment], of entry: Transcript.Entry) throws -> [Part] {
            var parts: [Part] = []
            for segment in segments {
                guard case .attachment(let attachment) = segment else {
                    parts += try textParts([segment], of: entry)
                    continue
                }
                let attachmentParts = try attachments.parts(for: attachment, in: entry)
                if attachmentParts.contains(where: { $0.type == .image }), !imageEntries.contains(where: { $0.id == entry.id }) {
                    imageEntries.append(entry)
                }
                parts += attachmentParts
            }
            return parts
        }

        /// Text and structure segments as text parts.
        ///
        /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for attachments, which instructions don't take,
        ///   and for a kind of segment the format can't take.
        private func textParts(_ segments: [Transcript.Segment], of entry: Transcript.Entry) throws -> [Part] {
            try segments.map { segment in
                if let text = segment.text { return .text(text) }
                if case .attachment = segment {
                    throw LanguageModelError.unsupported(entry, "\(provider)'s instructions take only text, not attachments.")
                }
                throw LanguageModelError.unsupported(entry, "\(provider) can't take this kind of segment yet.")
            }
        }
    }
}

// MARK: - Attachments

extension Responses.Input {
    /// Prompt and tool-output attachments as the format's input parts.
    ///
    /// A label goes first, as a text part of its own, so the model can name the attachment, as an `ImageReference`
    /// does. Images go as JPEG data URLs in `input_image` parts, or as their web address when they have one. Data
    /// attachments go by kind: text as text, images as images, and PDFs as `input_file` parts. The format has no part
    /// for other kinds, such as audio or video. The exchange first checks that its models take the attachment. The same
    /// attachment gives the same bytes every time.
    private struct AttachmentParts {
        /// The provider's name, for the errors.
        private let provider: String

        private let reader: AttachmentReader

        /// Checks that every model takes an attachment.
        private let check: (AttachmentKind, Transcript.Entry) throws(LanguageModelError) -> Void

        init<Exchange: Responses.Exchange>(model: Responses.Model<Exchange>, exchange: Exchange) {
            provider = model.providerName
            reader = AttachmentReader(provider: provider, encoding: model.images)
            check = { (attachment, entry) throws(LanguageModelError) in try exchange.checkAttachment(attachment, in: entry) }
        }

        /// The parts for one attachment: its label, when it has one, then the attachment.
        ///
        /// - Throws: The exchange's errors for an attachment a model doesn't take, and
        ///   `LanguageModelError.unsupportedTranscriptContent` for one that can't be read or that the format has no
        ///   part for.
        func parts(for segment: Transcript.AttachmentSegment, in entry: Transcript.Entry) throws -> [Part] {
            let content = try reader.content(of: segment, in: entry) { (kind) throws(LanguageModelError) in try check(kind, entry) }
            return (segment.givenLabel.map { [.text($0)] } ?? []) + [try part(for: content, in: entry)]
        }

        /// The input part for an attachment's content: text, an `input_image` or a PDF `input_file`.
        private func part(for content: AttachmentReader.Content, in entry: Transcript.Entry) throws -> Part {
            switch content {
            case .text(let text):
                return .text(text)
            case .jpeg(let data):
                return .image(url: DataURL(mediaType: MediaType.jpeg, data: data).text)
            case .imageURL(let url):
                return .image(url: url.absoluteString)
            case .pdf(let data, let fileName):
                return .file(name: fileName, data: DataURL(mediaType: MediaType.pdf, data: data).text)
            case .data(_, let type):
                throw LanguageModelError.unsupported(entry, "\(provider) takes no attachments of type \(type.identifier).")
            }
        }
    }
}

// MARK: - Wire

/// One item of a request's `input`.
private enum Item: Encodable {
    /// A message: the instructions, a prompt, or an answer's text, with the `phase` the answer's message had.
    case message(role: MessageRole, content: Content, phase: String?)

    /// One of an answer's function calls, matched to its output by `call_id`.
    case functionCall(callID: String, name: String, arguments: String)

    /// A tool's output for a function call.
    case functionCallOutput(callID: String, output: Content)

    /// One of an answer's `reasoning` items, as the provider sent it.
    case reasoning(ReasoningItem)

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .message(let role, let content, let phase):
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode(role, forKey: "role")
            try container.encode(content, forKey: "content")
            try container.encodeIfPresent(phase, forKey: "phase")
        case .functionCall(let callID, let name, let arguments):
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode(Responses.ItemType.functionCall, forKey: "type")
            try container.encode(callID, forKey: "call_id")
            try container.encode(name, forKey: "name")
            try container.encode(arguments, forKey: "arguments")
        case .functionCallOutput(let callID, let output):
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode(Responses.ItemType.functionCallOutput, forKey: "type")
            try container.encode(callID, forKey: "call_id")
            try container.encode(output, forKey: "output")
        case .reasoning(let item):
            try item.encode(to: encoder)
        }
    }
}

/// A message's content or a tool's output: text alone, or a list of input parts.
private enum Content: Encodable {
    case text(String)
    case parts([Part])

    /// One text part as its text, and anything else as parts.
    init(_ parts: [Part]) {
        if parts.count == 1, case .text(let text) = parts[0] {
            self = .text(text)
        } else {
            self = .parts(parts)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

/// One part of a message's content.
private enum Part: Encodable {
    /// An `input_text` part.
    case text(String)

    /// An `input_image` part, at a web address or as a data URL, which the model sees at the detail it picks.
    case image(url: String)

    /// An `input_file` part, holding the file as a data URL.
    case file(name: String, data: String)

    var type: PartType {
        switch self {
        case .text: .text
        case .image: .image
        case .file: .file
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        try container.encode(type, forKey: "type")
        switch self {
        case .text(let text):
            try container.encode(text, forKey: "text")
        case .image(let url):
            try container.encode(url, forKey: "image_url")
            try container.encode("auto", forKey: "detail")
        case .file(let name, let data):
            try container.encode(name, forKey: "filename")
            try container.encode(data, forKey: "file_data")
        }
    }
}

/// The role of a message: the person's, the model's, or the instructions' role that the model picks.
private struct MessageRole: ProviderVocabulary {
    static let user: Self = "user"
    static let assistant: Self = "assistant"

    let rawValue: String
}

/// The `type` of a content part.
private struct PartType: ProviderVocabulary {
    static let text: Self = "input_text"
    static let image: Self = "input_image"
    static let file: Self = "input_file"

    let rawValue: String
}
