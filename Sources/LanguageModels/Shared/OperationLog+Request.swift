package import Foundation
package import LanguageModelsCore
import os

extension OperationLog {
    /// Logs what a request leaves out or changes from what the app asked for, at `info` with the keys of metadata left
    /// out kept private, and shows it as a runtime warning in a debug build.
    ///
    /// - Parameters:
    ///   - adjustment: The change.
    ///   - model: The id of the model the request names first.
    ///   - provider: The provider's name, such as `OpenRouter`.
    package func report(_ adjustment: RequestAdjustment, model: String, provider: String) {
        if let logger = logger(.info) {
            let message = adjustment.message(model: model, provider: provider)
            if case .droppedMetadata(let keys) = adjustment {
                let keys = keys.joined(separator: ", ")
                logger.info("\(label, privacy: .public): \(message, privacy: .public) Keys: \(keys, privacy: .private)")
            } else {
                logger.info("\(label, privacy: .public): \(message, privacy: .public)")
            }
        }
        runtimeWarning(adjustment.warning(model: model, provider: provider))
    }

    /// Logs the retry of a request whose host rejected a constraint of its response schema.
    ///
    /// - Parameter host: The company whose servers rejected it, when the provider names one.
    package func retryingWithPortableSchema(host: String?) {
        logger(.info)?.info(
            """
            \(label, privacy: .public): \(host ?? "the host", privacy: .public) rejected a constraint of the response \
            schema; retrying with the portable schema.
            """
        )
    }

    /// Logs at `debug` what a request sends: the model and the names of the options, never the transcript.
    ///
    /// - Parameters:
    ///   - body: The request's body.
    ///   - model: The id of the model the request names.
    ///   - nonOptions: The body's members that aren't options, such as the model and the transcript.
    package func sending(_ body: JSONValue, to model: String, leavingOut nonOptions: Set<String>) {
        guard let logger = logger(.debug) else { return }
        let options = if case .object(let body) = body { body.members.map(\.key) } else { [String]() }
        let sent = options.filter { !nonOptions.contains($0) }.joined(separator: ", ")
        logger.debug("\(label, privacy: .public) to \(model, privacy: .public); sends \(sent, privacy: .public)")
    }

    /// Logs at `debug` which model and host answered, why the answer ended, the time to its first token and the
    /// request's whole time.
    ///
    /// - Parameters:
    ///   - report: What the format's own members reported about the answer.
    ///   - host: The company whose servers ran the model, when the provider names one.
    package func finished(_ report: AnswerReport, host: String?) {
        guard let logger = logger(.debug) else { return }
        logger.debug(
            """
            \(label, privacy: .public) answered by \(report.model ?? "an unnamed model", privacy: .public) on \
            \(host ?? "an unnamed host", privacy: .public) in \(elapsedMilliseconds) ms, first token after \
            \(firstTokenDelay, privacy: .public); finish reason \(report.finishReason?.rawValue ?? "none", privacy: .public)
            """
        )
    }

    /// Runs a request, logging the error it fails with: a failed connection's error as `URLError` maps it, and any
    /// other error as it is.
    ///
    /// - Parameter request: Sends the request, with the log to write to.
    /// - Returns: What the request returns.
    /// - Throws: What the request throws, with a `URLError` mapped the way a failed connection's is.
    package func run<Value>(_ request: (inout OperationLog) async throws -> Value) async throws -> Value {
        var log = self
        do {
            do {
                return try await request(&log)
            } catch let error as URLError {
                throw error.thrownError
            }
        } catch {
            log.failed(error)
            throw error
        }
    }

    /// Reads a response's server-sent events into an answer, until one ends the stream or the stream ends, and notes
    /// when the answer's first output arrived.
    ///
    /// - Parameters:
    ///   - bytes: The response's stream.
    ///   - answer: The answer the events go to.
    /// - Returns: Whether an event ended the stream.
    /// - Throws: What the answer throws for an event, what the stream throws, and `CancellationError` when the task is
    ///   cancelled.
    package mutating func read(_ bytes: URLSession.AsyncBytes, into answer: inout some StreamedAnswer) async throws -> Bool {
        var ended = false
        for try await event in ServerSentEvent.Events(bytes) {
            try Task.checkCancellation()
            if try await answer.receive(event) {
                ended = true
                break
            }
            if answer.hasOutput { receivedToken() }
        }
        try Task.checkCancellation()
        return ended
    }
}
