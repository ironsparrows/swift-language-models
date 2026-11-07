import Foundation
import FoundationModels
import LanguageModelsCore
package import UniformTypeIdentifiers

// MARK: - Turns

extension ChatCompletions {
    /// A transcript as the format's `messages`.
    ///
    /// Instructions become `system` messages and prompts `user` messages. The reasoning, response text and tool calls
    /// of one answer become one `assistant` message, with a reasoning block that the model wrote in its answer's text
    /// back at the start of that text, and each tool output a `tool` message. The exchange adds the reasoning it sends
    /// back to the assistant message. Prompts and tool outputs carry their attachments as content parts; generated
    /// data and an answer's attachments aren't sent back. Every entry turns into the same JSON each time, so a
    /// provider's prompt cache stays valid from one request to the next.
    struct Messages {
        private var messages: [Message] = []

        private var reader: SegmentReader<Part>

        /// Whether a reasoning entry goes back: one of the provider's own that its exchange sends back.
        private let replays: (Transcript.Reasoning) -> Bool

        /// The assistant message's members for the reasoning it sends back.
        private let replayMembers: ([(entry: Transcript.Reasoning, text: String)]) -> JSONObject

        /// The messages for a transcript.
        ///
        /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for content the format or a model can't take,
        ///   and the exchange's errors for an attachment a model doesn't take.
        init<Exchange: ChatCompletions.Exchange>(
            _ transcript: some Sequence<Transcript.Entry>,
            model: ChatCompletions.Model<Exchange>,
            exchange: Exchange
        ) throws {
            let provider = model.providerName
            let media = Self.formatMedia + model.media
            reader = SegmentReader(
                provider: provider, encoding: model.images, instructions: "system messages",
                check: { (attachment, entry) throws(LanguageModelError) in try exchange.checkAttachment(attachment, in: entry) },
                makePart: { content, entry in try Self.part(for: content, in: entry, media: media, provider: provider) })
            let origin = model.reasoningOrigin
            replays = { $0.origin == origin && exchange.replays($0) }
            replayMembers = { exchange.replayMembers(for: $0) }
            for turn in try TranscriptTurn.turns(of: transcript, provider: provider) { try append(turn) }
        }

        /// Whether a message carries a PDF.
        var carriesPDF: Bool {
            reader.carriesPDF
        }

        /// The transcript entries whose messages carry an image, which a host's rejection of an image names.
        var imageEntries: [Transcript.Entry] {
            reader.imageEntries
        }

        /// The `messages` member.
        ///
        /// - Parameter marks: Members added to the last content part of the last instructions, such as a cache mark.
        /// - Returns: The messages, as JSON.
        /// - Throws: An error when a message can't be encoded.
        func json(marking marks: JSONObject?) throws -> JSONValue {
            try JSONValueEncoder.encode(marks.map(markingLastInstructions) ?? messages)
        }

        /// The messages with members added to the last content part of the last instructions, such as a cache mark.
        private func markingLastInstructions(with marks: JSONObject) -> [Message] {
            guard let index = messages.lastIndex(where: { if case .system = $0 { true } else { false } }),
                case .system(let content) = messages[index]
            else { return messages }
            var marked = messages
            marked[index] = .system(content.marked(with: marks))
            return marked
        }

        private mutating func append(_ turn: TranscriptTurn) throws {
            switch turn {
            case .instructions(let instructions, let entry):
                // A session without instructions still has an empty instructions entry, which hosts reject.
                let parts = try reader.textParts(instructions.segments, of: entry)
                guard !parts.isEmpty else { return }
                messages.append(.system(Content(parts)))
            case .prompt(let prompt, let entry):
                let parts = try reader.parts(of: prompt, in: entry)
                guard !parts.isEmpty else { return }
                messages.append(.user(Content(parts)))
            case .answer(let entries):
                var answer = AssistantTurn()
                for entry in entries { append(entry, to: &answer) }
                appendAssistantMessage(answer)
            case .toolOutput(let output, let entry):
                let parts = try reader.parts(output.segments, of: entry)
                let texts = parts.compactMap { part -> String? in
                    if case .text(let text, let marks) = part, marks.members.isEmpty { text } else { nil }
                }
                // Text alone goes as one string, a line per part, so a label doesn't run into its text; attachments need
                // the parts.
                let content: Content = texts.count == parts.count ? .text(texts.joined(separator: "\n")) : .parts(parts)
                messages.append(.tool(callID: output.id, content: content))
            }
        }

        /// Adds one of an answer's reasoning, response or tool-call entries to its assistant message.
        private mutating func append(_ entry: Transcript.Entry, to turn: inout AssistantTurn) {
            switch entry {
            case .reasoning(let reasoning):
                // Reasoning that another provider wrote is in its own format, so only the provider's own goes back.
                guard replays(reasoning) else { return }
                // A block the model wrote in its answer's text goes back there, as it was written: MiniMax M2 needs its
                // `<think>` blocks back within a tool loop, Nova's tool loop takes its `<thinking>` text back, and a chat
                // template that drops older blocks finds them by their tags.
                turn.message.text = (TaggedReasoning.block(of: reasoning) ?? "") + turn.message.text
                turn.reasoning.append(reasoning)
            case .response(let response):
                // An answer's attachments aren't sent back, since the format's assistant messages take only text.
                turn.message.text += response.segments.compactMap(\.text).joined()
            case .toolCalls(let toolCalls):
                turn.message.toolCalls += toolCalls.map { call in
                    ToolCall(id: call.id, name: call.toolName, arguments: JSONValue(call.arguments).text)
                }
            default:
                return
            }
        }

