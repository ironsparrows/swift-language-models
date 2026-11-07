import Foundation
import FoundationModels
import LanguageModelsCore

extension ResponsesRequest {
    /// A transcript as the format's `input` items.
    ///
    /// Instructions become a message in the dialect's instructions role, and prompts `user` messages. One answer
    /// becomes its `reasoning` items, an `assistant` message for each of its messages, with its text and `phase`, and a
    /// reasoning block that the model wrote in its answer's text back at the start of the first, and a `function_call`
    /// item for each of its tool calls, in the order they came, or with the `reasoning` items first when the order
    /// isn't known. An answer with neither text nor tool calls, as one cut off while it reasoned, sends no reasoning
    /// back, since a reasoning item needs an item after it. Each tool output becomes a `function_call_output` item,
    /// matched to its call by `call_id`. Prompts and tool outputs carry their attachments as input parts;
    /// generated data and an answer's attachments aren't sent back. Every entry turns into the same JSON each time, so
    /// a provider's prompt cache stays valid from one request to the next.
    struct Input {
        private(set) var items: [Item] = []

        /// Whether an item carries a PDF.
        private(set) var carriesPDF = false

        /// The transcript entries whose items carry an image, which a host's rejection of an image names.
        private(set) var imageEntries: [Transcript.Entry] = []

        private let attachments: ResponsesRequest.AttachmentParts

        /// The provider's name, for the errors.
        private let provider: String

        /// The role of the instructions' messages.
        private let instructionsRole: MessageRole

        /// The metadata key under which an answer's response entry keeps the phases of its messages.
        private let phasesKey: String

        /// Whether a reasoning entry goes back: one of the provider's own that its dialect sends back.
        private let replays: (Transcript.Reasoning) -> Bool

        /// The items for a transcript.
        ///
        /// A prompt that recorded a response schema, which Foundation Models does when the schema belongs in the
        /// prompt, carries the schema as text after its own, so every request writes it the same way.
        ///
        /// - Throws: `LanguageModelError.unsupportedTranscriptContent` for content the format or a model can't take,
        ///   and the dialect's errors for an attachment a model doesn't take.
        init<Dialect: ResponsesDialect>(_ transcript: some Sequence<Transcript.Entry>, dialect: Dialect) throws {
            attachments = ResponsesRequest.AttachmentParts(dialect: dialect)
            provider = Dialect.name
            instructionsRole = MessageRole(rawValue: dialect.instructionsRole.rawValue)
            phasesKey = Dialect.phasesMetadataKey
            replays = { ReasoningOrigin(of: $0) == Dialect.reasoningOrigin && dialect.replays($0) }
            for turn in try TranscriptTurn.turns(of: transcript, provider: provider) { try append(turn) }
        }

        /// The items without the `reasoning` items that carry no encrypted reasoning, which a request the provider
        /// doesn't store can't send back, since the provider can't look them up by their ids.
        var withEncryptedReasoningOnly: [Item] {
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
                carriesPDF = carriesPDF || attachmentParts.contains(where: \.isPDF)
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
