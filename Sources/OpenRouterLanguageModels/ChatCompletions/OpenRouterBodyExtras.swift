import Foundation
import LanguageModels

/// OpenRouter's own members of a request's body: the fallback models, the output kinds, the settings only OpenRouter
/// takes, the routing, the plugins, the session id and the cache mark.
struct OpenRouterBodyExtras: Encodable {
    let models: [OpenRouterModelID]?
    let modalities: [OpenRouterOutputModality]?
    let parallelToolCalls: Bool?
    let reasoning: Reasoning?
    let topK: Int?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let repetitionPenalty: Double?
    let minP: Double?
    let topA: Double?
    let stop: [String]?
    let logitBias: LogitBias?
    let verbosity: OpenRouterOptions.Verbosity?
    let serviceTier: OpenRouterServiceTier?
    let user: String?
    let provider: OpenRouterRouting.Member?
    let plugins: [Plugin]
    let sessionID: String?
    let cacheControl: OpenRouterCacheControl.Directive?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ChatCompletions.Member.self)
        try container.encodeIfPresent(models, forKey: .models)
        try container.encodeIfPresent(modalities, forKey: .modalities)
        try container.encodeIfPresent(parallelToolCalls, forKey: .parallelToolCalls)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(topK, forKey: .topK)
        try container.encodeIfPresent(frequencyPenalty, forKey: .frequencyPenalty)
        try container.encodeIfPresent(presencePenalty, forKey: .presencePenalty)
        try container.encodeIfPresent(repetitionPenalty, forKey: .repetitionPenalty)
        try container.encodeIfPresent(minP, forKey: .minP)
        try container.encodeIfPresent(topA, forKey: .topA)
        try container.encodeIfPresent(stop, forKey: .stop)
        try container.encodeIfPresent(logitBias, forKey: .logitBias)
        try container.encodeIfPresent(verbosity, forKey: .verbosity)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encode(plugins, forKey: .plugins)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
    }

    /// The `reasoning` setting: whether to reason at all, for a model whose effort can't be chosen, or the effort.
    enum Reasoning: Encodable {
        case enabled(Bool)
        case effort(String)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .enabled(let isEnabled): try container.encode(isEnabled, forKey: .enabled)
            case .effort(let effort): try container.encode(effort, forKey: .effort)
            }
        }

        private enum Key: String, CodingKey {
            case enabled
            case effort
        }
    }

    /// The logit bias as an object keyed by token id, sorted by key, so it gives the same bytes every time.
    struct LogitBias: Encodable {
        let biases: [Int: Double]

        init(_ biases: [Int: Double]) {
            self.biases = biases
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            for (token, bias) in biases.map({ (String($0.key), $0.value) }).sorted(by: { $0.0 < $1.0 }) {
                try container.encode(bias, forKey: JSONKey(stringValue: token))
            }
        }
    }

    /// One of OpenRouter's plugins for a request.
    enum Plugin: Encodable {
        /// Context compression, always off, so the model sees the whole transcript.
        case contextCompression

        /// The engine that reads PDFs.
        case fileParser(OpenRouterOptions.PDFEngine)

        /// The Auto Router's settings, under the plugin id the router reads.
        case autoRouter(OpenRouterOptions.AutoRouter, plugin: OpenRouterPlugin)

        /// The Pareto router's settings.
        case paretoRouter(OpenRouterOptions.ParetoRouter)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .contextCompression:
                try container.encode(OpenRouterPlugin.contextCompression, forKey: .id)
                try container.encode(false, forKey: .enabled)
            case .fileParser(let engine):
                try container.encode(OpenRouterPlugin.fileParser, forKey: .id)
                var pdf = container.nestedContainer(keyedBy: Key.self, forKey: .pdf)
                try pdf.encode(engine, forKey: .engine)
            case .autoRouter(let settings, let plugin):
                try container.encode(plugin, forKey: .id)
                try container.encodeIfPresent(settings.allowedModels, forKey: .allowedModels)
                try container.encodeIfPresent(settings.excludedModels, forKey: .excludedModels)
                try container.encodeIfPresent(settings.costTier, forKey: .costTier)
            case .paretoRouter(let settings):
                try container.encode(OpenRouterPlugin.paretoRouter, forKey: .id)
                try container.encodeIfPresent(settings.minimumCodingScore, forKey: .minimumCodingScore)
                try container.encodeIfPresent(
                    settings.maximumPromptPrice.map { NSDecimalNumber(decimal: $0).doubleValue }, forKey: .maximumPrice)
                try container.encodeIfPresent(settings.priceSource, forKey: .priceSource)
            }
        }

        private enum Key: String, CodingKey {
            case id
            case enabled
            case pdf
            case engine
            case allowedModels = "allowed_models"
            case excludedModels = "excluded_models"
            case costTier = "cost_tier"
            case minimumCodingScore = "min_coding_score"
            case maximumPrice = "max_price"
            case priceSource = "price_source"
        }
    }
}

extension ChatCompletions.Member {
    static let models: Self = "models"
    static let modalities: Self = "modalities"
    static let parallelToolCalls: Self = "parallel_tool_calls"
    static let reasoning: Self = "reasoning"
    static let topK: Self = "top_k"
    static let frequencyPenalty: Self = "frequency_penalty"
    static let presencePenalty: Self = "presence_penalty"
    static let repetitionPenalty: Self = "repetition_penalty"
    static let minP: Self = "min_p"
    static let topA: Self = "top_a"
    static let stop: Self = "stop"
    static let logitBias: Self = "logit_bias"
    static let verbosity: Self = "verbosity"
    static let serviceTier: Self = "service_tier"
    static let user: Self = "user"
    static let provider: Self = "provider"
    static let plugins: Self = "plugins"
    static let sessionID: Self = "session_id"
    static let cacheControl: Self = "cache_control"

    /// The order OpenRouter's requests have always sent their members in, which a host's prompt cache and OpenRouter's
    /// response cache depend on.
    static let openRouterOrder: [ChatCompletions.Member] = [
        model, models, messages, modalities, stream, tools, toolChoice, parallelToolCalls, responseFormat, reasoning, temperature,
        topP, topK, seed, maxCompletionTokens, maxTokens, frequencyPenalty, presencePenalty, repetitionPenalty, minP, topA, stop,
        logitBias, verbosity, serviceTier, user, provider, plugins, sessionID, metadata, cacheControl,
    ]

    /// The members that go out only when the model and each fallback list them.
    static let openRouterListed: Set<ChatCompletions.Member> = [
        toolChoice, parallelToolCalls, temperature, topP, topK, seed, maxTokens, frequencyPenalty, presencePenalty,
        repetitionPenalty, minP, topA, stop, logitBias, verbosity,
    ]
}
