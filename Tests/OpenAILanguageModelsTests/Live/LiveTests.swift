import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAILanguageModels
import Testing

/// Requests to real OpenAI models, for what only OpenAI can show: which requests it accepts, what it needs sent back on
/// later turns, how it reports usage and how it fails. A full run costs about two cents.
///
/// The models are the cheapest of each kind: GPT-5 nano, which always reasons, GPT-6 Luna, the cheapest GPT-6 model,
/// which can stop reasoning and reads PDFs, and GPT-4o mini, which doesn't reason.
@diagnose(DeprecatedDeclaration, as: warning)
@Suite(
    "Live: OpenAI",
    .tags(.live),
    .requiresAPIKey("OPENAI_API_KEY"),
    .skipsUnavailableOpenAI,
    .timeLimit(.minutes(2))
)
struct LiveTests {
    /// A response limit for answers of a few words.
    static let short = GenerationOptions(maximumResponseTokens: 64)
}

/// A catalog model under test, with the cheapest reasoning level it takes.
struct LiveModel: Sendable, CustomTestStringConvertible {
    /// The model's id in the catalog. Models OpenAI retires are named by id, so the tests build without deprecation
    /// warnings.
    let id: OpenAIModelID

    /// The level that keeps the model's reasoning cheapest, or `nil` for a model that doesn't reason.
    let quickLevel: ContextOptions.ReasoningLevel?

    /// GPT-5 nano, the cheapest model, which always reasons and takes `minimal` at least.
    static let nano = LiveModel(id: "gpt-5-nano", quickLevel: .minimal)

    /// GPT-6 Luna, the cheapest GPT-6 model, which can stop reasoning and reads PDFs.
    static let luna = LiveModel(id: "gpt-6-luna", quickLevel: .off)

    /// GPT-4o mini, the cheapest model that doesn't reason.
    static let mini = LiveModel(id: "gpt-4o-mini", quickLevel: nil)

    /// GPT-4.1 mini, a model that doesn't reason, from before GPT-5.
    static let gpt41Mini = LiveModel(id: "gpt-4.1-mini", quickLevel: nil)

    /// o3, a model that always reasons, from before GPT-5.
    static let o3 = LiveModel(id: "o3", quickLevel: .light)

    /// GPT-5.4 mini, a model whose reasoning is off unless a request sets an effort, as OpenAI's model page says.
    static let gpt54Mini = LiveModel(id: "gpt-5.4-mini", quickLevel: .off)

    var testDescription: String { id.rawValue }

    /// The model with OpenAI's settings and the running test's API key.
    ///
    /// - Throws: An issue when the catalog doesn't list the model.
    func languageModel(
        options: OpenAIOptions = OpenAIOptions(),
        auth: OpenAIAuthentication? = nil
    ) throws -> OpenAILanguageModel<ContextOptions.ReasoningLevel> {
        let details = try #require(OpenAIModel(catalogID: id), "The catalog no longer lists \(id).")
        // Foundation Models may call the key closure from a task of its own, where the test's key isn't bound.
        let key = APIKeyTrait.current ?? ""
        return OpenAILanguageModel(details, options: options, auth: auth ?? .apiKey { key })
    }

    /// Context options with the model's cheapest reasoning level.
    var quickContext: ContextOptions {
        ContextOptions(reasoningLevel: quickLevel)
    }
}

/// The metadata of an answer's last response entry.
func metadata(of response: LanguageModelSession.Response<some Generable>) -> [String: GeneratedContent] {
    lastAnswer(in: response.transcriptEntries)?.metadata ?? [:]
}

/// Why OpenAI couldn't serve a request right now, when that, rather than the request, made it fail: a rate limit, a
/// timeout, or OpenAI failing or overloaded. A quota that ran out fails the test, since it needs someone to act.
private func isUnavailable(_ error: any Error) -> Bool {
    switch error {
    case let error as LanguageModelError:
        switch error {
        case .rateLimited, .timeout: true
        default: false
        }
    case let error as OpenAIError:
        error.code == .serverError || error.status.map([500, 502, 503, 504].contains) == true
    default:
        false
    }
}

/// A trait that cancels a test when OpenAI couldn't serve it right now, attaching the error, instead of failing it.
struct SkipsUnavailableOpenAI: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    // Testing declares the requirement without nonisolated(nonsending), so both the method and its closure run
    // concurrently.
    @concurrent func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable @concurrent () async throws -> Void
    ) async throws {
        do {
            try await function()
        } catch {
            guard isUnavailable(error) else { throw error }
            Attachment.record(String(reflecting: error), named: "unavailable-error.txt")
            try Test.cancel("OpenAI was briefly unavailable: \(error)")
        }
    }
}

extension Trait where Self == SkipsUnavailableOpenAI {
    /// Cancels a test when OpenAI couldn't serve it right now, instead of failing it.
    static var skipsUnavailableOpenAI: Self { Self() }
}
