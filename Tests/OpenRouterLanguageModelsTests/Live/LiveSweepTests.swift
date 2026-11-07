import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

/// Each vendor's cheapest catalog model through three passes, a tool round trip, guided generation and a reasoning
/// tool loop, to find the models the package doesn't work with yet. It runs only with `LIVE_SWEEP` set, makes about
/// 120 cases for about ten cents, and checks loosely, since it looks for breakage rather than quality.
///
/// The models rank by what OpenRouter charges when the sweep runs, from its public model list. When the list can't be
/// fetched, the sweep is skipped.
///
/// A case that no host would serve for the account right now, whether briefly or because the account's privacy settings
/// exclude every host, is cancelled rather than failed. Every case attaches its transcript, the answer's metadata and
/// any error.
///
/// Set `LIVE_SWEEP_MODELS` to model ids separated by commas, such as `qwen/qwen3.7-flash`, to sweep only those models,
/// without fetching prices.
@diagnose(DeprecatedDeclaration, as: warning)
@Suite(
    "Live sweep: OpenRouter",
    .tags(.liveSweep),
    .requiresAPIKey("OPENROUTER_API_KEY"),
    .enabled(
        if: ProcessInfo.processInfo.environment["LIVE_SWEEP"]?.isEmpty == false,
        "Set LIVE_SWEEP to sweep each vendor's cheapest model"
    ),
    .timeLimit(.minutes(3))
)
struct LiveSweepTests {
    /// What a case checks, which decides the models it can pick.
    enum Pass: Sendable {
        case toolRoundTrip
        case guidedGeneration
        case reasoningToolLoop

        /// Whether the model takes what the pass sends.
        func admits(_ model: OpenRouterModel<ContextOptions.ReasoningLevel>) -> Bool {
            let parameters = model.supportedParameters
            switch self {
            case .toolRoundTrip: return parameters.contains(.tools)
            case .guidedGeneration: return parameters.contains(.structuredOutputs)
            case .reasoningToolLoop: return parameters.contains(.tools) && model.reasoning != .unsupported
            }
        }
    }

    /// Models known to fail a pass, with why. Their cases run in a known issue that may not show on every run, since
    /// it often depends on the host OpenRouter picks.
    static let knownIssues: [Pass: [OpenRouterModelID: String]] = [
        .toolRoundTrip: [
            "fireworks/ember-1": "It sometimes answers without calling the tool it was asked to use.",
            "google/gemma-3-12b-it": "It sometimes calls the tool without arguments, which don't decode without the city.",
            "inception/mercury-2.5": "It sometimes answers without calling the tool it was asked to use.",
            "meta-llama/llama-3.1-8b-instruct": "Only Groq and CoreWeave serve its tools, and Groq rejects the call with tool_use_failed.",
            "nvidia/nemotron-3-nano-30b-a3b": "It sometimes calls the tool without arguments, which don't decode without the city.",
            "rekaai/reka-edge": "Its host sometimes sends the call's arguments with an extra closing brace, which isn't valid JSON.",
        ],
        .reasoningToolLoop: [
            "aion-labs/aion-3.0-mini": "It sometimes calls the tool but leaves the tool's value out of its answer.",
            "moonshotai/kimi-k2.5": "Kimi K2.5 sometimes sends its final answer only as reasoning, with empty content.",
        ],
    ]

    @Test(arguments: try await models(for: .toolRoundTrip))
    func `a tool round trip brings the tool's value into the answer`(model: LiveModel) async throws {
        try await sweep(model, in: .toolRoundTrip, tools: [WeatherTool()]) { session in
            let response = try await session.respond(to: "How warm is it in Lisbon right now? Use the tool.")

            record(answerMetadata(response), named: "metadata.txt")
            Self.expect(response, calledFor: "Lisbon", cities: try session.transcript.weatherCities(), by: model)
        }
    }

    @Test(arguments: try await models(for: .guidedGeneration))
    func `a guided answer decodes`(model: LiveModel) async throws {
        try await sweep(model, in: .guidedGeneration) { session in
            let response = try await session.respond(to: "Plan a short trip to Lisbon.", generating: Trip.self)

            record(answerMetadata(response), named: "metadata.txt")
            record(response.content, named: "trip.txt")
            #expect(response.usage.output.totalTokenCount > 0)
            Self.expectAnsweringModel(of: response, is: model)
        }
    }

    @Test(arguments: try await models(for: .reasoningToolLoop))
    func `reasoning goes back through a tool loop and the next turn`(model: LiveModel) async throws {
        try await sweep(model, in: .reasoningToolLoop, tools: [WeatherTool()]) { session in
            let options = ContextOptions(reasoningLevel: model.reasoningLevel)

            let first = try await session.respond(to: "How warm is it in Lisbon right now? Use the tool.", contextOptions: options)
            record(answerMetadata(first), named: "first-metadata.txt")
            let second = try await session.respond(to: "And in Porto? Use the tool.", contextOptions: options)
            record(answerMetadata(second), named: "second-metadata.txt")

            let cities = try session.transcript.weatherCities()
            Self.expect(first, calledFor: "Lisbon", cities: cities, by: model)
            Self.expect(second, calledFor: "Porto", cities: cities, by: model)
        }
    }

