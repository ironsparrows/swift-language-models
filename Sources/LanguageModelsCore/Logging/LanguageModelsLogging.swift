package import Foundation
import Synchronization
public import os

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
    static let subsystem = "com.ironsparrows.swift-language-models"

    private static let storedMinimumLevel = Atomic(OSLogType.debug.rawValue)

    /// The start of a request's id, which names it in the log.
    package static func requestName(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

extension OSLogType {
    /// The level's place by severity, from `.debug`, the least severe, to `.fault`. The levels' raw values don't
    /// follow it: `.default` is 0 and `.debug` is 2.
    var severity: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .error: 3
        case .fault: 4
        default: 2
        }
    }
}
