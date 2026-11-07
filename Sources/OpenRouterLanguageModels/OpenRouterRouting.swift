public import Foundation
public import LanguageModels

// MARK: - Routing

/// Which of a model's hosts OpenRouter may send requests to, and in what order.
///
/// OpenRouter calls the hosts that serve a model its providers, such as the model's maker or Amazon Bedrock, so the
/// settings that name hosts, such as ``allowedProviders``, keep OpenRouter's word, as does the request's `provider`
/// object that the routing becomes.
///
/// Every setting left `nil` keeps OpenRouter's default. Setting an `order` turns off OpenRouter's sticky routing, so
/// requests of one session may reach a host that hasn't cached their prompt.
public struct OpenRouterRouting: Sendable, Hashable {
    /// Whether hosts may store prompts and train on them, as OpenRouter's `data_collection` spells it.
    public struct DataCollection: ProviderVocabulary {
        /// Any host, including those that store prompts and may train on them. OpenRouter's default.
        public static let allow: Self = "allow"

        /// Only hosts that don't collect prompts.
        public static let deny: Self = "deny"

        /// The setting as OpenRouter's `data_collection` spells it.
        public let rawValue: String

        /// Creates a setting from OpenRouter's spelling of it.
        ///
        /// - Parameter rawValue: The `data_collection` value, such as `"deny"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Whether `sort` ranks each model's hosts on their own or the hosts of every model together, for a request
    /// that can fall back to other models, as a router's requests and those of a model with
    /// ``OpenRouterLanguageModel/fallbacks`` do.
    public struct SortPartition: ProviderVocabulary {
        /// Each model's hosts are ranked on their own, so a fallback model's hosts come after those of the model
        /// picked first. OpenRouter's default.
        public static let byModel: Self = "model"

        /// The hosts of every model are ranked together, so a fallback model's host comes first when it ranks higher.
        public static let acrossModels: Self = "none"

        /// The partition as OpenRouter's `sort.partition` spells it.
        public let rawValue: String

        /// Creates a partition from OpenRouter's spelling of it.
        ///
        /// - Parameter rawValue: The `sort.partition` value, such as `"none"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Whether OpenRouter may do something for a request, or does what it does by default.
    public enum Permission: Sendable, Hashable {
        /// OpenRouter's default, with the setting left out of the request.
        case automatic

        /// OpenRouter may.
        case allowed

        /// OpenRouter may not.
        case disallowed

        /// The setting's value in the request, or `nil` to leave it out.
        fileprivate var value: Bool? {
            switch self {
            case .automatic: nil
            case .allowed: true
            case .disallowed: false
            }
        }
    }

    /// Whether a request uses only hosts or models that meet a condition, or keeps OpenRouter's default.
    public enum Requirement: Sendable, Hashable {
        /// OpenRouter's default, with the setting left out of the request.
        case automatic

        /// Only hosts or models that meet the condition.
        case required

        /// Hosts or models whether or not they meet it.
        case notRequired

        /// The setting's value in the request, or `nil` to leave it out.
        fileprivate var value: Bool? {
            switch self {
            case .automatic: nil
            case .required: true
            case .notRequired: false
            }
        }
    }

    /// A suffix on the model id that changes how OpenRouter routes the request, such as `nitro`.
    ///
    /// ``nitro`` and ``floor`` rank the model's hosts and let the hosts of a service tier compete. A host of the tier
    /// serves the request only when it wins the ranking, and the request is billed at the rate of the tier that serves
    /// it, which can differ from the model's own price. Any other variant OpenRouter offers is valid too, written as
    /// its suffix without the colon.
    public struct Variant: ProviderVocabulary {
        /// `:nitro`, which ranks hosts by throughput and lets priority tiers compete. A priority host bills more.
        public static let nitro: Self = "nitro"

        /// `:floor`, which ranks hosts by price and lets flex tiers compete. A flex host bills less.
        public static let floor: Self = "floor"

        /// The suffix without its colon, as OpenRouter's model ids spell it.
        public let rawValue: String

        /// Creates a variant from its suffix.
        ///
        /// - Parameter rawValue: The suffix without its colon, such as `"nitro"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// The most to pay for a request, in US dollars.
    ///
    /// A host that charges more for any price that's set isn't used, and the request fails when no host qualifies.
    public struct MaximumPrice: Sendable, Hashable {
        /// The most to pay per million prompt tokens.
        public var prompt: Decimal?

        /// The most to pay per million generated tokens.
        public var completion: Decimal?

        /// The most to pay per image.
        public var image: Decimal?

        /// The most to pay per unit of audio.
        public var audio: Decimal?

        /// The most to pay per request, for hosts that charge by the request.
        public var request: Decimal?

