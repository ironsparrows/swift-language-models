public import Foundation
public import FoundationModels
public import LanguageModels

// MARK: - Response

/// What OpenRouter reported about an answer, read from the metadata of its response entry, or about a request that
/// ended in tool calls, read from its first call.
///
/// `Transcript.Response.openRouter` and `Transcript.ToolCalls.openRouter` read it. The response entry that ends an
/// answer carries the facts, and one that tool calls follow carries only the ``citations``. A fact OpenRouter didn't
/// report is `nil`, and a list it didn't report is empty:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if case .response(let answer)? = response.transcriptEntries.last {
///     print("\(answer.openRouter.provider ?? "A host") answered.")
///     if answer.openRouter.finishReason == .length {
///         print("The answer was cut short at its token limit.")
///     }
/// }
/// ```
///
/// The facts ``model``, ``provider``, ``responseID``, ``finishReason``, ``serviceTier`` and ``citations`` use keys
/// every provider shares, so they also read from another provider's answer, in that provider's words. The routing facts
/// come from the router's report, which the answer keeps when ``OpenRouterOptions/includesRouterMetadata`` is `true`.
public struct OpenRouterResponseMetadata: Sendable, Hashable {
    /// The model that answered, which can differ from the one asked for when OpenRouter routes the request or a
    /// fallback answers. The request is billed at this model's price.
    public let model: OpenRouterModelID?

    /// The host that served the answer, such as `Anthropic`.
    ///
    /// OpenRouter calls the hosts that serve its models providers, and the name keeps OpenRouter's word: it names the
    /// host, never OpenRouter itself.
    public let provider: OpenRouterProviderName?

    /// OpenRouter's id for the answer, such as `gen-…`, which its generation statistics are looked up by.
    public let responseID: String?

    /// Why the answer ended, such as ``FinishReason/length`` when it reached its token limit.
    ///
    /// A text answer cut off at its token limit doesn't throw, so its reason is the way to tell. A guided answer, or
    /// tool calls, cut off there throw instead.
    public let finishReason: FinishReason?

    /// The processing tier that served the answer, which it's billed at.
    ///
    /// It can differ from ``OpenRouterOptions/serviceTier``, such as ``OpenRouterServiceTier/priority`` for a request
    /// that asked for ``OpenRouterServiceTier/ultrafast`` from a model without that tier.
    public let serviceTier: OpenRouterServiceTier?

    /// The web pages the answer cites, in the order OpenRouter listed them, from the ``OpenRouterServerTool`` web
    /// search.
    ///
    /// Citations point into the answer's text, so they're on the response entry even when tool calls end the answer.
    public let citations: [Citation]

    /// Whether the ``OpenRouterResponseCache`` served the answer: ``OpenRouterResponseCache/Status/hit`` for an answer
    /// it kept from an earlier request, at no cost, ``OpenRouterResponseCache/Status/miss`` for a new answer that it
    /// now keeps, and `nil` when the cache is off.
    public let responseCacheStatus: OpenRouterResponseCache.Status?

    /// How long the ``OpenRouterResponseCache`` had kept the answer when it served it, to the second.
    public let responseCacheAge: Duration?

    /// The response id of the answer that the ``OpenRouterResponseCache`` kept and served again, such as `gen-…`.
    ///
    /// The answer's own ``responseID`` is new for each answer the cache serves.
    public let responseCacheSourceID: String?

    /// How OpenRouter picked the model and host, such as ``OpenRouterResponseMetadata/RoutingStrategy/fallback``.
    public let routingStrategy: OpenRouterResponseMetadata.RoutingStrategy?

    /// Which attempt answered, from 1. More than 1 means that earlier hosts or models failed.
    public let routingAttempt: Int?

    /// The hosts and models OpenRouter tried, in order.
    public let routingAttempts: [RoutingAttempt]

    /// The endpoints OpenRouter could pick from.
    public let routingEndpoints: [RoutingEndpoint]

    /// The plugins that changed the request or the answer, such as the engine that reads PDFs or a guardrail.
    public let routingPipeline: [PipelineStage]

