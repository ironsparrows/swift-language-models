package import os

/// One of the package's log categories, which writes only at the levels the app's
/// ``LanguageModelsLogging/minimumLevel`` lets through.
///
/// A provider makes one for each category it logs, and writes with the logger that a level returns:
///
/// ```swift
/// extension PackageLogger {
///     static let vendor = PackageLogger(category: "Vendor")
/// }
///
/// PackageLogger.vendor(.debug)?.debug("Sending \(id, privacy: .public)")
/// ```
///
/// A message at a level the app turned off returns `nil` before the message is built.
package struct PackageLogger: Sendable {
    private let logger: Logger

    /// Creates a category of the package's subsystem.
    ///
    /// - Parameter category: The category's name, such as the provider's.
    package init(category: String) {
        logger = Logger(subsystem: LanguageModelsLogging.subsystem, category: category)
    }

    /// The logger to write a message at a level with.
    ///
    /// - Parameter level: The message's level.
    /// - Returns: The logger, or `nil` when the app logs only more severe messages.
    package func callAsFunction(_ level: OSLogType) -> Logger? {
        level.severity >= LanguageModelsLogging.minimumLevel.severity ? logger : nil
    }
}

extension PackageLogger {
    /// The category of what the core logs for every provider module.
    static let languageModels = PackageLogger(category: "LanguageModels")
}
