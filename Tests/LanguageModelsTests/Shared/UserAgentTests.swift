import Foundation
import LanguageModels
import Testing

@Suite("User-Agent")
struct UserAgentTests {
    @Test(arguments: [
        ("com.example.Planner/2.3", "iOS/27.0.1", "swift-language-models (com.example.Planner/2.3; Swift/6.4; iOS/27.0.1)"),
        (nil, "macOS/27.2.0", "swift-language-models (Swift/6.4; macOS/27.2.0)"),
    ])
    func `the package leads, then the app when there's one, Swift and the operating system`(
        app: String?,
        system: String,
        value: String
    ) {
        #expect(UserAgent.value(app: app, swiftVersion: "6.4", system: system) == value)
    }

    @Test func `this process names the package, Swift and macOS, and no app, since tests run outside one`() {
        let pattern = /swift-language-models \(Swift\/\d+\.\d+; macOS\/\d+\.\d+\.\d+\)/

        #expect(UserAgent.current.wholeMatch(of: pattern) != nil)
    }

    @Test(arguments: [
        ("Planner.app", ["CFBundleIdentifier": "com.example.Planner", "CFBundleShortVersionString": "2.3"], "com.example.Planner/2.3"),
        ("Widget.appex", ["CFBundleIdentifier": "com.example.Planner.Widget"], "com.example.Planner.Widget"),
        ("Planner.framework", ["CFBundleIdentifier": "com.example.PlannerKit", "CFBundleShortVersionString": "1.0"], nil),
    ])
    func `an app or app extension names its bundle id and version, and any other bundle nothing`(
        name: String,
        info: [String: String],
        app: String?
    ) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: name)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let contents = url.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))
        let bundle = try #require(Bundle(url: url))

        #expect(UserAgent.app(of: bundle) == app)
    }
}
