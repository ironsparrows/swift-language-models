package import Foundation
import LanguageModelsCore
import os

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
