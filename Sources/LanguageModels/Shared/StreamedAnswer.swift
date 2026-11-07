/// One answer's stream as a format reads it, one server-sent event at a time, and the events that end it.
package protocol StreamedAnswer {
    /// Sends the events for one server-sent event.
    ///
    /// - Returns: Whether the event ends the stream.
    mutating func receive(_ event: ServerSentEvent) async throws -> Bool

    /// Whether any of the answer's output has arrived: text, reasoning or a tool call.
    var hasOutput: Bool { get }

    /// What the answer's events reported about it so far.
    var report: AnswerReport { get }

    /// The text sent to the response entry, or empty when the answer ends in tool calls.
    var responseText: String { get }

    /// The company whose servers ran the model, when the provider names one.
    var host: String? { get }

    /// Sends the events that end the answer, or throws the error it ends in.
    ///
    /// - Parameter isComplete: Whether an event ended the stream, rather than the stream itself.
    /// - Throws: The error the answer ends in, such as the dialect's for a stream that was cut off.
    mutating func finish(isComplete: Bool) async throws
}
