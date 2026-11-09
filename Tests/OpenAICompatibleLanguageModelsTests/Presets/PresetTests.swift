import OpenAICompatibleLanguageModels
import Testing

/// What each preset does differently from a provider the app describes itself: its defaults, the members its requests
/// carry and leave out, the requests it refuses before they're sent, the reasoning that goes back, and what its
/// failures become. Streams and errors are the provider's own, ids and signatures swapped, where one was captured, and
/// written from its docs, issues and SDKs otherwise, which the tests say.
@Suite("Presets", .timeLimit(.minutes(1)))
struct PresetTests {}

extension PresetTests {
    /// A failed response a provider sent, and the module's error it becomes.
    struct Rejection: Sendable, CustomTestStringConvertible {
        let name: String
        let status: Int
        var headers = ["Content-Type": "application/json"]
        let body: String
        let error: OpenAICompatibleError

        var testDescription: String { name }
    }
}
