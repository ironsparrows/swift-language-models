import Foundation
import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

// MARK: - Turns

extension Responses {
    /// A transcript as the format's `input` items.
    ///
    /// Instructions become a message in the model's instructions role, and prompts `user` messages. One answer
    /// becomes its `reasoning` items, an `assistant` message for each of its messages, with its text and `phase`, a
    /// `function_call` item for each of its tool calls, and its server tools' calls as the answer kept them. A reasoning
    /// block that the model wrote in its answer's text goes back at the start of the first message. The items go in the
    /// order they came, as the reasoning's signature records it; the items it doesn't place follow, the server tools'
    /// calls first, then the messages, then the function calls. An answer with nothing after its reasoning, as one cut
    /// off while it reasoned, sends no reasoning back, since a reasoning item needs an item after it. Each tool output
    /// becomes a `function_call_output` item, matched to its call by `call_id`. Prompts and tool outputs carry their
    /// attachments as input parts; generated data and an answer's attachments aren't sent back. Every entry turns into
    /// the same JSON each time, so a host's prompt cache stays valid from one request to the next.
    struct Input {
        private var items: [Item] = []

        private var reader: SegmentReader<Part>

        /// The role of the instructions' messages.
        private let instructionsRole: MessageRole

        /// The metadata key under which an answer's response entry keeps the phases of its messages.
        private let phasesKey: String

        /// The metadata key under which an answer's response entry keeps its server tools' calls.
        private let serverToolsKey: String

        /// Whether a reasoning entry goes back: one of the provider's own that its exchange sends back.
        private let replays: (Transcript.Reasoning) -> Bool

        /// The items for a transcript.
        ///
        /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for content the format or a model can't take,
        ///   and the exchange's errors for an attachment a model doesn't take.
        init<Exchange: Responses.Exchange>(
            _ transcript: some Sequence<Transcript.Entry>,
            model: Responses.Model<Exchange>,
            exchange: Exchange
        ) throws {
            let provider = model.providerName
            reader = SegmentReader(
                provider: provider, encoding: model.images, instructions: "instructions",
                check: { (attachment, entry) throws(LanguageModelError) in try exchange.checkAttachment(attachment, in: entry) },
                makePart: { content, entry in try Self.part(for: content, in: entry, provider: provider) })
            instructionsRole = MessageRole(rawValue: model.instructionsRole.rawValue)
            phasesKey = model.phasesKey
            serverToolsKey = model.serverToolsKey
            let origin = model.reasoningOrigin
            replays = { $0.origin == origin && exchange.replays($0) }
            for turn in try TranscriptTurn.turns(of: transcript, provider: provider) { try append(turn) }
        }

        /// The transcript entries whose items carry an image, which a host's rejection of an image names.
        var imageEntries: [Transcript.Entry] {
            reader.imageEntries
        }

        /// The `input` member: the items a request with this storage sends, with the server tools' calls it keeps.
        ///
        /// A server tool's call goes back with the `reasoning` items right before it, or neither goes back. It goes back
        /// only when it completed, or has no status, the request keeps its kind, and the provider keeps this request's
        /// response or, for a kind that goes back unstored, such as a web search, each of the `reasoning` items before it
        /// carries encrypted reasoning. A call of another kind, such as an image's, also needs the provider to have kept
        /// the response that made it. A request the provider doesn't store also leaves out every other `reasoning` item
        /// that carries no encrypted reasoning, since the provider can't look it up by its id.
        ///
        /// - Parameters:
        ///   - storage: Whether the provider keeps the response.
        ///   - calls: The kinds of server tool call the request keeps.
        /// - Returns: The items, as JSON.
        /// - Throws: An error when an item can't be encoded.
        func json(for storage: Request.Storage, keeping calls: Set<ServerToolCall>) throws -> JSONValue {
            let isStored = storage != .notStored
            var sent: [Item] = []
            // The `reasoning` items since the last item of another kind, which go back with the item after them.
            var reasoning: [ReasoningItem] = []
            for item in items {
                switch item {
                case .reasoning(let reasoningItem):
                    reasoning.append(reasoningItem)
                case .serverToolCall(let call, let json, let fromStoredResponse):
                    let completed = json["status"].map { $0 == "completed" } ?? true
                    let lookedUp =
                        call.goesBackUnstored ? isStored || reasoning.allSatisfy(\.hasEncryptedContent) : isStored && fromStoredResponse
                    if completed, calls.contains(call), lookedUp { sent += reasoning.map(Item.reasoning) + [item] }
                    reasoning = []
                case .message, .functionCall, .functionCallOutput:
                    sent += reasoning.filter { isStored || $0.hasEncryptedContent }.map(Item.reasoning) + [item]
                    reasoning = []
                }
            }
            sent += reasoning.filter { isStored || $0.hasEncryptedContent }.map(Item.reasoning)
            return try JSONValueEncoder.encode(sent)
        }

