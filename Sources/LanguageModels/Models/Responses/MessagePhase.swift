import FoundationModels
import LanguageModelsCore

/// The `phase` of one of an answer's messages, such as `commentary` or `final_answer`, and the length of its text, in
/// characters, as the response entry's metadata keeps them, so each message goes back on later turns with its own
/// phase. A message whose text is held out of the answer's text, such as a guided answer's `commentary`, keeps the text
/// itself instead.
struct MessagePhase: Equatable {
    var phase: String?
    var length = 0

    /// The message's text when it's held out of the answer's text, or `nil` when the answer's text holds it.
    var heldText: String?

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
    init?(_ values: MetadataValues) {
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
    enum Field {
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