    /// Runs one case in a new session, attaching the transcript and any error. A case that no host would serve for
    /// the account right now is cancelled, and a case of a model known to fail the pass runs in a known issue.
    private func sweep(
        _ model: LiveModel,
        in pass: Pass,
        tools: [any Tool] = [],
        _ body: (LanguageModelSession) async throws -> Void
    ) async throws {
        let session = LanguageModelSession(model: model.languageModel, tools: tools)
        defer { record(session.transcript, named: "transcript.txt") }
        var unavailability: (HostUnavailability, any Error)?
        func attempt() async throws {
            do {
                try await body(session)
            } catch {
                record(error, named: "error.txt")
                guard let cause = HostUnavailability(error) else { throw error }
                unavailability = (cause, error)
            }
        }

        if let reason = Self.knownIssues[pass]?[model.details.id] {
            await withKnownIssue(Comment(rawValue: reason), isIntermittent: true) {
                try await attempt()
            }
        } else {
            try await attempt()
        }
        if case (let cause, let error)? = unavailability {
            try Test.cancel("\(cause.reason): \(error)")
        }
    }

    /// The loose checks of a turn that should call the weather tool for a city and answer with its value.
    private static func expect(
        _ response: LanguageModelSession.Response<String>,
        calledFor city: String,
        cities: [String],
        by model: LiveModel
    ) {
        #expect(cities.contains { $0.localizedCaseInsensitiveContains(city) }, "No call for \(city): \(cities)")
        #expect(response.content.contains("17"))
        #expect(response.usage.output.totalTokenCount > 0)
        expectAnsweringModel(of: response, is: model)
    }

    /// Checks that the answer names the model, as its id or a dated version of it.
    private static func expectAnsweringModel(of response: LanguageModelSession.Response<some Generable>, is model: LiveModel) {
        let answering = lastAnswer(in: response.transcriptEntries).flatMap { $0.openRouter.model?.rawValue }
        #expect(answering?.hasPrefix(model.details.id.rawValue) == true, "Answered by \(answering ?? "an unnamed model")")
    }
}

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveSweepTests {
    /// Each vendor's cheapest model that the pass admits, sorted by id.
    ///
    /// Routers, aliases, free variants and Perplexity's models are left out, which leaves models whose price is what
    /// their tokens cost. So are models without text output, models past their expiration date, and models whose
    /// prices are missing or zero, which a ranking by price can't place. A model ranks by what a case roughly takes at
    /// OpenRouter's prices now: 500 prompt tokens and 80 completion tokens, and 800 more completion tokens of reasoning
    /// when the model always reasons or the pass asks for reasoning.
    ///
    /// - Throws: A cancellation that skips the test when OpenRouter's prices can't be fetched.
    static func models(for pass: Pass) async throws -> [LiveModel] {
        let candidates = OpenRouterModel.catalogModels.filter { isSweepable($0) && pass.admits($0) }
        let swept: [OpenRouterModel<ContextOptions.ReasoningLevel>]
        if let chosenIDs {
            swept = candidates.filter { chosenIDs.contains($0.id.rawValue) }
        } else {
            let prices: [OpenRouterModelID: OpenRouterPricing]
            do {
                prices = try await LivePrices.all
            } catch {
                try Test.cancel("OpenRouter's prices, which rank the models, couldn't be fetched: \(error)")
            }
            var cheapest: [Substring: (price: Decimal, model: OpenRouterModel<ContextOptions.ReasoningLevel>)] = [:]
            for model in candidates {
                guard let pricing = prices[model.id], let price = price(of: model, in: pass, at: pricing) else { continue }
                let vendor = model.id.rawValue.prefix { $0 != "/" }
                if let current = cheapest[vendor], current.price <= price { continue }
                cheapest[vendor] = (price, model)
            }
            swept = cheapest.values.map(\.model)
        }
        return swept.sorted { $0.id.rawValue < $1.id.rawValue }.map { model in
            LiveModel(model, reasoningLevel: reasoningLevel(for: model))
        }
    }

    /// The ids in `LIVE_SWEEP_MODELS`, or `nil` when it isn't set.
    private static var chosenIDs: Set<String>? {
        guard let list = ProcessInfo.processInfo.environment["LIVE_SWEEP_MODELS"], !list.isEmpty else { return nil }
        return Set(list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private static func isSweepable(_ model: OpenRouterModel<ContextOptions.ReasoningLevel>) -> Bool {
        let id = model.id.rawValue
        let isLeftOut = id.hasPrefix("openrouter/") || id.hasPrefix("~") || id.hasSuffix(":free") || id.hasPrefix("perplexity/")
        let hasExpired = model.expirationDate.map { $0 <= .now } ?? false
        return !isLeftOut && !hasExpired && model.outputModalities.contains(.text)
    }

    /// What a case roughly costs at the given prices, or `nil` when they're zero.
    private static func price(
        of model: OpenRouterModel<ContextOptions.ReasoningLevel>,
        in pass: Pass,
        at pricing: OpenRouterPricing
    ) -> Decimal? {
        guard pricing.prompt > 0 || pricing.completion > 0 else { return nil }
        let reasons = model.reasoning == .mandatory || pass == .reasoningToolLoop
        return pricing.prompt * 500 + pricing.completion * (reasons ? 880 : 80)
    }

    /// The lowest effort that still reasons, for a model that takes efforts, and otherwise `.light`, which turns
    /// reasoning on.
    private static func reasoningLevel(for model: OpenRouterModel<ContextOptions.ReasoningLevel>) -> ContextOptions.ReasoningLevel {
        let lowestFirst: [ContextOptions.ReasoningLevel] = [.low, .medium, .minimal, .high, .xhigh, .max]
        return lowestFirst.first { model.reasoningEfforts.contains($0) } ?? .light
    }
}