        /// Adds an answer's assistant message, unless the answer left nothing to send back.
        private mutating func appendAssistantMessage(_ turn: AssistantTurn) {
            var message = turn.message
            message.replay = turn.reasoning.isEmpty ? JSONObject() : replayMembers(turn.reasoning.map { ($0, Self.replayedText(of: $0)) })
            let carriesReasoning = message.replay.members.contains { !$0.value.isEmpty }
            guard !message.text.isEmpty || carriesReasoning || !message.toolCalls.isEmpty else { return }
            messages.append(.assistant(message))
        }

        /// The text of a reasoning entry that goes back, or empty text for a block the model wrote at the start of its
        /// answer's text, which goes back there instead.
        private static func replayedText(of reasoning: Transcript.Reasoning) -> String {
            TaggedReasoning.block(of: reasoning) == nil ? reasoning.segments.compactMap(\.text).joined() : ""
        }
    }
}

extension ChatCompletions.Messages {
    /// The parts of one answer that become one `assistant` message.
    private struct AssistantTurn {
        var message = Assistant()

        /// The reasoning entries that go back, in their order.
        var reasoning: [Transcript.Reasoning] = []
    }
}

extension JSONValue {
    /// Whether the value is an empty list, an empty text or `null`, which carries nothing.
    fileprivate var isEmpty: Bool {
        switch self {
        case .null: true
        case .string(let text): text.isEmpty
        case .array(let elements): elements.isEmpty
        default: false
        }
    }
}

// MARK: - Attachments

extension ChatCompletions.Messages {
    /// The kinds of audio `input_audio` takes in the format, WAV and MP3, each with its name.
    private static let formatMedia: [ChatCompletions.MediaPart] = [.audio(.wav, format: "wav"), .audio(.mp3, format: "mp3")]

    /// The content part for a piece of content: text, an `image_url`, a PDF `file`, or the part of the first kind of audio
    /// or movie it conforms to.
    ///
    /// Images go as JPEG data URLs, or as their web address when they have one. Data attachments go by kind: text as
    /// text, images as images, PDFs as `file` parts, WAV and MP3 audio as `input_audio` with its format, and the kinds of
    /// audio and movies the model adds as their parts. The same attachment gives the same bytes every time.
    ///
    /// - Parameters:
    ///   - content: The content.
    ///   - entry: The entry that carries it, which the error names.
    ///   - media: The kinds of audio and movies the format takes, then the ones the model adds, in the order they're
    ///     matched.
    ///   - provider: The provider's name, for the error.
    /// - Returns: The part.
    /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for data that neither the format nor the model has a
    ///   part for.
    private static func part(
        for content: AttachmentReader.Content, in entry: Transcript.Entry, media: [ChatCompletions.MediaPart], provider: String
    ) throws -> Part {
        switch content {
        case .text(let text):
            return .text(text)
        case .jpeg(let data):
            return .image(url: DataURL(mediaType: MediaType.jpeg, data: data).text)
        case .imageURL(let url):
            return .image(url: url.absoluteString)
        case .pdf(let data, let fileName):
            return .file(name: fileName, data: DataURL(mediaType: MediaType.pdf, data: data).text)
        case .data(let data, let type):
            switch media.first(where: { type.conforms(to: $0.contentType) })?.part {
            case .audio(let format)?:
                return .audio(data: data.base64EncodedString(), format: format)
            case .video(let mediaType)?:
                return .video(url: DataURL(mediaType: mediaType, data: data).text)
            case nil:
                throw LanguageModelError.unsupported(entry, "\(provider) takes no attachments of type \(type.identifier).")
            }
        }
    }
}

extension ChatCompletions {
    /// A kind of data a provider takes beyond the format's, and the content part it goes in.
    package struct MediaPart: Sendable {
        /// The part a kind of data goes in.
        fileprivate enum Part: Sendable {
            /// An `input_audio` part, with the provider's name for the format.
            case audio(format: String)

            /// A `video_url` part, holding the movie as a data URL of the media type.
            case video(mediaType: String)
        }

        /// The kind of data, which the attachment's content type conforms to.
        fileprivate let contentType: UTType

        fileprivate let part: Part

        /// Audio of a kind, sent as `input_audio` with the format's name.
        package static func audio(_ contentType: UTType, format: String) -> Self {
            Self(contentType: contentType, part: .audio(format: format))
        }

        /// A movie of a kind, sent as a `video_url` data URL of the media type.
        package static func video(_ contentType: UTType, mediaType: String) -> Self {
            Self(contentType: contentType, part: .video(mediaType: mediaType))
        }
    }
}

