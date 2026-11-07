/// What a request executor reports of an answer it streamed, which the model's executor checks.
///
/// ``DetailedLanguageModelRequestExecutor/execute(_:model:streamingInto:)`` returns it once the answer's events are
/// sent. For a request with a schema, ``DetailedLanguageModelExecutor`` checks the response's text against the
/// schema's guides, since a host may drop or ignore constraints such as a guide's minimum.
public struct DetailedLanguageModelAnswer: Sendable {
    /// The text of the answer's response entry, as the request executor sent it, or empty when the answer ended in
    /// tool calls.
    public var responseText: String

    /// Creates the report of an answer.
    ///
    /// - Parameter responseText: The text of the answer's response entry, as the request executor sent it, or empty
    ///   when the answer ended in tool calls.
    public init(responseText: String) {
        self.responseText = responseText
    }
}