    /// The OpenRouter edge region that handled the request, such as `iad`.
    public let region: String?

    /// How long the host took, from OpenRouter sending it the request until its answer ended.
    ///
    /// The output tokens divided by it give the host's throughput.
    public let generationTime: Duration?

    /// What OpenRouter reported about the request's cost and counts, such as its cost in US dollars.
    ///
    /// A response's own `usage` has only its last request's facts, so a response whose tool calls ran reads each
    /// earlier request's here, on the tool calls it asked for. Adding up the ``OpenRouterUsageMetadata/cost`` of each
    /// entry that ends a request gives what the whole response cost.
    public let usage: OpenRouterUsageMetadata

    /// The facts in the metadata of a response entry, or of the first call of a tool-calls entry.
    init(_ metadata: [String: GeneratedContent]) {
        let shared = ProviderResponseMetadata(metadata)
        let values = MetadataValues(metadata)
        model = shared.model.map(OpenRouterModelID.init(rawValue:))
        provider = shared.host.map(OpenRouterProviderName.init(rawValue:))
        responseID = shared.responseID
        finishReason = shared.finishReason
        serviceTier = shared.serviceTier.map(OpenRouterServiceTier.init(rawValue:))
        citations = shared.citations
        responseCacheStatus = values.string(Key.responseCacheStatus).map(OpenRouterResponseCache.Status.init(rawValue:))
        responseCacheAge = values.duration(Key.responseCacheAge)
        responseCacheSourceID = values.string(Key.responseCacheSourceID)
        routingStrategy = values.string(Key.routingStrategy).map(
            OpenRouterResponseMetadata.RoutingStrategy.init(rawValue:))
        routingAttempt = values.integer(Key.routingAttempt)
        routingAttempts = values.structures(Key.routingAttempts).map(RoutingAttempt.init)
        routingEndpoints = values.structures(Key.routingEndpoints).map(RoutingEndpoint.init)
        routingPipeline = values.structures(Key.routingPipeline).map(PipelineStage.init)
        region = values.string(Key.region)
        generationTime = values.duration(Key.generationTime)
        usage = OpenRouterUsageMetadata(metadata)
    }
}

extension OpenRouterResponseMetadata {
    /// A host and model that OpenRouter tried, in the router's report.
    public struct RoutingAttempt: Sendable, Hashable {
        /// The host, such as `Anthropic`.
        public let provider: OpenRouterProviderName?

        /// The model asked of the host.
        public let model: OpenRouterModelID?

        /// The HTTP status the host answered with, such as 503 for a host that was down.
        public let status: Int?

        fileprivate init(_ values: MetadataValues) {
            provider = values.string(Field.provider).map(OpenRouterProviderName.init(rawValue:))
            model = values.string(Field.model).map(OpenRouterModelID.init(rawValue:))
            status = values.integer(Field.status)
        }
    }

    /// An endpoint that OpenRouter could pick from, in the router's report.
    public struct RoutingEndpoint: Sendable, Hashable {
        /// The host, such as `Anthropic`.
        public let provider: OpenRouterProviderName?

        /// The model the host serves.
        public let model: OpenRouterModelID?

        /// Whether OpenRouter picked the endpoint.
        public let isSelected: Bool?

        fileprivate init(_ values: MetadataValues) {
            provider = values.string(Field.provider).map(OpenRouterProviderName.init(rawValue:))
            model = values.string(Field.model).map(OpenRouterModelID.init(rawValue:))
            isSelected = values.bool(Field.selected)
        }
    }

    /// A plugin that changed the request or the answer, in the router's report.
    public struct PipelineStage: Sendable, Hashable {
        /// The kind of stage, such as ``Kind/guardrail``.
        public let kind: Kind?

        /// The plugin, such as ``OpenRouterPlugin/fileParser``.
        public let plugin: OpenRouterPlugin?

        /// What the plugin did, when OpenRouter wrote it down.
        public let summary: String?

