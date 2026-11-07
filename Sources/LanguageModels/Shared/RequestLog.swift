import Foundation
import FoundationModels
import LanguageModelsCore
import os

// MARK: - Log

/// The timing, retry and failure messages of one request to a provider, a generation or a call for a model's info, under
/// a label that names it, such as `Request 1A2B3C4D`.
///
/// It logs retries at `info`, a cancellation at `debug` and any other failure at `error`, with the error's message
/// kept private, since it may quote the request.
struct RequestLog {
    /// What names the request in each message.
    let label: String
    /// The provider's log category.
    let logger: PackageLogger
    private let start = ContinuousClock.now
    private var firstToken: ContinuousClock.Instant?

    /// Starts the log of a request, and its timing.
    ///
    /// - Parameters:
    ///   - label: What names the request, such as `GET models`.
    ///   - logger: The provider's log category.
    init(_ label: String, logger: PackageLogger) {
        self.label = label
        self.logger = logger
    }

    /// Starts the log of a generation request, named by the start of the id Foundation Models gave it, as the core's
    /// own messages about the request name it.
    init(request id: UUID, logger: PackageLogger) {
        self.init("Request \(LanguageModelsLogging.requestName(id))", logger: logger)
    }

    /// The milliseconds since the request started.
    var elapsedMilliseconds: Int {
        Self.milliseconds(ContinuousClock.now - start)
    }

    /// When the first token arrived after the start, such as `120 ms`, or `never`.
    private var firstTokenDelay: String {
        firstToken.map { "\(Self.milliseconds($0 - start)) ms" } ?? "never"
    }

    /// Notes when the answer's first token arrived, once.
    mutating func receivedToken() {
        firstToken = firstToken ?? ContinuousClock.now
    }

    /// Logs a retry: the status of the response that failed, or the error of the connection that did, and which retry
    /// it is after how long a wait.
    func retrying(_ retry: HTTPClient.Retry) {
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
    func failed(_ error: any Error) {
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

// MARK: - Generation requests

extension RequestLog {
    /// Logs what a request leaves out or changes from what the app asked for, at `info` with the keys of metadata left
    /// out kept private, and shows it as a runtime warning in a debug build.
    ///
    /// - Parameters:
    ///   - adjustment: The change.
    ///   - model: The id of the model the request names first.
    ///   - provider: The provider's name, such as `OpenRouter`.
    func report(_ adjustment: RequestAdjustment, model: String, provider: String) {
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
    func retryingWithPortableSchema(host: String?) {
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
    func sending(_ body: JSONValue, to model: String, leavingOut nonOptions: Set<String>) {
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
    func finished(_ report: AnswerReport, host: String?) {
        guard let logger = logger(.debug) else { return }
        logger.debug(
            """
            \(label, privacy: .public) answered by \(report.model ?? "an unnamed model", privacy: .public) on \
            \(host ?? "an unnamed host", privacy: .public) in \(elapsedMilliseconds) ms, first token after \
            \(firstTokenDelay, privacy: .public); finish reason \(report.finishReason?.rawValue ?? "none", privacy: .public)
            """
        )
    }
}

// MARK: - Errors

/// What the log says about an error a request throws: its type, and the HTTP status, error code and host it came
/// from, so the log shows how a failure was mapped. Never its message, which may quote the request.
struct LoggedError: Equatable {
    /// The error's type, and its case for a `LanguageModelError`, such as `LanguageModelError.rateLimited`.
    let kind: String
    let status: Int?
    let code: String?
    let host: String?

    /// Where the error came from, such as `HTTP 429, rate_limit_exceeded, host Vendor`, with only the parts known.
    var origin: String {
        [status.map { "HTTP \($0)" }, code, host.map { "host \($0)" }].compactMap(\.self).joined(separator: ", ")
    }
}

extension LoggedError {
    /// The parts of an error: a provider error's own, a `LanguageModelError`'s from its metadata, and only the type of
    /// any other error.
    init(_ error: any Error) {
        switch error {
        case let error as any LoggableError:
            let fields = error.logFields
            self.init(kind: fields.kind, status: fields.status, code: fields.code, host: fields.host)
        case let error as LanguageModelError:
            let facts = error.providerMetadata
            self.init(kind: "LanguageModelError.\(error.caseName)", status: facts.status, code: facts.errorCode, host: facts.provider)
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
    /// The case's name.
    fileprivate var caseName: String {
        switch self {
        case .contextSizeExceeded: "contextSizeExceeded"
        case .rateLimited: "rateLimited"
        case .guardrailViolation: "guardrailViolation"
        case .refusal: "refusal"
        case .unsupportedCapability: "unsupportedCapability"
        case .unsupportedTranscriptContent: "unsupportedTranscriptContent"
        case .unsupportedGenerationGuide: "unsupportedGenerationGuide"
        case .unsupportedLanguageOrLocale: "unsupportedLanguageOrLocale"
        case .timeout: "timeout"
        @unknown default: "unknown"
        }
    }
}
