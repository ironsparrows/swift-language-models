import Foundation

/// One endpoint of a host that serves a model on OpenRouter, with its limits, prices and recent health.
///
/// A host, such as Google Vertex or Amazon Bedrock, can serve a model at several endpoints, such as in different
/// regions or service tiers, so the same host can appear more than once in a model's endpoints. Their ``tag``
/// tells them apart, and ``OpenRouterRouting/order`` takes it to send requests to that endpoint:
///
/// ```swift
/// let endpoints = try await OpenRouterModel.anthropicClaudeHaiku5_5.endpoints()
/// let europe = endpoints.filter { $0.tag.rawValue.hasSuffix("/europe") }.map(\.tag)
/// let routing = OpenRouterRouting(order: europe)
/// let model = OpenRouterLanguageModel(
///     .anthropicClaudeHaiku5_5,
///     routing: routing,
///     auth: .apiKey { try await keyStore.openRouterKey() }
/// )
/// ```
///
/// ``OpenRouterModel/endpoints(auth:session:)`` lists a model's endpoints.
public struct OpenRouterEndpoint: Sendable, Hashable {
    /// The host's name, such as `Google`, to show to people.
    ///
    /// ``OpenRouterRouting/order``, ``OpenRouterRouting/allowedProviders`` and ``OpenRouterRouting/excludedProviders``
    /// take it too, and then mean every endpoint of the host, which is why it shares its type with ``tag``.
    public let name: OpenRouterProviderName

    /// The endpoint's slug, such as `google-vertex/europe`: the host's slug, then the region, precision or tier that
    /// sets the endpoint apart, when the host has several.
    ///
    /// ``OpenRouterRouting/order`` takes it to send requests to this endpoint alone, rather than to any of the host's.
    public let tag: OpenRouterProviderName

    /// The model the endpoint serves.
    public let modelID: OpenRouterModelID

    /// The tier the endpoint sells, such as ``OpenRouterServiceTier/flex`` or ``OpenRouterServiceTier/priority``, or
    /// `nil` for a standard endpoint.
    public let serviceTier: OpenRouterServiceTier?

    /// The precision of the endpoint's model weights, such as `fp8`, or ``OpenRouterQuantization/unknown`` when the
    /// host doesn't say.
    public let quantization: OpenRouterQuantization

    /// The size of the endpoint's context window, in tokens.
    public let contextSize: Int?

    /// The most tokens the endpoint generates in one response. Prompt and output share the context window, so a long
    /// prompt leaves room for fewer.
    public let maximumOutputTokens: Int?

    /// The most prompt tokens the endpoint takes, when it takes fewer than its context size.
    public let maximumPromptTokens: Int?

    /// What the endpoint charges, or `nil` when its price depends on the request.
    public let pricing: OpenRouterPricing?

    /// OpenRouter's health code for the endpoint: 0 while it serves normally, and below 0 while OpenRouter sees it
    /// degraded or down, or `nil` when OpenRouter doesn't report one. OpenRouter doesn't document what each negative
    /// code means.
    public let status: Int?

    /// The share of the last 5 minutes in which the endpoint answered, as a percentage from 0 to 100, or `nil` when it
    /// had too few requests to tell.
    ///
    /// A minute counts as up when at least 80% of its requests succeeded, and only minutes with 10 or more requests
    /// count. Rate limits and requests the caller got wrong don't count as failures.
    public let uptimeLast5Minutes: Double?

    /// The share of the last 30 minutes in which the endpoint answered, as for ``uptimeLast5Minutes``.
    public let uptimeLast30Minutes: Double?

    /// The share of the last day in which the endpoint answered, as for ``uptimeLast5Minutes``.
    public let uptimeLastDay: Double?

    /// How long the endpoint took to its first token over the last 30 minutes, at each percentile: `p90` is the time
    /// that 90% of requests beat.
    ///
    /// OpenRouter reports it only to a call with an API key, so it's `nil` without one.
    public let latencyLast30Minutes: OpenRouterRouting.Percentiles<Duration>?