        fileprivate init(_ values: MetadataValues) {
            kind = values.string(Field.type).map(Kind.init(rawValue:))
            plugin = values.string(Field.name).map(OpenRouterPlugin.init(rawValue:))
            summary = values.string(Field.summary)
        }
    }
}

extension OpenRouterResponseMetadata.PipelineStage {
    /// A kind of stage in the router's report, as its `type` names it. Any kind OpenRouter reports is valid.
    public struct Kind: ProviderVocabulary {
        /// A guardrail that checked the request or the answer.
        public static let guardrail: Self = "guardrail"

        /// A plugin the request asked for.
        public static let plugin: Self = "plugin"

        /// OpenRouter's server tools.
        public static let serverTools: Self = "server_tools"

        /// Response healing, which repaired an answer that broke its schema.
        public static let responseHealing: Self = "response_healing"

        /// Context compression, which shortened a prompt too long for the model.
        public static let contextCompression: Self = "context_compression"

        /// The kind as the router's report spells it.
        public let rawValue: String

        /// Creates a kind from the router's spelling of it.
        ///
        /// - Parameter rawValue: The kind, such as `"guardrail"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

extension OpenRouterResponseMetadata {
    /// How OpenRouter picked the model and host for a request, as the router's report names it, such as ``fallback``.
    ///
    /// Any strategy OpenRouter reports is valid, with or without a static member.
    public struct RoutingStrategy: ProviderVocabulary {
        /// OpenRouter sent the request to a host of the model it names.
        public static let direct: Self = "direct"

        /// The Auto Router, `openrouter/auto`, picked the model.
        public static let auto: Self = "auto"

        /// OpenRouter's `free` routing.
        public static let free: Self = "free"

        /// OpenRouter's `latest` routing.
        public static let latest: Self = "latest"

        /// The request named an alias, which OpenRouter resolved to the model it stands for.
        public static let alias: Self = "alias"

        /// An earlier host or model failed, and OpenRouter fell back to another.
        public static let fallback: Self = "fallback"

        /// The Pareto router, such as `openrouter/pareto-code`, picked the model.
        public static let pareto: Self = "pareto"

        /// OpenRouter's `bodybuilder` routing.
        public static let bodybuilder: Self = "bodybuilder"

        /// OpenRouter's `fusion` routing.
        public static let fusion: Self = "fusion"

        /// The strategy as the router's report spells it.
        public let rawValue: String

