import Foundation
import FoundationModels
import LanguageModelsCore

// MARK: - Output items

/// One of an answer's `reasoning` output items, as a later request's input sends it back: the item the stream's
/// `response.output_item.done` carried, with members such as `type`, `id`, `summary` and `encrypted_content`, and
/// every other member the provider sent.
struct ReasoningItem: Encodable, Equatable {
    /// The item, as the provider sent it.
    let json: JSONValue

    /// Whether the item carries its reasoning encrypted, which a request that the provider doesn't store needs, since
    /// the provider can't look the item up by its id.
    var hasEncryptedContent: Bool {
        if case .string(let content)? = json["encrypted_content"] { !content.isEmpty } else { false }
    }

    func encode(to encoder: any Encoder) throws {
        try json.encode(to: encoder)
    }
}

/// One of an answer's output items, in the order the answer's reasoning entry keeps them in its signature: a
/// `reasoning` item whole, or the place of a message or a function call.
///
/// A signature is a JSON array. When every `reasoning` item came before the answer's messages and calls, as in most
/// answers, it holds the `reasoning` items alone. Otherwise it also holds `{"type": "message"}` and
/// `{"type": "function_call"}` in the places of the answer's messages and calls, so they go back between the
/// `reasoning` items as they came. Saved transcripts keep this shape, so it never changes.
enum OutputItem: Equatable {
    case reasoning(ReasoningItem)
    case message
    case functionCall

    /// The output items an entry's signature holds, in their order; none for an entry without one.
    static func items(inSignatureOf entry: Transcript.Reasoning) -> [OutputItem] {
        guard let signature = entry.signature, case .array(let items)? = try? JSONValue(json: signature) else { return [] }
        return items.compactMap { item in
            switch item["type"]?.stringValue.map(Responses.ItemType.init(rawValue:)) {
            case .reasoning?: .reasoning(ReasoningItem(json: item))
            case .message?: .message
            case .functionCall?: .functionCall
            default: nil
            }
        }
    }

    /// The signature for an answer's output items: the `reasoning` items alone when they all come first, or `nil`
    /// when there are none.
    static func signature(of items: [OutputItem]) -> Data? {
        let reasoning = items.filter { if case .reasoning = $0 { true } else { false } }
        guard !reasoning.isEmpty else { return nil }
        let kept = items.prefix(reasoning.count) == reasoning[...] ? reasoning : items
        return JSONValue.array(kept.map(\.json)).data
    }

    /// The item as the signature writes it.
    private var json: JSONValue {
        switch self {
        case .reasoning(let item): item.json
        case .message: ["type": .string(Responses.ItemType.message.rawValue)]
        case .functionCall: ["type": .string(Responses.ItemType.functionCall.rawValue)]
        }
    }
}

extension Responses {
    /// The `type` of an input or output item.
    struct ItemType: ProviderVocabulary {
        static let message: Self = "message"
        static let functionCall: Self = "function_call"
        static let functionCallOutput: Self = "function_call_output"
        static let reasoning: Self = "reasoning"

        let rawValue: String
    }
}

// MARK: - Message phases

extension Responses {
    /// The `phase` of one of an answer's messages, such as `commentary` or `final_answer`, and the length of its text, in
    /// characters, as the response entry's metadata keeps them, so each message goes back on later turns with its own
    /// phase. A message whose text is held out of the answer's text, such as a guided answer's `commentary`, keeps the text
    /// itself instead.
    package struct MessagePhase: Equatable {
        package private(set) var phase: String?
        package private(set) var length = 0

        /// The message's text when it's held out of the answer's text, or `nil` when the answer's text holds it.
        package private(set) var heldText: String?

        init(phase: String? = nil, length: Int = 0) {
            self.phase = phase
            self.length = length
        }

        /// A message whose text is held out of the answer's text.
        init(phase: String?, heldText: String) {
            self.phase = phase
            self.heldText = heldText
        }

        /// A message's phase read back from an element of the metadata, or `nil` for an element that isn't one.
        package init?(_ values: MetadataValues) {
            guard let length = values.integer(Field.length) else { return nil }
            self.init(phase: values.string(Field.phase), length: length)
            heldText = values.string(Field.heldText)
        }

        /// The message as an element of the metadata.
        var metadataValue: GeneratedContent {
            guard let heldText else { return GeneratedContent(properties: [Field.phase: phase, Field.length: length]) }
            return GeneratedContent(properties: [Field.phase: phase, Field.length: length, Field.heldText: heldText])
        }

        /// The phase of the message that holds an answer's final text, which a guided answer decodes.
        static let finalAnswer = "final_answer"

        /// The keys of an element. Saved transcripts keep them, so they never change.
        private enum Field {
            static let phase = "phase"
            static let length = "length"
            static let heldText = "heldText"
        }

        /// An answer's text split into its messages, each with its phase, and the held-out messages in their places; when
        /// the lengths don't add up to the text, as when the text changed, the held-out messages, then the whole text as
        /// one message with the last phase of the others.
        ///
        /// - Parameters:
        ///   - text: The answer's text.
        ///   - phases: The answer's messages, in their order.
        /// - Returns: The messages' texts and phases, leaving out empty texts.
        static func split(_ text: String, into phases: [MessagePhase]) -> [(text: String, phase: String?)] {
            let shown = phases.filter { $0.heldText == nil }
            guard shown.map(\.length).reduce(0, +) == text.count else {
                let held = phases.compactMap { message in message.heldText.map { (text: $0, phase: message.phase) } }
                return (held + [(text, shown.last?.phase)]).filter { !$0.text.isEmpty }
            }
            var rest = Substring(text)
            return phases.compactMap { message in
                if let heldText = message.heldText { return heldText.isEmpty ? nil : (heldText, message.phase) }
                let part = rest.prefix(message.length)
                rest = rest.dropFirst(message.length)
                return part.isEmpty ? nil : (String(part), message.phase)
            }
        }
    }
}
