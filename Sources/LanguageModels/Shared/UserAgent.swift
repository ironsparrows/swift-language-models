package import Foundation
import LanguageModelsCore

/// The `User-Agent` that names the package on every request, such as
/// `swift-language-models (com.example.Planner/2.3; Swift/6.4; iOS/27.0.1)`.
///
/// The package's name comes first, so a provider credits the traffic to it, whichever app sends it. The app's bundle
/// id and version follow, read from the main bundle, then the Swift and operating system versions. Outside an app
/// bundle, as in a command-line tool or a test, the app is left out. It's what the app reports about itself, for a
/// provider's statistics, not proof of anything.
package enum UserAgent {
    /// The `User-Agent` of this process.
    package static let current = value(app: app(of: .main), swiftVersion: swiftVersion, system: system)

    /// A `User-Agent`: the package, then a comment of the app, the Swift version and the operating system.
    ///
    /// - Parameters:
    ///   - app: The app's bundle id and version, such as `com.example.Planner/2.3`, or `nil` to leave the app out.
    ///   - swiftVersion: The version of the Swift compiler that built the package, such as `6.4`.
    ///   - system: The operating system and its version, such as `iOS/27.0.1`.
    /// - Returns: The header's value.
    package static func value(app: String?, swiftVersion: String, system: String) -> String {
        let comment = [app, "Swift/\(swiftVersion)", system].compactMap(\.self).joined(separator: "; ")
        return "swift-language-models (\(comment))"
    }

    /// The bundle id and version of an app or app extension's bundle, such as `com.example.Planner/2.3`.
    ///
    /// - Parameter bundle: The bundle, usually the main one.
    /// - Returns: The bundle id, and its version when the bundle has one, or `nil` for a bundle that isn't an app's
    ///   or an app extension's.
    package static func app(of bundle: Bundle) -> String? {
        guard ["app", "appex"].contains(bundle.bundleURL.pathExtension), let id = bundle.bundleIdentifier else { return nil }
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        return version.map { "\(id)/\($0)" } ?? id
    }

    /// The version of the Swift compiler that built the package, as precisely as the package knows: the newest version
    /// it names, or the oldest it builds with.
    private static var swiftVersion: String {
        #if compiler(>=6.6)
        "6.6"
        #elseif compiler(>=6.5)
        "6.5"
        #else
        "6.4"
        #endif
    }

    /// The operating system's name and version, such as `iOS/27.0.1`.
    private static var system: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if targetEnvironment(macCatalyst)
        return "macCatalyst/\(number)"
        #elseif os(iOS)
        return "iOS/\(number)"
        #elseif os(macOS)
        return "macOS/\(number)"
        #elseif os(visionOS)
        return "visionOS/\(number)"
        #elseif os(watchOS)
        return "watchOS/\(number)"
        #else
        return "unknown/\(number)"
        #endif
    }
}