    /// How fast the endpoint generated over the last 30 minutes, in tokens per second, at each percentile: `p90` is the
    /// speed that 90% of requests reached, so it's lower than `p50`.
    ///
    /// OpenRouter reports it only to a call with an API key, so it's `nil` without one.
    public let throughputLast30Minutes: OpenRouterRouting.Percentiles<Double>?

    /// The request parameters the endpoint accepts, such as `tools` or `seed`.
    public let supportedParameters: Set<OpenRouterParameter>

    /// Whether the endpoint caches prompts by itself, without marks on the request.
    public let supportsImplicitCaching: Bool

    /// Creates an endpoint's details, such as for a preview.
    ///
    /// - Parameters:
    ///   - name: The host's name.
    ///   - tag: The endpoint's slug.
    ///   - modelID: The model the endpoint serves.
    ///   - serviceTier: The tier the endpoint sells, or `nil` for a standard endpoint.
    ///   - quantization: The precision of the endpoint's model weights.
    ///   - contextSize: The size of the endpoint's context window, in tokens.
    ///   - maximumOutputTokens: The most tokens the endpoint generates in one response.
    ///   - maximumPromptTokens: The most prompt tokens the endpoint takes.
    ///   - pricing: What the endpoint charges.
    ///   - status: OpenRouter's health code for the endpoint, 0 while it serves normally.
    ///   - uptimeLast5Minutes: The share of the last 5 minutes in which the endpoint answered, as a percentage.
    ///   - uptimeLast30Minutes: The share of the last 30 minutes in which the endpoint answered, as a percentage.
    ///   - uptimeLastDay: The share of the last day in which the endpoint answered, as a percentage.
    ///   - latencyLast30Minutes: How long the endpoint took to its first token over the last 30 minutes.
    ///   - throughputLast30Minutes: How fast the endpoint generated over the last 30 minutes, in tokens per second.
    ///   - supportedParameters: The request parameters the endpoint accepts.
    ///   - supportsImplicitCaching: Whether the endpoint caches prompts by itself.
    public init(
        name: OpenRouterProviderName,
        tag: OpenRouterProviderName,
        modelID: OpenRouterModelID,
        serviceTier: OpenRouterServiceTier? = nil,
        quantization: OpenRouterQuantization = .unknown,
        contextSize: Int? = nil,
        maximumOutputTokens: Int? = nil,
        maximumPromptTokens: Int? = nil,
        pricing: OpenRouterPricing? = nil,
        status: Int? = 0,
        uptimeLast5Minutes: Double? = nil,
        uptimeLast30Minutes: Double? = nil,
        uptimeLastDay: Double? = nil,
        latencyLast30Minutes: OpenRouterRouting.Percentiles<Duration>? = nil,
        throughputLast30Minutes: OpenRouterRouting.Percentiles<Double>? = nil,
        supportedParameters: Set<OpenRouterParameter> = [],
        supportsImplicitCaching: Bool = false
    ) {
        self.name = name
        self.tag = tag
        self.modelID = modelID
        self.serviceTier = serviceTier
        self.quantization = quantization
        self.contextSize = contextSize
        self.maximumOutputTokens = maximumOutputTokens
        self.maximumPromptTokens = maximumPromptTokens
        self.pricing = pricing
        self.status = status
        self.uptimeLast5Minutes = uptimeLast5Minutes
        self.uptimeLast30Minutes = uptimeLast30Minutes
        self.uptimeLastDay = uptimeLastDay
        self.latencyLast30Minutes = latencyLast30Minutes
        self.throughputLast30Minutes = throughputLast30Minutes
        self.supportedParameters = supportedParameters
        self.supportsImplicitCaching = supportsImplicitCaching
    }
}

