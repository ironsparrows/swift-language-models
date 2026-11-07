import LanguageModelsCore
import os

extension InfoTransport {
    /// The messages one call to a provider's API besides generation logs, such as for a model's info.
    ///
    /// Calls log at `debug` how they end and whether the cache answered, at `info` their retries, and at `error` how
    /// they fail. They log the path, but never the key.
    struct CallLog {
        private let operation: OperationLog
        private var status: Int?

        /// Starts the log of a call, and its timing.
        ///
        /// - Parameters:
        ///   - path: The path under the base URL, such as `models/anthropic/claude-haiku-5.5/endpoints`.
        ///   - logger: The provider's log category.
        init(path: String, logger: PackageLogger) {
            operation = OperationLog("GET \(path)", logger: logger)
        }

        mutating func received(status: Int) {
            self.status = status
        }

        func answeredFromCache() {
            operation.logger(.debug)?.debug("\(operation.label, privacy: .public) answered from the cache.")
        }

        func retrying(_ retry: ProviderHTTP.Retry) {
            operation.retrying(retry)
        }

        func finished() {
            operation.logger(.debug)?.debug(
                "\(operation.label, privacy: .public) answered with HTTP \(status ?? 0) in \(operation.elapsedMilliseconds) ms.")
        }

        /// Logs a cancelled call at `debug`, and any other failure at `error`, with the error it became.
        func failed(_ error: any Error) {
            operation.failed(error)
        }
    }
}
