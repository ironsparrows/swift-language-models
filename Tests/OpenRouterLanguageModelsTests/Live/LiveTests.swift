import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

/// Requests to real models through OpenRouter, for what only a host can show: which schemas it accepts, how it
/// caches, what it needs replayed and how it fails. A full run costs about three cents.
///
/// The executor risks suite probes the ways the executor may break on some models, each named after its risk. A probe
/// that fails today runs in a known issue, so it reports once the risk is fixed; the others guard what works, whether
/// the executor or OpenRouter handles it.
@diagnose(DeprecatedDeclaration, as: warning)
@Suite(
    "Live: OpenRouter",
    .tags(.live),
    .requiresAPIKey("OPENROUTER_API_KEY"),
    .skipsUnavailableHosts,
    .timeLimit(.minutes(2))
)
struct LiveTests {
    /// A response limit for answers of a few words.
    static let short = GenerationOptions(maximumResponseTokens: 16)

    /// Mistral's own host, which takes only 9-character tool-call ids. It charges a regional surcharge, so OpenRouter's
    /// default routing skips it for a model that other hosts serve, unless a request pins its regional slug.
    static let mistralHost = OpenRouterRouting(order: ["mistral/eu"], fallbackProviders: .disallowed)
}