extension APITransport {
    /// The endpoints of one model.
    func endpoints(of model: OpenRouterModelID) async throws -> [OpenRouterEndpoint] {
        let endpoints = try await value(at: API.Path.endpoints(of: model), as: APITransport.DataEnvelope<OpenRouterEndpoint.List>.self)
        return endpoints.data.endpoints.map(OpenRouterEndpoint.init)
    }
}

extension OpenRouterEndpoint {
    /// The `data` of `GET /models/{author}/{slug}/endpoints`, reduced to the endpoints.
    struct List: Decodable, Sendable {
        let endpoints: [OpenRouterEndpoint.Payload]
    }
}

extension OpenRouterEndpoint {
    /// An endpoint in `GET /models/{author}/{slug}/endpoints`.
    struct Payload: Decodable, Sendable {
        struct Percentiles: Decodable, Sendable {
            let p50: Double?
            let p75: Double?
            let p90: Double?
            let p99: Double?
        }

        let providerName: String
        let tag: String
        let modelID: String
        let serviceTier: String?
        let quantization: String?
        let contextLength: Int?
        let maxCompletionTokens: Int?
        let maxPromptTokens: Int?
        let pricing: OpenRouterPricing.Payload?
        let status: Int?
        let uptimeLast5m: Double?
        let uptimeLast30m: Double?
        let uptimeLast1d: Double?
        let latencyLast30m: Percentiles?
        let throughputLast30m: Percentiles?
        let supportedParameters: [String]?
        let supportsImplicitCaching: Bool?

        private enum CodingKeys: String, CodingKey {
            case tag, quantization, pricing, status
            case providerName = "provider_name"
            case modelID = "model_id"
            case serviceTier = "service_tier"
            case contextLength = "context_length"
            case maxCompletionTokens = "max_completion_tokens"
            case maxPromptTokens = "max_prompt_tokens"
            case uptimeLast5m = "uptime_last_5m"
            case uptimeLast30m = "uptime_last_30m"
            case uptimeLast1d = "uptime_last_1d"
            case latencyLast30m = "latency_last_30m"
            case throughputLast30m = "throughput_last_30m"
            case supportedParameters = "supported_parameters"
            case supportsImplicitCaching = "supports_implicit_caching"
        }
    }
}

extension OpenRouterEndpoint {
    /// An endpoint from OpenRouter's list, with its latency read in milliseconds.
    init(_ payload: OpenRouterEndpoint.Payload) {
        self.init(
            name: OpenRouterProviderName(rawValue: payload.providerName),
            tag: OpenRouterProviderName(rawValue: payload.tag),
            modelID: OpenRouterModelID(rawValue: payload.modelID),
            serviceTier: payload.serviceTier.map(OpenRouterServiceTier.init(rawValue:)),
            quantization: payload.quantization.map(OpenRouterQuantization.init(rawValue:)) ?? .unknown,
            contextSize: payload.contextLength,
            maximumOutputTokens: payload.maxCompletionTokens,
            maximumPromptTokens: payload.maxPromptTokens,
            pricing: payload.pricing.flatMap(OpenRouterPricing.init),
            status: payload.status,
            uptimeLast5Minutes: payload.uptimeLast5m,
            uptimeLast30Minutes: payload.uptimeLast30m,
            uptimeLastDay: payload.uptimeLast1d,
            latencyLast30Minutes: payload.latencyLast30m.map { $0.percentiles { .milliseconds($0) } },
            throughputLast30Minutes: payload.throughputLast30m.map { $0.percentiles { $0 } },
            supportedParameters: Set((payload.supportedParameters ?? []).map(OpenRouterParameter.init(rawValue:))),
            supportsImplicitCaching: payload.supportsImplicitCaching ?? false
        )
    }
}

extension OpenRouterEndpoint.Payload.Percentiles {
    fileprivate func percentiles<Value>(_ value: (Double) -> Value) -> OpenRouterRouting.Percentiles<Value> {
        OpenRouterRouting.Percentiles(p50: p50.map(value), p75: p75.map(value), p90: p90.map(value), p99: p99.map(value))
    }
}