        /// Creates price limits.
        ///
        /// - Parameters:
        ///   - prompt: The most to pay per million prompt tokens.
        ///   - completion: The most to pay per million generated tokens.
        ///   - image: The most to pay per image.
        ///   - audio: The most to pay per unit of audio.
        ///   - request: The most to pay per request.
        public init(
            prompt: Decimal? = nil,
            completion: Decimal? = nil,
            image: Decimal? = nil,
            audio: Decimal? = nil,
            request: Decimal? = nil
        ) {
            self.prompt = prompt
            self.completion = completion
            self.image = image
            self.audio = audio
            self.request = request
        }
    }

    /// Thresholds on a host's recent performance, each met by a share of its requests, such as the median, `p50`.
    ///
    /// As a routing preference, a host is preferred only when it meets every threshold that's set. One that misses them
    /// is tried later but can still serve the request. Setting only `p50` is the same as OpenRouter's single-number
    /// form. An ``OpenRouterEndpoint`` reports its measured performance in the same form.
    public struct Percentiles<Value: Sendable & Hashable>: Sendable, Hashable {
        /// The threshold that half of the host's requests meet.
        public var p50: Value?

        /// The threshold that three quarters of the host's requests meet.
        public var p75: Value?

        /// The threshold that 90% of the host's requests meet.
        public var p90: Value?

        /// The threshold that 99% of the host's requests meet.
        public var p99: Value?

        /// Creates thresholds.
        ///
        /// - Parameters:
        ///   - p50: The threshold that half of the host's requests meet.
        ///   - p75: The threshold that three quarters of the host's requests meet.
        ///   - p90: The threshold that 90% of the host's requests meet.
        ///   - p99: The threshold that 99% of the host's requests meet.
        public init(p50: Value? = nil, p75: Value? = nil, p90: Value? = nil, p99: Value? = nil) {
            self.p50 = p50
            self.p75 = p75
            self.p90 = p90
            self.p99 = p99
        }
    }

    /// The hosts to try first, in order, by name or slug, such as `"Anthropic"` or `"amazon-bedrock"`.
    public var order: [OpenRouterProviderName]?

    /// The only hosts to use.
    public var allowedProviders: [OpenRouterProviderName]?

    /// Hosts never to use.
    public var excludedProviders: [OpenRouterProviderName]?

    /// Whether to fall back to other hosts when the chosen ones are unavailable.
    public var fallbackProviders: Permission

    /// Whether to use only hosts that support every parameter a request sends.
    ///
    /// With ``Requirement/automatic``, requests with tools, server tools or a response schema require it, so a host
    /// that would ignore the tools or the schema isn't used.
    public var parameterSupport: Requirement

    /// Whether hosts may store prompts and train on them.
    public var dataCollection: DataCollection?

    /// Whether to use only hosts that retain no prompts.
    public var zeroDataRetention: Requirement

    /// Whether to use only models whose authors allow training other models on their output.
    public var distillableText: Requirement

    /// How to rank hosts when no `order` is set.
    public var sort: OpenRouterRouting.Sort?

    /// Whether `sort` ranks each model's hosts on their own or the hosts of every model together.
    public var sortPartition: SortPartition?

    /// The model weight precisions to allow, such as `fp8`.
    public var quantizations: [OpenRouterQuantization]?

    /// The most to pay for a request. Unlike the preferred throughput and latency, it fails a request that no host
    /// can serve within it.
    public var maximumPrice: MaximumPrice?

    /// The throughput, in tokens per second, at or above which a host is preferred.
    public var preferredMinimumThroughput: Percentiles<Double>?

    /// The latency at or below which a host is preferred.
    public var preferredMaximumLatency: Percentiles<Duration>?

    /// A suffix on the model id, such as `:nitro` or `:floor`, that ranks the model's hosts and lets a service tier
    /// compete.
    ///
    /// The request names the model with the suffix, and each of its ``OpenRouterLanguageModel/fallbacks`` too, since
    /// the routing applies to whichever model answers. The models' details, such as their context sizes and
    /// parameters, stay those of the catalog models. `nitro` and `floor` can change what a request costs. An `order`
    /// replaces the ranking and keeps the tier's hosts out, and a ``OpenRouterOptions/serviceTier`` of
    /// ``OpenRouterServiceTier/default`` keeps the ranking but keeps the tier's hosts out.
    public var variant: Variant?

