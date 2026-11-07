package import Foundation
import FoundationModels
package import LanguageModelsCore
import os

// MARK: - Log

/// The timing, retry and failure messages of one operation a provider runs, such as a request or a call for a model's
/// info, under a label that names it, such as `Request 1A2B3C4D`.
///
/// It logs retries at `info`, a cancellation at `debug` and any other failure at `error`, with the error's message
/// kept private, since it may quote the request.
package struct OperationLog {
    /// What names the operation in each message.
    package let label: String
    /// The provider's log category.
    package let logger: PackageLogger
    private let start = ContinuousClock.now
    private var firstToken: ContinuousClock.Instant?

    /// Starts the log of an operation, and its timing.
    ///
    /// - Parameters:
    ///   - label: What names the operation, such as `GET models`.
    ///   - logger: The provider's log category.
    package init(_ label: String, logger: PackageLogger) {
        self.label = label
        self.logger = logger
    }

    /// Starts the log of a generation request, named by the start of the id Foundation Models gave it, as the core's
    /// own messages about the request name it.
    package init(request id: UUID, logger: PackageLogger) {
        self.init("Request \(LanguageModelsLogging.requestName(id))", logger: logger)
    }

    /// The milliseconds since the operation started.
    package var elapsedMilliseconds: Int {
        Self.milliseconds(ContinuousClock.now - start)
    }

    /// When the first token arrived after the start, such as `120 ms`, or `never`.
    package var firstTokenDelay: String {
        firstToken.map { "\(Self.milliseconds($0 - start)) ms" } ?? "never"
    }

    /// Notes when the answer's first token arrived, once.
    package mutating func receivedToken() {
        firstToken = firstToken ?? ContinuousClock.now
    }

    /// Logs a retry: the status of the response that failed, or the error of the connection that did, and which retry
    /// it is after how long a wait.
    package func retrying(_ retry: ProviderHTTP.Retry) {
        guard let logger = logger(.info) else { return }
        let failure = retry.status.map { " got HTTP \($0)" } ?? "'s connection failed with URLError \(retry.error?.code.rawValue ?? 0)"
        logger.info(
            """
            \(label, privacy: .public)\(failure, privacy: .public); sending it again (retry \(retry.number) of \
            \(retry.limit)) after \(Self.milliseconds(retry.wait)) ms.
            """
        )
    }

    /// Logs a cancellation at `debug`, and any other failure at `error`, with the error it became.
    package func failed(_ error: any Error) {
        if error is CancellationError {
            logger(.debug)?.debug("\(label, privacy: .public) was cancelled after \(elapsedMilliseconds) ms.")
            return
        }
        guard let logger = logger(.error) else { return }
        let failure = LoggedError(error)
        let origin = failure.origin.isEmpty ? "" : " (\(failure.origin))"
        logger.error(
            """
            \(label, privacy: .public) failed after \(elapsedMilliseconds) ms with \(failure.kind, privacy: .public)\
            \(origin, privacy: .public).
            """
        )
    }

    /// A duration in whole milliseconds.
    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration / .milliseconds(1))
    }
}

// MARK: - Requests

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

// MARK: - Errors

/// What the log says about an error a request throws: its type, and the HTTP status, error code and host it came
/// from, so the log shows how a failure was mapped. Never its message, which may quote the request.
package struct LoggedError: Equatable {
    /// The error's type, and its case for a `LanguageModelError`, such as `LanguageModelError.rateLimited`.
    package let kind: String
    package let status: Int?
    package let code: String?
    package let host: String?

    package init(kind: String, status: Int?, code: String?, host: String?) {
        self.kind = kind
        self.status = status
        self.code = code
        self.host = host
    }

    /// Where the error came from, such as `HTTP 429, rate_limit_exceeded, host Vendor`, with only the parts known.
    package var origin: String {
        [status.map { "HTTP \($0)" }, code, host.map { "host \($0)" }].compactMap(\.self).joined(separator: ", ")
    }
}

extension LoggedError {
    /// The parts of an error: a provider error's own, a `LanguageModelError`'s from its metadata, and only the type of
    /// any other error.
    package init(_ error: any Error) {
        switch error {
        case let error as any LoggableError:
            let fields = error.logFields
            self.init(kind: fields.kind, status: fields.status, code: fields.code, host: fields.host)
        case let error as LanguageModelError:
            let (name, metadata) = error.parts
            self.init(
                kind: "LanguageModelError.\(name)",
                status: metadata[LanguageModelMetadataKey.status] as? Int,
                code: metadata[LanguageModelMetadataKey.errorCode] as? String,
                host: metadata[LanguageModelMetadataKey.provider] as? String
            )
        default:
            self.init(kind: String(reflecting: type(of: error)), status: nil, code: nil, host: nil)
        }
    }
}

/// An error the request log can describe, as a provider's own error is.
package protocol LoggableError: Error {
    /// What the log says of the error: its type, HTTP status, code and host, never its message.
    var logFields: (kind: String, status: Int?, code: String?, host: String?) { get }
}

extension LanguageModelError {
    /// The case's name and metadata.
    fileprivate var parts: (name: String, metadata: [String: any Sendable]) {
        switch self {
        case .contextSizeExceeded(let context): ("contextSizeExceeded", context.metadata)
        case .rateLimited(let context): ("rateLimited", context.metadata)
        case .guardrailViolation(let context): ("guardrailViolation", context.metadata)
        case .refusal(let context): ("refusal", context.metadata)
        case .unsupportedCapability(let context): ("unsupportedCapability", context.metadata)
        case .unsupportedTranscriptContent(let context): ("unsupportedTranscriptContent", context.metadata)
        case .unsupportedGenerationGuide(let context): ("unsupportedGenerationGuide", context.metadata)
        case .unsupportedLanguageOrLocale(let context): ("unsupportedLanguageOrLocale", context.metadata)
        case .timeout(let context): ("timeout", context.metadata)
        @unknown default: ("unknown", [:])
        }
    }
}