        /// Creates a strategy from the router's spelling of it.
        ///
        /// - Parameter rawValue: The strategy, such as `"fallback"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

extension OpenRouterResponseCache.Report {
    /// The report as metadata of the entry that ends the answer.
    var metadata: [String: any ConvertibleToGeneratedContent] {
        var metadata: [String: any ConvertibleToGeneratedContent] = [Key.responseCacheStatus: status.rawValue]
        metadata[Key.responseCacheAge] = age
        metadata[Key.responseCacheSourceID] = sourceID
        return metadata
    }
}

extension OpenRouterChunkExtras.RouterMetadata {
    /// The router's report as metadata of the entry that ends the answer, with the generation time in seconds.
    var metadata: [String: any ConvertibleToGeneratedContent] {
        typealias Field = OpenRouterResponseMetadata.Field
        var metadata: [String: any ConvertibleToGeneratedContent] = [:]
        metadata[Key.routingStrategy] = strategy
        metadata[Key.routingAttempt] = attempt
        metadata[Key.routingAttempts] = attempts?.map { attempt in
            GeneratedContent(properties: [Field.provider: attempt.provider, Field.model: attempt.model, Field.status: attempt.status])
        }
        metadata[Key.routingEndpoints] = endpoints?.available?.map { endpoint in
            GeneratedContent(properties: [
                Field.provider: endpoint.provider, Field.model: endpoint.model, Field.selected: endpoint.selected,
            ])
        }
        metadata[Key.routingPipeline] = pipeline?.map { stage in
            GeneratedContent(properties: [Field.type: stage.type, Field.name: stage.name, Field.summary: stage.summary])
        }
        metadata[Key.region] = region
        metadata[Key.generationTime] = generationTime.map { $0 / 1_000 }
        return metadata
    }
}

extension OpenRouterResponseMetadata {
    /// The names of the fields of the router report's structures in an entry's metadata.
    fileprivate enum Field {
        static let provider = "provider"
        static let model = "model"
        static let status = "status"
        static let selected = "selected"
        static let type = "type"
        static let name = "name"
        static let summary = "summary"
    }
}

// MARK: - Usage

/// What OpenRouter reported about an answer's cost and counts, read from its usage's metadata.
///
/// `LanguageModelSession.Usage.openRouter` reads it. Amounts are in US dollars, as `Decimal` values without binary
/// rounding noise, such as exactly `0.000012345` rather than `0.000012344999…`, and a fact OpenRouter didn't report is
/// `nil`:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if let cost = response.usage.openRouter.cost {
///     print("It cost $\(cost).")
/// }
/// ```
///
/// The facts are those of one request. A response whose tool calls ran has the last request's, and a session's own
/// `usage`, which adds up the token counts, keeps no metadata, so its facts are all `nil`. Each request's facts are
/// also on the transcript entry that ends it, which ``OpenRouterResponseMetadata/usage`` reads, so adding up their
/// costs gives what a response with tool calls cost:
///
/// ```swift
/// let cost = response.transcriptEntries.reduce(Decimal.zero) { total, entry in
///     switch entry {
///     case .toolCalls(let calls): total + (calls.openRouter.usage.cost ?? 0)
///     case .response(let answer): total + (answer.openRouter.usage.cost ?? 0)
///     default: total
///     }
/// }
/// ```
///
/// The facts ``cost``, ``cacheWriteTokenCount`` and ``webSearchCount`` use keys every provider shares, so they also
/// read from another provider's usage.
public struct OpenRouterUsageMetadata: Sendable, Hashable {
    /// What the answer cost, in US dollars, from the account's OpenRouter credits.
    ///
    /// When ``isBYOK`` is `true`, it's only OpenRouter's fee, and the host bills the account's own key for
    /// ``upstreamInferenceCost``.
    public let cost: Decimal?

    /// The prompt tokens written to the host's prompt cache.
    public let cacheWriteTokenCount: Int?

    /// Whether the request used the account's own key for the host, rather than OpenRouter's, so the host billed that
    /// key.
    public let isBYOK: Bool?

    /// What the host charged for the answer, in US dollars, when OpenRouter reports it, as for a request that used the
    /// account's own key.
    public let upstreamInferenceCost: Decimal?

    /// The part of the host's charge for the prompt, in US dollars.
    public let upstreamInferencePromptCost: Decimal?

    /// The part of the host's charge for the output, in US dollars.
    public let upstreamInferenceCompletionCost: Decimal?

    /// What server tools that are billed by use cost, in US dollars, such as the time a sandbox ran; 0 when they ran
    /// for free.
    public let serverToolCost: Decimal?

    /// The server-tool calls the model asked for, of every kind, such as ``OpenRouterServerTool`` web searches and
    /// fetches. A host's own web search isn't counted.
    public let requestedServerToolCallCount: Int?

    /// The server-tool calls that ran and gave the model a result.
    public let executedServerToolCallCount: Int?

    /// The web searches that ran, by ``OpenRouterServerTool`` or by the host's own search.
    ///
    /// A search by ``OpenRouterServerTool`` also counts in ``requestedServerToolCallCount``, so don't add the two
    /// together.
    public let webSearchCount: Int?