    /// Creates routing preferences.
    ///
    /// - Parameters:
    ///   - order: The hosts to try first, in order.
    ///   - allowedProviders: The only hosts to use.
    ///   - excludedProviders: Hosts never to use.
    ///   - fallbackProviders: Whether to fall back to other hosts when the chosen ones are unavailable.
    ///   - parameterSupport: Whether to use only hosts that support every parameter a request sends.
    ///   - dataCollection: Whether hosts may store prompts and train on them.
    ///   - zeroDataRetention: Whether to use only hosts that retain no prompts.
    ///   - distillableText: Whether to use only models whose authors allow training other models on their output.
    ///   - sort: How to rank hosts when no `order` is set.
    ///   - sortPartition: Whether `sort` ranks each model's hosts on their own or the hosts of every model together.
    ///   - quantizations: The model weight precisions to allow.
    ///   - maximumPrice: The most to pay for a request.
    ///   - preferredMinimumThroughput: The throughput, in tokens per second, at or above which a host is preferred.
    ///   - preferredMaximumLatency: The latency at or below which a host is preferred.
    ///   - variant: A suffix on the model id that ranks the model's hosts and lets a service tier compete.
    public init(
        order: [OpenRouterProviderName]? = nil,
        allowedProviders: [OpenRouterProviderName]? = nil,
        excludedProviders: [OpenRouterProviderName]? = nil,
        fallbackProviders: Permission = .automatic,
        parameterSupport: Requirement = .automatic,
        dataCollection: DataCollection? = nil,
        zeroDataRetention: Requirement = .automatic,
        distillableText: Requirement = .automatic,
        sort: OpenRouterRouting.Sort? = nil,
        sortPartition: SortPartition? = nil,
        quantizations: [OpenRouterQuantization]? = nil,
        maximumPrice: MaximumPrice? = nil,
        preferredMinimumThroughput: Percentiles<Double>? = nil,
        preferredMaximumLatency: Percentiles<Duration>? = nil,
        variant: Variant? = nil
    ) {
        self.order = order
        self.allowedProviders = allowedProviders
        self.excludedProviders = excludedProviders
        self.fallbackProviders = fallbackProviders
        self.parameterSupport = parameterSupport
        self.dataCollection = dataCollection
        self.zeroDataRetention = zeroDataRetention
        self.distillableText = distillableText
        self.sort = sort
        self.sortPartition = sortPartition
        self.quantizations = quantizations
        self.maximumPrice = maximumPrice
        self.preferredMinimumThroughput = preferredMinimumThroughput
        self.preferredMaximumLatency = preferredMaximumLatency
        self.variant = variant
    }

    /// The model id a request names for the model or one of its fallbacks: the catalog model's id, with the variant's
    /// suffix when one is set.
    func modelID(for id: OpenRouterModelID) -> OpenRouterModelID {
        guard let variant else { return id }
        return OpenRouterModelID(rawValue: "\(id.rawValue):\(variant.rawValue)")
    }
}

extension OpenRouterRouting {
    /// How OpenRouter ranks a model's hosts.
    public struct Sort: ProviderVocabulary {
        /// The lowest price first.
        public static let price: Self = "price"

        /// The highest throughput first.
        public static let throughput: Self = "throughput"

        /// The lowest latency first.
        public static let latency: Self = "latency"

        /// The hosts whose tool calls OpenRouter measures as most accurate first.
        public static let exacto: Self = "exacto"

        /// The ranking's name in OpenRouter's API.
        public let rawValue: String

        /// Creates a ranking from its name in OpenRouter's API.
        ///
        /// - Parameter rawValue: The name, such as `"price"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

// MARK: - Wire

extension OpenRouterRouting {
    /// The `provider` object of OpenRouter's request.
    ///
    /// - Parameter needsParameters: Whether the request needs its parameters honored when the routing doesn't say.
    /// - Returns: The object, or `nil` when every setting keeps OpenRouter's default.
    func member(needsParameters: Bool) -> Member? {
        let parameterSupport = self.parameterSupport == .automatic && needsParameters ? .required : self.parameterSupport
        let member = Member(routing: self, parameterSupport: parameterSupport)
        return member.isEmpty ? nil : member
    }

    /// The `provider` object of OpenRouter's request: each setting that doesn't keep OpenRouter's default, in the
    /// order OpenRouter's requests have always sent them.
    struct Member: Encodable {
        fileprivate let routing: OpenRouterRouting

        /// Whether hosts must take every parameter the request sends, after the request's own needs.
        fileprivate let parameterSupport: Requirement

        private var sort: SortMember? { SortMember(sort: routing.sort, partition: routing.sortPartition) }
        private var maximumPrice: Prices? { routing.maximumPrice.flatMap(Prices.init) }
        private var minimumThroughput: Thresholds? { routing.preferredMinimumThroughput.flatMap { Thresholds($0) { $0 } } }
        private var maximumLatency: Thresholds? { routing.preferredMaximumLatency.flatMap { Thresholds($0) { $0 / .seconds(1) } } }