        private mutating func append(_ turn: TranscriptTurn) throws {
            switch turn {
            case .instructions(let instructions, let entry):
                // A session without instructions still has an empty instructions entry, which hosts reject.
                let parts = try reader.textParts(instructions.segments, of: entry)
                guard !parts.isEmpty else { return }
                items.append(.message(role: instructionsRole, content: Content(parts), phase: nil))
            case .prompt(let prompt, let entry):
                let parts = try reader.parts(of: prompt, in: entry)
                guard !parts.isEmpty else { return }
                items.append(.message(role: .user, content: Content(parts), phase: nil))
            case .answer(let entries):
                try appendAnswer(entries)
            case .toolOutput(let output, let entry):
                let parts = try reader.parts(output.segments, of: entry)
                let texts = parts.compactMap { part -> String? in
                    if case .text(let text) = part { text } else { nil }
                }
                // Text alone goes as one string, a line per part, so a label doesn't run into its text; attachments need
                // the parts.
                let content: Content = texts.count == parts.count ? .text(texts.joined(separator: "\n")) : .parts(parts)
                items.append(.functionCallOutput(callID: output.id, output: content))
            }
        }

        /// Adds one answer's items: its `reasoning` items, messages, function calls and server tools' calls, in the
        /// order its signatures keep, with any message or function call they don't place after them, and any server
        /// tool's call they don't place before the messages.
        private mutating func appendAnswer(_ entries: [Transcript.Entry]) throws {
            let start = items.count
            var order: [OutputItem] = []
            var block = ""
            var text = ""
            var phases: [MessagePhase] = []
            var calls: [Item] = []
            var serverToolCalls: [(call: ServerToolCall, item: JSONValue, fromStoredResponse: Bool)] = []
            // The server tools' calls that reasoning which doesn't go back placed, which don't go back either.
            var skippedCalls: [ServerToolCall] = []
            for entry in entries {
                switch entry {
                case .reasoning(let entry):
                    // Reasoning that another provider wrote is in its own format, so only the provider's own goes back.
                    guard replays(entry) else {
                        skippedCalls += OutputItem.items(inSignatureOf: entry).compactMap { item in
                            if case .serverToolCall(let call) = item { call } else { nil }
                        }
                        continue
                    }
                    // A block the model wrote in its answer's text goes back there, as it was written.
                    block = (TaggedReasoning.block(of: entry) ?? "") + block
                    order += OutputItem.items(inSignatureOf: entry)
                case .response(let response):
                    // An answer's attachments aren't sent back, since the format's assistant messages here take only text.
                    text += response.segments.compactMap(\.text).joined()
                    phases += MetadataValues(response.metadata).structures(phasesKey).compactMap(MessagePhase.init)
                    serverToolCalls += kept(in: response.metadata)
                case .toolCalls(let toolCalls):
                    // An answer that ends in tool calls keeps its facts, its messages' phases and its server tools' calls
                    // among them, on its first call.
                    if let first = toolCalls.first {
                        if phases.isEmpty { phases = MetadataValues(first.metadata).structures(phasesKey).compactMap(MessagePhase.init) }
                        if serverToolCalls.isEmpty { serverToolCalls = kept(in: first.metadata) }
                    }
                    calls += toolCalls.map { call in
                        .functionCall(callID: call.id, name: call.toolName, arguments: JSONValue(call.arguments).text)
                    }
                default:
                    continue
                }
            }
            for call in skippedCalls {
                if let index = serverToolCalls.firstIndex(where: { $0.call == call }) { serverToolCalls.remove(at: index) }
            }
            let hasServerToolCalls = !serverToolCalls.isEmpty
            var messages = MessagePhase.split(text, into: phases).enumerated().map { index, message in
                Item.message(role: .assistant, content: .text(index == 0 ? block + message.text : message.text), phase: message.phase)
            }[...]
            // A reasoning item needs an item after it, which a block alone isn't.
            if messages.isEmpty, calls.isEmpty, serverToolCalls.isEmpty { order = [] }
            if messages.isEmpty, !block.isEmpty {
                messages = [.message(role: .assistant, content: .text(block), phase: nil)]
            }
            var rest = calls[...]
            for item in order {
                switch item {
                case .reasoning(let reasoning): items.append(.reasoning(reasoning))
                case .message: if let message = messages.popFirst() { items.append(message) }
                case .functionCall: if let call = rest.popFirst() { items.append(call) }
                case .serverToolCall(let call):
                    if let index = serverToolCalls.firstIndex(where: { $0.call == call }) {
                        let placed = serverToolCalls.remove(at: index)
                        items.append(.serverToolCall(placed.call, placed.item, fromStoredResponse: placed.fromStoredResponse))
                    }
                }
            }
            items += serverToolCalls.map { .serverToolCall($0.call, $0.item, fromStoredResponse: $0.fromStoredResponse) }
            items += messages
            items += rest
            // Reasoning whose following item doesn't go back, such as the empty message of an answer that is only an
            // image, would have nothing after it.
            while hasServerToolCalls, items.count > start, case .reasoning? = items.last { items.removeLast() }
        }

