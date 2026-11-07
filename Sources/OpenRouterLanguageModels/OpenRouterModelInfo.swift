public import Foundation
import LanguageModels

// MARK: - Calls

extension OpenRouterLanguageModel {
    /// The endpoints of the model's ``details``, as ``OpenRouterModel/endpoints(auth:session:configuration:)`` lists
    /// them, with the model's authentication, session and ``configuration``.
    ///
    /// With an API key, OpenRouter reports each endpoint's latency and throughput too.
    ///
    /// - Returns: The endpoints, in OpenRouter's order.
    /// - Throws: What ``OpenRouterModel/endpoints(auth:session:configuration:)`` throws.
    public func endpoints() async throws -> [OpenRouterEndpoint] {
        try await connection(configuration).endpoints(of: details.id, for: configuration.infoCacheLifetime)
    }

    /// What OpenRouter lists for the model's ``details`` now, as
    /// ``OpenRouterModel/currentDetails(auth:session:configuration:)`` reads it, with the model's authentication,
    /// session and ``configuration``.
    ///
    /// - Returns: The model's current details.
    /// - Throws: What ``OpenRouterModel/currentDetails(auth:session:configuration:)`` throws.
    public func currentDetails() async throws -> OpenRouterCurrentDetails {
        try await connection(configuration).currentDetails(of: details.id, for: configuration.infoCacheLifetime)
    }

    /// What OpenRouter charges for the model's ``details`` now, with the model's authentication, session and
    /// ``configuration``.
    ///
    /// - Returns: The prices, or `nil` when the price depends on the request, as for a router.
    /// - Throws: What ``currentDetails()`` throws.
    public func currentPricing() async throws -> OpenRouterPricing? {
        try await currentDetails().pricing
    }
}

extension OpenRouterModel {
    /// The model's endpoints: each host that serves it, once for each region, tier or precision it serves the model at,
    /// with its limits, prices and recent health.
    ///
    /// ```swift
    /// let endpoints = try await OpenRouterModel.anthropicClaudeHaiku5_5.endpoints()
    /// let healthy = endpoints.filter { ($0.uptimeLast30Minutes ?? 0) > 99 }.map(\.tag)
    /// ```
    ///
    /// The call needs no key, but OpenRouter reports each endpoint's latency and throughput only to a call with one.
    /// Answers from the last minute are reused, so calling this often, such as from a list, doesn't fetch them again,
    /// and a failed call is retried up to twice. To retry or reuse answers differently, pass a configuration of the
    /// call's own:
    ///
    /// ```swift
    /// // Health kept for 10 seconds, without retries.
    /// let configuration = OpenRouterConfiguration(retries: .disabled, infoCacheLifetime: .seconds(10))
    /// let endpoints = try await OpenRouterModel.anthropicClaudeHaiku5_5.endpoints(configuration: configuration)
    /// ```
    ///
    /// - Parameters:
    ///   - auth: How the call authenticates, and where it goes, or `nil` to call OpenRouter without a key.
    ///   - session: The URL session that sends the request.
    ///   - configuration: How the call retries and reuses earlier answers.
    /// - Returns: The endpoints, in OpenRouter's order; none for an alias, such as `~anthropic/claude-haiku-latest`,
    ///   whose endpoints are those of the model it points to.
    /// - Throws: `OpenRouterError` with `notFound` for a model OpenRouter doesn't list, any error the authentication
    ///   throws, and otherwise what a session's request throws when OpenRouter can't be reached or fails.
    public func endpoints(
        auth: OpenRouterAuthentication? = nil,
        session: URLSession = .shared,
        configuration: OpenRouterConfiguration = OpenRouterConfiguration()
    ) async throws -> [OpenRouterEndpoint] {
        let connection = Connection(auth: auth, session: session, configuration: configuration)
        return try await connection.endpoints(of: id, for: configuration.infoCacheLifetime)
    }

    /// What OpenRouter lists for the model now: its prices, limits and parameters.
    ///
    /// The catalog keeps no prices, since OpenRouter changes them often, so this is where they come from. Answers from
    /// the last minute are reused. To retry or reuse answers differently, pass a configuration of the call's own.
    ///
    /// - Parameters:
    ///   - auth: How the call authenticates, and where it goes, or `nil` to call OpenRouter without a key.
    ///   - session: The URL session that sends the request.
    ///   - configuration: How the call retries and reuses earlier answers.
    /// - Returns: The model's current details.
    /// - Throws: `OpenRouterError` with `notFound` for a model OpenRouter doesn't list, any error the authentication
    ///   throws, and otherwise what a session's request throws when OpenRouter can't be reached or fails.
    public func currentDetails(
        auth: OpenRouterAuthentication? = nil,
        session: URLSession = .shared,
        configuration: OpenRouterConfiguration = OpenRouterConfiguration()
    ) async throws -> OpenRouterCurrentDetails {
        let connection = Connection(auth: auth, session: session, configuration: configuration)
        return try await connection.currentDetails(of: id, for: configuration.infoCacheLifetime)
    }

