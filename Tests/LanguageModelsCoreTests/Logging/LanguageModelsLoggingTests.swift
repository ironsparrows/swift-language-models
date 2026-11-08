import LanguageModelsCore
import Testing
import os

/// The level is shared by the whole process, so these tests run one at a time and restore it.
@Suite("Logging level", .serialized)
struct LanguageModelsLoggingTests {
    @Test func `the package logs every level unless the app sets one`() {
        #expect(LanguageModelsLogging.minimumLevel == .debug)
    }

    @Test(arguments: [
        (OSLogType.debug, [OSLogType.debug, .info, .default, .error, .fault]),
        (.info, [.info, .default, .error, .fault]),
        (.default, [.default, .error, .fault]),
        (.error, [.error, .fault]),
        (.fault, [.fault]),
    ])
    func `a category writes only at the app's level and the more severe ones`(level: OSLogType, written: [OSLogType]) {
        let category = PackageLogger(category: "Tests")
        LanguageModelsLogging.minimumLevel = level
        defer { LanguageModelsLogging.minimumLevel = .debug }

        let levels: [OSLogType] = [.debug, .info, .default, .error, .fault]
        #expect(levels.filter { category($0) != nil } == written)
    }

    @Test func `any task can set and read the level at once`() async {
        defer { LanguageModelsLogging.minimumLevel = .debug }

        await withTaskGroup(of: OSLogType.self) { group in
            for index in 0..<100 {
                group.addTask {
                    LanguageModelsLogging.minimumLevel = index.isMultiple(of: 2) ? .error : .fault
                    return LanguageModelsLogging.minimumLevel
                }
            }
            for await level in group {
                #expect([.error, .fault].contains(level))
            }
        }
    }
}