    /// The facts in a usage's metadata.
    fileprivate init(_ metadata: [String: GeneratedContent]) {
        let shared = ProviderUsageMetadata(metadata)
        let values = MetadataValues(metadata)
        cost = shared.cost
        cacheWriteTokenCount = shared.cacheWriteTokenCount
        isBYOK = values.bool(Key.isBYOK)
        upstreamInferenceCost = values.decimal(Key.upstreamInferenceCost)
        upstreamInferencePromptCost = values.decimal(Key.upstreamInferencePromptCost)
        upstreamInferenceCompletionCost = values.decimal(Key.upstreamInferenceCompletionCost)
        serverToolCost = values.decimal(Key.serverToolCost)
        requestedServerToolCallCount = values.integer(Key.requestedServerToolCallCount)
        executedServerToolCallCount = values.integer(Key.executedServerToolCallCount)
        webSearchCount = shared.webSearchCount
    }
}

extension OpenRouterChunkExtras.Usage {
    /// What only OpenRouter reports about the usage, as metadata of the answer's usage: the parts of the cost, whether
    /// the account's own key paid and the server tools' calls.
    var metadata: [String: any ConvertibleToGeneratedContent] {
        var metadata: [String: any ConvertibleToGeneratedContent] = [:]
        metadata[Key.isBYOK] = isBYOK
        metadata[Key.upstreamInferenceCost] = costDetails?.upstreamInferenceCost
        metadata[Key.upstreamInferencePromptCost] = costDetails?.upstreamInferencePromptCost
        metadata[Key.upstreamInferenceCompletionCost] = costDetails?.upstreamInferenceCompletionsCost
        metadata[Key.serverToolCost] = costDetails?.serverToolCost
        metadata[Key.requestedServerToolCallCount] = serverToolUseDetails?.toolCallsRequested
        metadata[Key.executedServerToolCallCount] = serverToolUseDetails?.toolCallsExecuted
        return metadata
    }
}

// MARK: - Error

/// What OpenRouter reported about a failure that throws Foundation Models' `LanguageModelError`, in OpenRouter's own
/// words, read from the error's metadata.
///
/// `LanguageModelError.openRouter` reads it. A fact OpenRouter didn't report is `nil`:
///
/// ```swift
/// do {
///     let response = try await session.respond(to: "Plan dinner.")
///     print(response.content)
/// } catch LanguageModelError.rateLimited(let limit) {
///     print("Try again after \(limit.resetDate ?? .now).")
/// } catch let error as LanguageModelError where error.openRouter.limitSource == .apiKey {
///     print("The key's spending budget ran out.")
/// }
/// ```
///
/// Its facts are the shared ones that `providerMetadata` also reads, as OpenRouter's types, and ``limitSource``.
public struct OpenRouterErrorMetadata: Sendable, Hashable {
    /// The HTTP status of the response that failed, such as 429 for a rate limit, or for an error in the stream, which
    /// arrives after the response's HTTP 200, the status its code names. `nil` for a failure in the stream whose code
    /// isn't a number.
    public let status: Int?

    /// The code the failure would have as an ``OpenRouterError``, such as ``OpenRouterError/Code/budgetExceeded``.
    public let code: OpenRouterError.Code?

    /// The host that failed, such as `Anthropic`, when OpenRouter names one.
    public let provider: OpenRouterProviderName?

    /// The budget or limit the request ran into, such as the key's spending budget, when OpenRouter names one.
    public let limitSource: LimitSource?

    /// The facts in an error's metadata.
    init(_ metadata: [String: any Sendable]) {
        let shared = ProviderErrorMetadata(metadata)
        status = shared.status
        code = shared.code.map(OpenRouterError.Code.init(rawValue:))
        provider = shared.host.map(OpenRouterProviderName.init(rawValue:))
        limitSource = (metadata[Key.limitSource] as? String).map(LimitSource.init(rawValue:))
    }

    /// The metadata of a `LanguageModelError`: the status, the code, the host that failed and the budget it ran into.
    static func metadata(
        status: Int?, code: OpenRouterError.Code, provider: OpenRouterProviderName?, limitSource: LimitSource?
    ) -> [String: any Sendable] {
        var metadata = ProviderErrorMetadata(status: status, code: code.rawValue, host: provider?.rawValue).contextMetadata
        metadata[Key.limitSource] = limitSource?.rawValue
        return metadata
    }
}

extension OpenRouterErrorMetadata {
    /// The budget or limit a request ran into, as OpenRouter's `limit_source` names it.
    public struct LimitSource: ProviderVocabulary {
        /// The key's spending budget.
        public static let apiKey: Self = "api_key"