    /// What OpenRouter charges for the model now, from ``currentDetails(auth:session:configuration:)``.
    ///
    /// ```swift
    /// if let pricing = try await OpenRouterModel.anthropicClaudeHaiku5_5.currentPricing() {
    ///     let estimate = pricing.prices(forPromptTokens: 2_000).prompt * 2_000
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - auth: How the call authenticates, and where it goes, or `nil` to call OpenRouter without a key.
    ///   - session: The URL session that sends the request.
    ///   - configuration: How the call retries and reuses earlier answers.
    /// - Returns: The prices, or `nil` when the price depends on the request, as for a router.
    /// - Throws: What ``currentDetails(auth:session:configuration:)`` throws.
    public func currentPricing(
        auth: OpenRouterAuthentication? = nil,
        session: URLSession = .shared,
        configuration: OpenRouterConfiguration = OpenRouterConfiguration()
    ) async throws -> OpenRouterPricing? {
        try await currentDetails(auth: auth, session: session, configuration: configuration).pricing
    }
}

// MARK: - Current details

/// What OpenRouter lists for a model now: its prices, limits and parameters, which can change after the catalog was
/// generated.
///
/// ``OpenRouterModel/currentDetails(auth:session:configuration:)`` reads them, and
/// ``OpenRouterModel/currentPricing(auth:session:configuration:)`` reads only the prices.
public struct OpenRouterCurrentDetails: Sendable, Hashable {
    /// The model's OpenRouter id, such as `anthropic/claude-haiku-5.5`.
    public let id: OpenRouterModelID

    /// The model's human-readable name.
    public let displayName: String

    /// The model that an alias, such as `~anthropic/claude-haiku-latest`, points to now, or `nil` for a model that
    /// isn't an alias.
    public let aliasTarget: OpenRouterModelID?

    /// The size of the model's context window, in tokens.
    public let contextSize: Int?

    /// The most tokens the model can generate in one response, at the host OpenRouter ranks first.
    public let maximumOutputTokens: Int?

    /// What OpenRouter charges for the model, or `nil` when the price depends on the request, as for a router.
    ///
    /// The model's endpoints can charge other prices; ``OpenRouterModel/endpoints(auth:session:configuration:)`` lists
    /// each one's.
    public let pricing: OpenRouterPricing?

    /// The request parameters the model accepts, such as `tools` or `seed`.
    public let supportedParameters: Set<OpenRouterParameter>

    /// Whether the host OpenRouter ranks first moderates content.
    public let isModerated: Bool

    /// The day OpenRouter retires the model, at midnight UTC.
    public let expirationDate: Date?

    /// Creates a model's current details, such as for a preview.
    ///
    /// - Parameters:
    ///   - id: The model's OpenRouter id.
    ///   - displayName: The model's human-readable name.
    ///   - aliasTarget: The model an alias points to now.
    ///   - contextSize: The size of the model's context window, in tokens.
    ///   - maximumOutputTokens: The most tokens the model can generate in one response.
    ///   - pricing: What OpenRouter charges for the model.
    ///   - supportedParameters: The request parameters the model accepts.
    ///   - isModerated: Whether the host OpenRouter ranks first moderates content.
    ///   - expirationDate: The day OpenRouter retires the model.
    public init(
        id: OpenRouterModelID,
        displayName: String,
        aliasTarget: OpenRouterModelID? = nil,
        contextSize: Int? = nil,
        maximumOutputTokens: Int? = nil,
        pricing: OpenRouterPricing? = nil,
        supportedParameters: Set<OpenRouterParameter> = [],
        isModerated: Bool = false,
        expirationDate: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.aliasTarget = aliasTarget
        self.contextSize = contextSize
        self.maximumOutputTokens = maximumOutputTokens
        self.pricing = pricing
        self.supportedParameters = supportedParameters
        self.isModerated = isModerated
        self.expirationDate = expirationDate
    }
}

