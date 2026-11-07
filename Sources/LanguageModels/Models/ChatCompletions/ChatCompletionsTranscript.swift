import Foundation
import FoundationModels
import LanguageModelsCore
package import UniformTypeIdentifiers

// MARK: - Turns

extension ChatCompletionRequest {
    /// A transcript as the format's `messages`.
    ///
    /// Instructions become `system` messages and prompts `user` messages. The reasoning, response text and tool calls
    /// of one answer become one `assistant` message, with a reasoning block that the model wrote in its answer's text
    /// back at the start of that text, and each tool output a `tool` message. The dialect adds the reasoning it sends
    /// back to the assistant message. Prompts and tool outputs carry their attachments as content parts; generated
    /// data and an answer's attachments aren't sent back. Every entry turns into the same JSON each time, so a
    /// provider's prompt cache stays valid from one request to the next.
    struct Messages {
        private(set) var messages: [Message] = []

        /// Whether a message carries a PDF.
        private(set) var carriesPDF = false

        /// The transcript entries whose messages carry an image, which a host's rejection of an image names.
        private(set) var imageEntries: [Transcript.Entry] = []

        private let attachments: ChatCompletionRequest.AttachmentParts

        /// The provider's name, for the errors.
        private let provider: String

        /// Whether a reasoning entry goes back: one of the provider's own that its dialect sends back.
        private let replays: (Transcript.Reasoning) -> Bool

        /// The assistant message's members for the reasoning it sends back.
        private let replayMembers: ([Transcript.Reasoning]) throws -> JSONObject

        /// The messages for a transcript.
        ///
        /// A prompt that recorded a response schema, which Foundation Models does when the schema belongs in the
        /// prompt, carries the schema as text after its own, so every request writes it the same way.
        ///
        /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for content the format or a model can't take,
        ///   and the dialect's errors for an attachment a model doesn't take.
        init<Dialect: ChatCompletionsDialect>(_ transcript: some Sequence<Transcript.Entry>, dialect: Dialect) throws {
            attachments = ChatCompletionRequest.AttachmentParts(dialect: dialect)
            provider = Dialect.name
            replays = { ReasoningOrigin(of: $0) == Dialect.reasoningOrigin && dialect.replays($0) }
            replayMembers = { try JSONValueEncoder.members(of: dialect.replayMembers($0.map(ReplayedReasoning.init))) }
            for turn in try TranscriptTurn.turns(of: transcript, provider: provider) { try append(turn) }
        }

        /// The messages with members added to the last content part of the last instructions, such as a cache mark.
        func markingLastInstructions(with marks: JSONObject) -> [Message] {
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
                let parts = try textParts(instructions.segments, of: entry)
                guard !parts.isEmpty else { return }
                messages.append(.system(Content(parts)))
            case .prompt(let prompt, let entry):
                var parts = try parts(prompt.segments, of: entry)
                if case .schema(let schema)? = prompt.responseFormat?.kind {
                    parts.append(.text(try schema.promptInstructions()))
                }
                guard !parts.isEmpty else { return }
                messages.append(.user(Content(parts)))
            case .answer(let entries):
                var answer = AssistantTurn()
                for entry in entries { append(entry, to: &answer) }
                try appendAssistantMessage(answer)
            case .toolOutput(let output, let entry):
                let parts = try parts(output.segments, of: entry)
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
        private mutating func appendAssistantMessage(_ turn: AssistantTurn) throws {
            var message = turn.message
            message.replay = turn.reasoning.isEmpty ? JSONObject() : try replayMembers(turn.reasoning)
            let carriesReasoning = message.replay.members.contains { !$0.value.isEmpty }
            guard !message.text.isEmpty || carriesReasoning || !message.toolCalls.isEmpty else { return }
            messages.append(.assistant(message))
        }

        /// Text, structure and attachment segments as content parts, in their order.
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
                carriesPDF = carriesPDF || attachmentParts.contains { $0.type == .file }
                if attachmentParts.contains(where: { $0.type == .image }), !imageEntries.contains(where: { $0.id == entry.id }) {
                    imageEntries.append(entry)
                }
                parts += attachmentParts
            }
            return parts
        }

        /// Text and structure segments as text parts.
        ///
        /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for attachments, which `system` messages don't
        ///   take, and for a kind of segment the format can't take.
        private func textParts(_ segments: [Transcript.Segment], of entry: Transcript.Entry) throws -> [Part] {
            try segments.map { segment in
                if let text = segment.text { return .text(text) }
                if case .attachment = segment {
                    throw LanguageModelError.unsupported(entry, "\(provider)'s system messages take only text, not attachments.")
                }
                throw LanguageModelError.unsupported(entry, "\(provider) can't take this kind of segment yet.")
            }
        }
    }
}