        /// The most requests a key may have in flight at once.
        public static let inFlightBudget: Self = "openrouter_in_flight_budget"

        /// The source as OpenRouter's API spells it.
        public let rawValue: String

        /// Creates a source from OpenRouter's spelling of it.
        ///
        /// - Parameter rawValue: The source, such as `"api_key"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

// MARK: - Reading

extension Transcript.Response {
    /// What OpenRouter reported about the answer, such as the model and host that served it and why it ended.
    public var openRouter: OpenRouterResponseMetadata {
        OpenRouterResponseMetadata(metadata)
    }
}

extension Transcript.ToolCalls {
    /// What OpenRouter reported about the request that asked for these tool calls, such as the model and host that
    /// served it.
    ///
    /// Foundation Models keeps no readable metadata on the tool-calls entry itself, so the request's facts sit on its
    /// first call, and this reads them from there. A request that asked for several calls has one set of facts.
    public var openRouter: OpenRouterResponseMetadata {
        OpenRouterResponseMetadata(first?.metadata ?? [:])
    }
}

extension LanguageModelSession.Usage {
    /// What OpenRouter reported about the answer's cost and counts, such as its cost in US dollars.
    public var openRouter: OpenRouterUsageMetadata {
        OpenRouterUsageMetadata(metadata)
    }
}

extension LanguageModelError {
    /// What OpenRouter reported about the failure, such as the host that failed and the budget the request ran into.
    public var openRouter: OpenRouterErrorMetadata {
        OpenRouterErrorMetadata(contextMetadata)
    }
}

// MARK: - Keys

/// The keys of the facts that only OpenRouter reports, which start with `openRouter.`, so they never collide with
/// another provider's keys.
///
/// The response or tool-calls entry that ends an answer carries what the response cache did, and the router's report
/// when ``OpenRouterOptions/includesRouterMetadata`` is `true`. The answer's usage carries the parts of its cost,
/// whether the account's own key paid the host, and the server tools' calls. A key is left out when OpenRouter didn't
/// report its value.
///
/// Saved transcripts keep the keys, so their spellings never change.
private enum Key {
    /// An ``OpenRouterResponseCache/Status`` raw value: `HIT` or `MISS`.
    static let responseCacheStatus = "openRouter.responseCacheStatus"

    /// In seconds.
    static let responseCacheAge = "openRouter.responseCacheAge"

    static let responseCacheSourceID = "openRouter.responseCacheSourceID"
    static let routingStrategy = "openRouter.routingStrategy"
    static let routingAttempt = "openRouter.routingAttempt"

    /// A list of structures, each with the host's `provider`, the `model` and the HTTP `status` it answered with.
    static let routingAttempts = "openRouter.routingAttempts"

    /// A list of structures, each with the host's `provider`, the `model`, and whether it was `selected`.
    static let routingEndpoints = "openRouter.routingEndpoints"

    /// A list of structures, each with the stage's `type`, such as `guardrail`, the plugin's `name`, such as
    /// `content-filter`, and a `summary` of what it did when OpenRouter wrote one.
    static let routingPipeline = "openRouter.routingPipeline"

    static let region = "openRouter.region"

    /// In seconds.
    static let generationTime = "openRouter.generationTime"

    static let isBYOK = "openRouter.isBYOK"
    static let upstreamInferenceCost = "openRouter.upstreamInferenceCost"
    static let upstreamInferencePromptCost = "openRouter.upstreamInferencePromptCost"
    static let upstreamInferenceCompletionCost = "openRouter.upstreamInferenceCompletionCost"
    static let serverToolCost = "openRouter.serverToolCost"
    static let requestedServerToolCallCount = "openRouter.requestedServerToolCallCount"
    static let executedServerToolCallCount = "openRouter.executedServerToolCallCount"

    /// On the metadata of every `LanguageModelError` whose body names one.
    static let limitSource = "openRouter.limitSource"
}