        /// The server tools' calls an entry's metadata keeps, each with its kind and whether the provider kept the
        /// response that made it, leaving out a kind the format doesn't know.
        private func kept(in metadata: [String: GeneratedContent]) -> [(call: ServerToolCall, item: JSONValue, fromStoredResponse: Bool)] {
            let output = ServerToolOutput(MetadataValues(metadata), key: serverToolsKey)
            return output.calls.compactMap { item in
                let type = item["type"]?.stringValue.map(ItemType.init(rawValue:))
                return type.flatMap(ServerToolCall.init).map { ($0, item, output.isStored) }
            }
        }
    }
}

// MARK: - Attachments

extension Responses.Input {
    /// The input part for a piece of content: text, an `input_image` or a PDF `input_file`.
    ///
    /// Images go as JPEG data URLs, or as their web address when they have one. Data attachments go by kind: text as
    /// text, images as images, and PDFs as `input_file` parts. The format has no part for other kinds, such as audio or
    /// video. The same attachment gives the same bytes every time.
    ///
    /// - Parameters:
    ///   - content: The content.
    ///   - entry: The entry that carries it, which the error names.
    ///   - provider: The provider's name, for the error.
    /// - Returns: The part.
    /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for data the format has no part for.
    private static func part(for content: AttachmentReader.Content, in entry: Transcript.Entry, provider: String) throws -> Part {
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

    /// One of an answer's server tools' calls, as the answer keeps it, and whether the provider kept the response that
    /// made it.
    case serverToolCall(Responses.ServerToolCall, JSONValue, fromStoredResponse: Bool)

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
        case .serverToolCall(_, let item, _):
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

/// The role of a message: `user`, `assistant`, or the one ``Responses/Model/instructionsRole`` gives the instructions.
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
