package import Foundation
import MachO
import Synchronization
public import os

// MARK: - Logging

/// How much the package writes to the unified logging system.
///
/// The package logs what each request sends, what it leaves out or changes from what the app asked for, retries,
/// which model and host answered, failures, and how long each request took. Every message has the subsystem
/// `com.ironsparrows.swift-language-models` and a category named after each provider module, or `LanguageModels` for
/// what the core logs, such as a request that may reach a model its provider stopped listing.
///
/// It never logs API keys, prompts, answers, tool arguments or outputs, or attachments, nor a host's error message,
/// which may quote the request. This covers the package's own logging: a recording with Instruments' Foundation Models
/// template can include prompts and responses, which Foundation Models records. Model ids, host names, parameter
/// names, HTTP statuses, error codes and timings are public.
///
/// Logging is on at every level, and the system decides what it keeps, as it does for Apple's frameworks: debug
/// messages only while a tool such as Xcode or Console shows them, info messages only in memory, and errors on disk.
/// Set a level once, early, to log less:
///
/// ```swift
/// LanguageModelsLogging.minimumLevel = .error  // Only failed requests and removed models.
/// LanguageModelsLogging.minimumLevel = .fault  // Nothing, since the package logs no faults.
/// ```
public enum LanguageModelsLogging {
    /// The least severe messages the package logs, from `.debug`, the least severe, through `.info`, `.default`
    /// and `.error` to `.fault`. The default is `.debug`, every message.
    ///
    /// The package logs at `.debug`, `.info` and `.error` only, so `.default` logs what `.error` does, and `.fault`
    /// logs nothing and also turns off the runtime warnings.
    ///
    /// Any thread can read and set it.
    public static var minimumLevel: OSLogType {
        get { OSLogType(rawValue: storedMinimumLevel.load(ordering: .relaxed)) }
        set { storedMinimumLevel.store(newValue.rawValue, ordering: .relaxed) }
    }

    /// The subsystem of every message the package logs.
    fileprivate static let subsystem = "com.ironsparrows.swift-language-models"

    private static let storedMinimumLevel = Atomic(OSLogType.debug.rawValue)

    /// The start of a request's id, which names it in the log.
    package static func requestName(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

extension OSLogType {
    /// The level's place by severity, from `.debug`, the least severe, to `.fault`. The levels' raw values don't
    /// follow it: `.default` is 0 and `.debug` is 2.
    fileprivate var severity: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .error: 3
        case .fault: 4
        default: 2
        }
    }
}

// MARK: - Package logger

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

// MARK: - Runtime warnings

/// Shows a purple runtime warning in Xcode, in a debug build, for a likely mistake in the app that the package worked
/// around, such as a setting the model doesn't take.
///
/// Apple has no API for runtime warnings, so this does what Point-Free's IssueReporting does: it logs a fault to the
/// `com.apple.runtime-issues` subsystem, which Xcode shows as a runtime issue when the fault seems to come from one of
/// Apple's frameworks. The fault names SwiftUI's image when the process has loaded SwiftUI, and the caller's otherwise.
///
/// A release build shows nothing, and neither does a debug build whose app set ``LanguageModelsLogging/minimumLevel``
/// to `.fault`; any other level leaves the warnings on.
///
/// - Parameters:
///   - message: What the app likely got wrong, and what the package did instead.
///   - fileID: A file whose module names the warning's category, by default the caller's.
///   - dso: The caller's image, which the fault names when SwiftUI isn't loaded.
@safe
package func runtimeWarning(
    _ message: @autoclosure () -> String,
    fileID: StaticString = #fileID,
    dso: UnsafeRawPointer = #dsohandle
) {
    #if DEBUG
    guard LanguageModelsLogging.minimumLevel != .fault else { return }
    let module = String("\(fileID)".prefix { $0 != "/" })
    // `unsafe`: os_log reads the Mach-O header that `dso` points to, to name the image. SwiftUI's header and the
    // caller's both stay valid while the process runs, since neither image is ever unloaded.
    unsafe os_log(.fault, dso: swiftUIImage() ?? dso, log: OSLog(subsystem: "com.apple.runtime-issues", category: module), "%@", message())
    #endif
}

#if DEBUG
/// The Mach-O header of SwiftUI's image, or `nil` when the process hasn't loaded SwiftUI.
private func swiftUIImage() -> UnsafeRawPointer? {
    for index in 0..<_dyld_image_count() {
        // `unsafe`: dyld returns a C string and a header that stay valid while the image is loaded, and a name of `nil`
        // for an index that another thread unloaded meanwhile. SwiftUI is never unloaded.
        guard let name = unsafe _dyld_get_image_name(index), unsafe String(cString: name).hasSuffix("/SwiftUI") else { continue }
        return unsafe _dyld_get_image_header(index).map { unsafe UnsafeRawPointer($0) }
    }
    return nil
}
#endif