// MARK: - Connection

extension Connection {
    /// One model's current details.
    ///
    /// - Parameters:
    ///   - model: The model.
    ///   - lifetime: How long an answer stays fresh in the cache.
    /// - Returns: The details.
    /// - Throws: What ``value(at:as:for:)`` throws.
    fileprivate func currentDetails(of model: OpenRouterModelID, for lifetime: Duration) async throws -> OpenRouterCurrentDetails {
        OpenRouterCurrentDetails(try await value(at: API.Path.model(model), as: OpenRouterCurrentDetails.Payload.self, for: lifetime))
    }

    /// Reads a path under the base URL, or OpenRouter's own API, and decodes the `data` of the answer's body, or reuses
    /// a fresh answer from the cache, with a failure thrown as a chat request's would be.
    ///
    /// - Parameters:
    ///   - path: The path under the base URL, such as `models/anthropic/claude-haiku-5.5/endpoints`.
    ///   - type: The type of the body's `data`.
    ///   - lifetime: How long an answer stays fresh in the cache.
    /// - Returns: The decoded `data`.
    /// - Throws: `OpenRouterError` with `invalidResponse` when the body doesn't decode, and otherwise the error a
    ///   rejected response becomes, what the authentication throws, and a failed connection's error.
    func value<Value: Decodable & Sendable>(at path: String, as type: Value.Type, for lifetime: Duration) async throws -> Value {
        try await cachedValue(
            at: path, under: API.baseURL(authentication.baseURL), for: lifetime, provider: API.name, decode: Self.decode,
            failure: { (rejected: RequestFailure<OpenRouterErrorResponse>) in OpenRouterFailure(rejected).error(contextSize: nil) })
    }

    /// The `data` of an answer's body.
    ///
    /// - Throws: `OpenRouterError` with `invalidResponse` when the body doesn't decode.
    private static func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(DataEnvelope<Value>.self, from: data).data
        } catch {
            throw OpenRouterError(message: "OpenRouter sent a response that couldn't be read: \(error)", code: .invalidResponse)
        }
    }
}

// MARK: - Reading

extension OpenRouterCurrentDetails {
    /// A model's current details from OpenRouter's answer.
    fileprivate init(_ payload: OpenRouterCurrentDetails.Payload) {
        self.init(
            id: OpenRouterModelID(rawValue: payload.id),
            displayName: payload.name,
            aliasTarget: payload.aliasTarget.map { OpenRouterModelID(rawValue: $0.slug) },
            contextSize: payload.contextLength,
            maximumOutputTokens: payload.topProvider?.maxCompletionTokens,
            pricing: payload.pricing.flatMap(OpenRouterPricing.init),
            supportedParameters: Set((payload.supportedParameters ?? []).map(OpenRouterParameter.init(rawValue:))),
            isModerated: payload.topProvider?.isModerated ?? false,
            expirationDate: payload.expirationDate.flatMap(Self.midnightUTC)
        )
    }

    /// Midnight UTC at the start of a day written as `YYYY-MM-DD`, or `nil` for text that isn't such a day.
    private static func midnightUTC(_ day: String) -> Date? {
        try? Date(day, strategy: Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    }
}

// MARK: - Wire

extension OpenRouterCurrentDetails {
    /// The `data` of `GET /model/{author}/{slug}`.
    fileprivate struct Payload: Decodable, Sendable {
        struct AliasTarget: Decodable, Sendable {
            let slug: String
        }

        struct TopProvider: Decodable, Sendable {
            let maxCompletionTokens: Int?
            let isModerated: Bool?

            private enum CodingKeys: String, CodingKey {
                case maxCompletionTokens = "max_completion_tokens"
                case isModerated = "is_moderated"
            }
        }

        let id: String
        let name: String
        let aliasTarget: AliasTarget?
        let contextLength: Int?
        let topProvider: TopProvider?
        let pricing: OpenRouterPricing.Payload?
        let supportedParameters: [String]?
        /// The day as `YYYY-MM-DD`.
        let expirationDate: String?

        private enum CodingKeys: String, CodingKey {
            case id, name, pricing
            case aliasTarget = "alias_target"
            case contextLength = "context_length"
            case topProvider = "top_provider"
            case supportedParameters = "supported_parameters"
            case expirationDate = "expiration_date"
        }
    }
}

/// The body of OpenRouter's answers, `{"data": …}`.
private struct DataEnvelope<Value: Decodable>: Decodable {
    let data: Value
}
