/// Why an answer ended, such as ``length`` when it reached its token limit.
///
/// The entry that ends an answer carries it under ``LanguageModelMetadataKey/finishReason``. Each provider module maps
/// its service's reasons onto these words, and passes on any other reason in its service's spelling, which is valid
/// too. An answer that a content filter stopped or that ended in an error throws instead, so no entry carries such a
/// reason.
public struct FinishReason: ProviderVocabulary {
    /// The model finished.
    public static let stop: Self = "stop"

    /// The answer reached its token limit, so its text is cut short.
    public static let length: Self = "length"

    /// The model asked for tool calls.
    public static let toolCalls: Self = "tool_calls"

    /// The reason's spelling.
    public let rawValue: String

    /// Creates a reason from its spelling.
    ///
    /// - Parameter rawValue: The reason, such as `"length"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