// MARK: - Wire

/// One message of the format's `messages`.
private enum Message: Encodable {
    /// Instructions, as a `system` message.
    case system(Content)

    /// A prompt, as a `user` message.
    case user(Content)

    /// One answer's text, the reasoning it sends back and its tool calls, as an `assistant` message.
    case assistant(Assistant)

    /// A tool's output, as a `tool` message answering the call of the id.
    case tool(callID: String, content: Content)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        switch self {
        case .system(let content):
            try container.encode(Role.system, forKey: "role")
            try container.encode(content, forKey: "content")
        case .user(let content):
            try container.encode(Role.user, forKey: "role")
            try container.encode(content, forKey: "content")
        case .assistant(let assistant):
            try container.encode(Role.assistant, forKey: "role")
            if !assistant.text.isEmpty { try container.encode(assistant.text, forKey: "content") }
            for member in assistant.replay.members {
                try container.encode(member.value, forKey: JSONKey(stringValue: member.key))
            }
            if !assistant.toolCalls.isEmpty { try container.encode(assistant.toolCalls, forKey: "tool_calls") }
        case .tool(let callID, let content):
            try container.encode(Role.tool, forKey: "role")
            try container.encode(callID, forKey: "tool_call_id")
            try container.encode(content, forKey: "content")
        }
    }
}

/// An `assistant` message's parts: the answer's text, with a reasoning block the model wrote in its text back at
/// the start, the members of the reasoning it sends back, and its tool calls.
private struct Assistant {
    var text = ""
    var replay = JSONObject()
    var toolCalls: [ToolCall] = []
}

/// A message's content: one text as a plain string, otherwise its parts.
private enum Content: Encodable {
    case text(String)
    case parts([Part])

    /// The content of parts: a plain string for one text part without added members, otherwise the parts.
    init(_ parts: [Part]) {
        if parts.count == 1, case .text(let text, let marks) = parts[0], marks.members.isEmpty {
            self = .text(text)
        } else {
            self = .parts(parts)
        }
    }

    /// The content with members added to its last part, such as a cache mark, which makes a plain string a part.
    func marked(with marks: JSONObject) -> Content {
        var parts: [Part] =
            switch self {
            case .text(let text): [.text(text)]
            case .parts(let parts): parts
            }
        guard let last = parts.last else { return self }
        parts[parts.count - 1] = last.marked(with: marks)
        return .parts(parts)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

/// A content part of a message.
private enum Part: Encodable {
    /// Text, with members a provider added, such as a cache mark.
    case text(String, marks: JSONObject = JSONObject())

    /// An image, at a web address or in a data URL.
    case image(url: String)

    /// A file, such as a PDF, in a data URL.
    case file(name: String, data: String)

    /// Audio as Base64, with its format's name.
    case audio(data: String, format: String)

    /// A movie in a data URL.
    case video(url: String)

    /// The part's `type`.
    var type: PartType {
        switch self {
        case .text: .text
        case .image: .image
        case .file: .file
        case .audio: .audio
        case .video: .video
        }
    }

    /// The part with members added, which only a text part takes.
    func marked(with marks: JSONObject) -> Part {
        guard case .text(let text, var existing) = self else { return self }
        for mark in marks.members { existing[mark.key] = mark.value }
        return .text(text, marks: existing)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        try container.encode(type, forKey: "type")
        switch self {
        case .text(let text, let marks):
            try container.encode(text, forKey: "text")
            for mark in marks.members { try container.encode(mark.value, forKey: JSONKey(stringValue: mark.key)) }
        case .image(let url):
            try container.encode(["url": url], forKey: "image_url")
        case .file(let name, let data):
            var file = container.nestedContainer(keyedBy: JSONKey.self, forKey: "file")
            try file.encode(name, forKey: "filename")
            try file.encode(data, forKey: "file_data")
        case .audio(let data, let format):
            var audio = container.nestedContainer(keyedBy: JSONKey.self, forKey: "input_audio")
            try audio.encode(data, forKey: "data")
            try audio.encode(format, forKey: "format")
        case .video(let url):
            try container.encode(["url": url], forKey: "video_url")
        }
    }
}

/// One tool call of an `assistant` message, with its arguments as JSON text.
private struct ToolCall: Encodable {
    let id: String
    let name: String
    let arguments: String

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        try container.encode(id, forKey: "id")
        try container.encode("function", forKey: "type")
        var function = container.nestedContainer(keyedBy: JSONKey.self, forKey: "function")
        try function.encode(name, forKey: "name")
        try function.encode(arguments, forKey: "arguments")
    }
}

/// Who wrote a message: the instructions, the person, the model or a tool.
private struct Role: ProviderVocabulary {
    static let system: Self = "system"
    static let user: Self = "user"
    static let assistant: Self = "assistant"
    static let tool: Self = "tool"

    let rawValue: String
}

/// The `type` of a message's content part.
private struct PartType: ProviderVocabulary {
    static let text: Self = "text"
    static let image: Self = "image_url"
    static let file: Self = "file"
    static let audio: Self = "input_audio"
    static let video: Self = "video_url"

    let rawValue: String
}