extension ChatCompletionRequest.Messages {
    /// The parts of one answer that become one `assistant` message.
    private struct AssistantTurn {
        var message = ChatCompletionRequest.Assistant()

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

extension ChatCompletionRequest {
    /// Prompt and tool-output attachments as the format's content parts.
    ///
    /// A label goes first, as a text part of its own, so the model can name the attachment, as an `ImageReference`
    /// does. Images go as JPEG data URLs in `image_url` parts, or as their web address when they have one. Data
    /// attachments go by kind: text as text, images as images, PDFs as `file` parts, WAV and MP3 audio as
    /// `input_audio` with its format, and the kinds of audio and movies the dialect adds as their parts. The dialect
    /// first checks that its models take the attachment. The same attachment gives the same bytes every time.
    struct AttachmentParts {
        /// The provider's name, for the errors.
        private let provider: String

        private let reader: AttachmentReader

        /// Checks that every model takes an attachment.
        private let check: (AttachmentKind, Transcript.Entry) throws(LanguageModelError) -> Void

        /// The kinds of audio and movies the format takes, then the ones the dialect adds, in the order they're
        /// matched.
        private let media: [MediaPart]

        init<Dialect: ChatCompletionsDialect>(dialect: Dialect) {
            provider = Dialect.name
            reader = AttachmentReader(provider: provider, encoding: dialect.imageEncoding)
            check = { (attachment, entry) throws(LanguageModelError) in try dialect.check(attachment, in: entry) }
            media = Self.formatMedia + Dialect.extraMedia
        }

        /// The kinds of audio `input_audio` takes in the format, WAV and MP3, each with its name.
        private static let formatMedia: [MediaPart] = [.audio(.wav, format: "wav"), .audio(.mp3, format: "mp3")]

        /// The parts for one attachment: its label, when it has one, then the attachment.
        ///
        /// - Throws: The dialect's errors for an attachment a model doesn't take, and
        ///   `LanguageModelError.unsupportedTranscriptContent` for one that can't be read or that neither the format
        ///   nor the dialect has a part for.
        func parts(for segment: Transcript.AttachmentSegment, in entry: Transcript.Entry) throws -> [Part] {
            let content = try reader.content(of: segment, in: entry) { (kind) throws(LanguageModelError) in try check(kind, entry) }
            return (segment.givenLabel.map { [.text($0)] } ?? []) + [try part(for: content, in: entry)]
        }

        /// The content part for an attachment's content: text, an `image_url`, a PDF `file`, or the part of the first
        /// kind of audio or movie it conforms to.
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
}

/// A kind of data a provider takes beyond the format's, and the content part it goes in.
package struct MediaPart: Sendable {
    /// The part a kind of data goes in.
    enum Part: Sendable, Equatable {
        /// An `input_audio` part, with the provider's name for the format.
        case audio(format: String)

        /// A `video_url` part, holding the movie as a data URL of the media type.
        case video(mediaType: String)
    }

    /// The kind of data, which the attachment's content type conforms to.
    let contentType: UTType

    let part: Part

    /// Audio of a kind, sent as `input_audio` with the format's name.
    package static func audio(_ contentType: UTType, format: String) -> Self {
        Self(contentType: contentType, part: .audio(format: format))
    }

    /// A movie of a kind, sent as a `video_url` data URL of the media type.
    package static func video(_ contentType: UTType, mediaType: String) -> Self {
        Self(contentType: contentType, part: .video(mediaType: mediaType))
    }
}

// MARK: - Wire

extension ChatCompletionRequest {
    /// One message of the format's `messages`.
    enum Message: Encodable, Equatable {
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
    struct Assistant: Equatable {
        var text = ""
        var replay = JSONObject()
        var toolCalls: [ToolCall] = []
    }

    /// A message's content: one text as a plain string, otherwise its parts.
    enum Content: Encodable, Equatable {
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
    enum Part: Encodable, Equatable {
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
    struct ToolCall: Encodable, Equatable {
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
    struct Role: ProviderVocabulary {
        static let system: Self = "system"
        static let user: Self = "user"
        static let assistant: Self = "assistant"
        static let tool: Self = "tool"

        let rawValue: String
    }

    /// The `type` of a message's content part.
    struct PartType: ProviderVocabulary {
        static let text: Self = "text"
        static let image: Self = "image_url"
        static let file: Self = "file"
        static let audio: Self = "input_audio"
        static let video: Self = "video_url"

        let rawValue: String
    }
}
