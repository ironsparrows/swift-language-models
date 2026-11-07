import Foundation
import FoundationModels
import LanguageModelsCore

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
