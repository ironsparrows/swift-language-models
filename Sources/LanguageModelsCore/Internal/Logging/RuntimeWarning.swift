import Foundation
import MachO
import os

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