        /// Whether every setting keeps OpenRouter's default, so the object would be empty.
        fileprivate var isEmpty: Bool {
            routing.order == nil && routing.allowedProviders == nil && routing.excludedProviders == nil
                && routing.fallbackProviders.value == nil && parameterSupport.value == nil && routing.dataCollection == nil
                && routing.zeroDataRetention.value == nil && routing.distillableText.value == nil && sort == nil
                && routing.quantizations == nil && maximumPrice == nil && minimumThroughput == nil && maximumLatency == nil
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encodeIfPresent(routing.order, forKey: .order)
            try container.encodeIfPresent(routing.allowedProviders, forKey: .only)
            try container.encodeIfPresent(routing.excludedProviders, forKey: .ignore)
            try container.encodeIfPresent(routing.fallbackProviders.value, forKey: .allowFallbacks)
            try container.encodeIfPresent(parameterSupport.value, forKey: .requireParameters)
            try container.encodeIfPresent(routing.dataCollection, forKey: .dataCollection)
            try container.encodeIfPresent(routing.zeroDataRetention.value, forKey: .zeroDataRetention)
            try container.encodeIfPresent(routing.distillableText.value, forKey: .distillableText)
            try container.encodeIfPresent(sort, forKey: .sort)
            try container.encodeIfPresent(routing.quantizations, forKey: .quantizations)
            try container.encodeIfPresent(maximumPrice, forKey: .maximumPrice)
            try container.encodeIfPresent(minimumThroughput, forKey: .minimumThroughput)
            try container.encodeIfPresent(maximumLatency, forKey: .maximumLatency)
        }

        private enum Key: String, CodingKey {
            case order
            case only
            case ignore
            case allowFallbacks = "allow_fallbacks"
            case requireParameters = "require_parameters"
            case dataCollection = "data_collection"
            case zeroDataRetention = "zdr"
            case distillableText = "enforce_distillable_text"
            case sort
            case quantizations
            case maximumPrice = "max_price"
            case minimumThroughput = "preferred_min_throughput"
            case maximumLatency = "preferred_max_latency"
        }
    }

    /// The ranking's name, or an object with the ranking and its partition when a partition is set.
    private struct SortMember: Encodable {
        let sort: Sort?
        let partition: SortPartition?

        init?(sort: Sort?, partition: SortPartition?) {
            guard sort != nil || partition != nil else { return nil }
            self.sort = sort
            self.partition = partition
        }

        func encode(to encoder: any Encoder) throws {
            guard let partition else {
                var container = encoder.singleValueContainer()
                try container.encode(sort)
                return
            }
            var container = encoder.container(keyedBy: Key.self)
            try container.encodeIfPresent(sort, forKey: .by)
            try container.encode(partition, forKey: .partition)
        }

        private enum Key: String, CodingKey {
            case by
            case partition
        }
    }

    /// The `max_price` object, each price as a decimal string so it's sent exactly.
    private struct Prices: Encodable {
        let price: MaximumPrice

        /// The prices, or `nil` when none is set.
        init?(_ price: MaximumPrice) {
            guard [price.prompt, price.completion, price.image, price.audio, price.request].contains(where: { $0 != nil }) else {
                return nil
            }
            self.price = price
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encodeIfPresent(price.prompt?.description, forKey: .prompt)
            try container.encodeIfPresent(price.completion?.description, forKey: .completion)
            try container.encodeIfPresent(price.image?.description, forKey: .image)
            try container.encodeIfPresent(price.audio?.description, forKey: .audio)
            try container.encodeIfPresent(price.request?.description, forKey: .request)
        }

        private enum Key: String, CodingKey {
            case prompt
            case completion
            case image
            case audio
            case request
        }
    }

    /// Thresholds as one number when only `p50` is set, otherwise as an object.
    private struct Thresholds: Encodable {
        let p50: Double?
        let p75: Double?
        let p90: Double?
        let p99: Double?

        /// The thresholds as numbers, or `nil` when none is set.
        init?<Value>(_ percentiles: Percentiles<Value>, number: (Value) -> Double) {
            p50 = percentiles.p50.map(number)
            p75 = percentiles.p75.map(number)
            p90 = percentiles.p90.map(number)
            p99 = percentiles.p99.map(number)
            guard p50 != nil || p75 != nil || p90 != nil || p99 != nil else { return nil }
        }

        func encode(to encoder: any Encoder) throws {
            if p75 == nil, p90 == nil, p99 == nil {
                var container = encoder.singleValueContainer()
                try container.encode(p50)
                return
            }
            var container = encoder.container(keyedBy: Key.self)
            try container.encodeIfPresent(p50, forKey: .p50)
            try container.encodeIfPresent(p75, forKey: .p75)
            try container.encodeIfPresent(p90, forKey: .p90)
            try container.encodeIfPresent(p99, forKey: .p99)
        }

        private enum Key: String, CodingKey {
            case p50
            case p75
            case p90
            case p99
        }
    }
}
