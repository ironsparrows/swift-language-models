import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

/// The app name live requests send, so their usage shows apart in OpenRouter's analytics.
let liveAppName = "swift-language-models tests"

/// A catalog model under test, with what the tests need to know about it.
struct LiveModel: Sendable, CustomTestStringConvertible {
    /// The model's details, with its efforts as reasoning levels.
    let details: OpenRouterModel<ContextOptions.ReasoningLevel>

    /// How requests mark prompts for caching.
    let cacheControl: OpenRouterCacheControl?

    /// A level that keeps the model reasoning at little cost.
    let reasoningLevel: ContextOptions.ReasoningLevel

    /// Whether the model's reasoning comes back signed or encrypted, for the host to check when it's replayed.
    let signsReasoning: Bool

    /// The OpenRouter settings the model's requests use, such as a PDF engine.
    let options: OpenRouterOptions

    init(
        _ details: OpenRouterModel<some ModelEffort>,
        cacheControl: OpenRouterCacheControl? = .automatic,
        reasoningLevel: ContextOptions.ReasoningLevel = .light,
        signsReasoning: Bool = false,
        options: OpenRouterOptions = OpenRouterOptions()
    ) {
        self.details = OpenRouterModel(details)
        self.cacheControl = cacheControl
        self.reasoningLevel = reasoningLevel
        self.signsReasoning = signsReasoning
        self.options = options
    }

    var testDescription: String {
        cacheControl == .always ? "\(details.id.rawValue), always marked" : details.id.rawValue
    }

    /// The model, with the running test's API key.
    var languageModel: OpenRouterLanguageModel<ContextOptions.ReasoningLevel> {
        languageModel()
    }

    /// The model with OpenRouter's settings and the running test's API key.
    func languageModel(
        fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>] = [],
        serverTools: [OpenRouterServerTool] = [],
        routing: OpenRouterRouting = OpenRouterRouting(),
        options: OpenRouterOptions? = nil,
        responseCache: OpenRouterResponseCache? = nil
    ) -> OpenRouterLanguageModel<ContextOptions.ReasoningLevel> {
        // Foundation Models may call the key closure from a task of its own, where the test's key isn't bound.
        let key = APIKeyTrait.current ?? ""
        var model = OpenRouterLanguageModel(
            details,
            serverTools: serverTools,
            routing: routing,
            options: options ?? self.options,
            cacheControl: cacheControl,
            responseCache: responseCache,
            app: OpenRouterApp(name: liveAppName),
            auth: .apiKey { key }
        )
        model.fallbacks = fallbacks
        return model
    }
}

/// The reasoning details stored in a reasoning entry's signature, or none when it has no list of them.
func reasoningDetails(of reasoning: Transcript.Reasoning) throws -> [JSONValue] {
    guard let signature = reasoning.signature, case .array(let details) = try JSONValue(json: signature) else { return [] }
    return details
}

/// The answer's metadata and its usage's, for reading what OpenRouter reported.
func answerMetadata(_ response: LanguageModelSession.Response<some Generable>) -> String {
    let answer = lastAnswer(in: response.transcriptEntries)
    return "Answer: \(answer?.metadata ?? [:])\nUsage: \(response.usage)"
}

/// Why no host would serve a request for the account right now, when that, rather than the request, made it fail.
enum HostUnavailability {
    /// A rate limit, a timeout, an unavailable or overloaded host, a gateway status, or no host left that serves the
    /// model.
    case brief

    /// The account's privacy settings exclude every host of the model, such as one that trains on paid prompts.
    case excludedByAccountSettings

    /// The unavailability an error shows, or `nil` when the request itself failed.
    init?(_ error: any Error) {
        switch error {
        case let error as LanguageModelError:
            switch error {
            case .rateLimited, .timeout: self = .brief
            default: return nil
            }
        case let error as OpenRouterError:
            // OpenRouter lists why it excluded each host, such as "Paid model training violation (account settings)".
            if error.status == 404, error.message.localizedCaseInsensitiveContains("(account settings)") {
                self = .excludedByAccountSettings
                return
            }
            let isBrief =
                [OpenRouterError.Code.providerUnavailable, .providerOverloaded].contains(error.code)
                || error.status.map(transientStatuses.contains) == true
                || (error.status == 404 && error.message.localizedCaseInsensitiveContains("no endpoints"))
            guard isBrief else { return nil }
            self = .brief
        default:
            return nil
        }
    }

    /// Why a test that ran into it is cancelled.
    var reason: String {
        switch self {
        case .brief: "The host was briefly unavailable"
        case .excludedByAccountSettings: "The account's privacy settings exclude every host of the model"
        }
    }
}

/// The statuses of a host or gateway that's briefly unavailable or slow.
private let transientStatuses: Set<Int> = [408, 502, 503, 504, 524, 529]

/// A trait that cancels a test when no host would serve it for the account right now, attaching the error, instead of
/// failing it.
struct SkipsUnavailableHosts: TestTrait, SuiteTrait, TestScoping {
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
            guard let unavailability = HostUnavailability(error) else { throw error }
            Attachment.record(String(reflecting: error), named: "unavailable-host-error.txt")
            try Test.cancel("\(unavailability.reason): \(error)")
        }
    }
}

extension Trait where Self == SkipsUnavailableHosts {
    /// Cancels a test when no host would serve it for the account right now, instead of failing it.
    static var skipsUnavailableHosts: Self { Self() }
}
