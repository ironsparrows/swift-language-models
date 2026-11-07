import Foundation
import FoundationModels
import LanguageModels
import UniformTypeIdentifiers

// MARK: - As a Chat Completions model

extension OpenRouterLanguageModel {
    /// This model as a Chat Completions model: what is true for every request, and OpenRouter's part in each.
    ///
    /// - Parameter configuration: Where requests go, how they name the app and how they're sent.
    /// - Returns: The model.
    /// - Throws: `OpenRouterError` with `invalidRequest` when there's no valid base URL.
    func chatCompletions(_ configuration: Executor.Configuration) throws(OpenRouterError)
        -> ChatCompletions.Model<OpenRouterExchange>
    {
        let exchange = OpenRouterExchange(
            model: OpenRouterLanguageModel<ContextOptions.ReasoningLevel>(self), details: sharedDetails, app: configuration.app)
        var model = ChatCompletions.Model(
            name: routing.modelID(for: details.id).rawValue, url: try API.baseURL(configuration.baseURL),
            connection: connection(configuration.settings), providerName: API.name, capabilities: capabilities,
            reaching: [details] + fallbacks, exchange: exchange)
        model.memberOrder = OpenRouterExchange.memberOrder
        model.unsupportedMembers = OpenRouterExchange.listedMembers.filter { !exchange.lists($0) }
        model.media = OpenRouterInputModality.media
        model.images = configuration.settings.images
        model.reasoningOrigin = API.reasoningOrigin
        return model
    }
}

// MARK: - Exchange

/// OpenRouter's part in one exchange: the fallback models, routing, plugins, server tools, session id and cache marks its
/// requests add, the parameters its models list, the headers that name the app, and the reasoning, images, costs and
/// errors its chunks carry.
///
/// Every method with a default is here, in the type that declares the conformance, so a misspelled one draws a warning
/// instead of silently keeping the default.
struct OpenRouterExchange: ChatCompletions.Exchange {
    /// The model and its fallbacks.
    private let model: OpenRouterLanguageModel<ContextOptions.ReasoningLevel>

    /// The model's details narrowed to what each fallback also supports.
    private let details: OpenRouterModel<ContextOptions.ReasoningLevel>

    /// How requests name the app.
    private let app: OpenRouterApp

    /// The host that served the answer.
    ///
    /// This and the three values after it are what OpenRouter's chunks report about one answer beyond the format's facts.
    /// Chunks repeat some facts and leave out others, so a fact that a chunk reports replaces the earlier one, and one it
    /// leaves out keeps its earlier value.
    private var host: OpenRouterProviderName?

    /// What OpenRouter added to the usage the last chunk with usage reported.
    private var usage: OpenRouterChunkExtras.Usage?

    /// How OpenRouter routed the request, when the options include it.
    private var routerReport: OpenRouterChunkExtras.RouterMetadata?

    /// The `reasoning_details` the model sent, or `nil` when it sent none. Some models send an empty list, and
    /// expect it back.
    private var reasoningDetails: ReasoningDetails?

    /// The order OpenRouter's requests have always sent their members in, which a host's prompt cache and OpenRouter's
    /// response cache depend on.
    fileprivate static let memberOrder: [ChatCompletions.Member] = [
        .model, .models, .messages, .modalities, .stream, .tools, .toolChoice, .parallelToolCalls, .responseFormat, .reasoning,
        .temperature, .topP, .topK, .seed, .maxCompletionTokens, .maxTokens, .frequencyPenalty, .presencePenalty, .repetitionPenalty,
        .minP, .topA, .stop, .logitBias, .verbosity, .serviceTier, .user, .provider, .plugins, .sessionID, .metadata, .cacheControl,
    ]

    /// The members that go out only when the model and each fallback list them.
    fileprivate static let listedMembers: Set<ChatCompletions.Member> = [
        .toolChoice, .parallelToolCalls, .temperature, .topP, .topK, .seed, .maxTokens, .frequencyPenalty, .presencePenalty,
        .repetitionPenalty, .minP, .topA, .stop, .logitBias, .verbosity,
    ]

    fileprivate init(
        model: OpenRouterLanguageModel<ContextOptions.ReasoningLevel>,
        details: OpenRouterModel<ContextOptions.ReasoningLevel>,
        app: OpenRouterApp
    ) {
        self.model = model
        self.details = details
        self.app = app
    }

    /// Whether the model and each fallback list a parameter, which OpenRouter names as the body does.
    fileprivate func lists(_ member: ChatCompletions.Member) -> Bool {
        details.supportedParameters.contains(OpenRouterParameter(rawValue: member.rawValue))
    }

    // MARK: While the request is read

    /// Checks that every model takes an attachment, as Foundation Models does before a request: images, and data of the
    /// input kinds they all take.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` with `.vision` for an image attachment when a model doesn't
    ///   take images, and `LanguageModelError.unsupportedTranscriptContent` for a data attachment a model doesn't take,
    ///   images included, as `supportsDataAttachmentType` refuses it.
    func checkAttachment(_ kind: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {
        switch kind {
        case .image:
            guard model.attachmentInputs.contains(.image) else {
                throw LanguageModelError.unsupported(.vision, "The model or one of its fallbacks doesn't take images.")
            }
        case .data(let type):
            guard let input = OpenRouterInputModality(carrying: type) else {
                throw LanguageModelError.unsupported(entry, "\(API.name) takes no attachments of type \(type.identifier).")
            }
            guard model.attachmentInputs.contains(input) else {
                throw LanguageModelError.unsupported(
                    entry, "The model or one of its fallbacks doesn't take \(input) attachments, such as \(type.identifier).")
            }
        }
    }

    /// Whether OpenRouter's reasoning goes back: only to the model that wrote it.
    func replays(_ reasoning: Transcript.Reasoning) -> Bool {
        model.replaysReasoning(writtenBy: reasoning.writer)
    }

    /// The assistant message's `reasoning` and `reasoning_details` for the reasoning it sends back.
    func replayMembers(for reasoning: [(entry: Transcript.Reasoning, text: String)]) -> JSONObject {
        ReasoningDetails.replayMembers(for: reasoning)
    }

    // MARK: Before it is sent

    /// OpenRouter's headers and members, and each setting that the model or a fallback doesn't list left out.
    ///
    /// A model's list holds every parameter any of its hosts takes, so with tools or a schema, when the request asks
    /// for hosts that take all it sends, each setting sent also narrows its hosts.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` when tool calls are required and a model doesn't take
    ///   `tool_choice`, when there are server tools and a model doesn't take tools, and for a schema when a model
    ///   doesn't take structured outputs.
    func prepare(_ request: inout ChatCompletions.Request) throws {
        let options = model.options
        let toolCallingMode = request.generation.generationOptions.toolCallingMode
        let hasSchema = request.generation.schema != nil
        // A model that doesn't take tools gets none of the session's, and requiring a call needs `tool_choice`, the
        // only way to require one.
        let sendsSessionTools = request.hasSessionTools && lists(.tools)
        if sendsSessionTools, toolCallingMode?.kind == .required, !lists(.toolChoice) {
            let description = "The model or one of its fallbacks doesn't take tool_choice, so it can't be made to call a tool."
            throw LanguageModelError.unsupported(.toolCalling, description)
        }
        let serverTools = try serverTools(toolCallingMode: toolCallingMode)
        if hasSchema, !details.supportedParameters.contains(.structuredOutputs) {
            let description = "The model or one of its fallbacks doesn't take structured outputs, so it can't hold its answer to a schema."
            throw LanguageModelError.unsupported(.guidedGeneration, description)
        }
        let needsParameters = sendsSessionTools || !serverTools.isEmpty || hasSchema
        let sampling = request.sampling
        // A request with tools or a schema needs hosts that take every parameter it sends, so greedy sampling's `top_k`
        // 1 goes only with requests that have neither, to models that list it.
        let greedyTopK = sampling.isGreedy && !needsParameters && lists(.topK) ? 1 : nil
        let reasoning = Self.reasoning(request.generation.contextOptions.reasoningLevel, details: details)
        let fallbackIDs = model.fallbacks.map { model.routing.modelID(for: $0.id) }
        request.headers = headers(firstPromptID: request.firstPromptID)
        request.members = try JSONValueEncoder.members(
            of: Members(
                models: fallbackIDs.isEmpty ? nil : fallbackIDs,
                modalities: Self.modalities(details.outputModalities, hasSchema: hasSchema),
                // The parallel calls concern only the session's tools.
                parallelToolCalls: sendsSessionTools ? options.parallelToolCalls.value : nil,
                reasoning: reasoning.setting,
                topK: sampling.topK ?? greedyTopK,
                frequencyPenalty: options.frequencyPenalty,
                presencePenalty: options.presencePenalty,
                repetitionPenalty: options.repetitionPenalty,
                minP: options.minP,
                topA: options.topA,
                stop: options.stopSequences,
                logitBias: options.logitBias.map(Members.LogitBias.init),
                verbosity: options.verbosity,
                serviceTier: options.serviceTier,
                user: options.endUserID,
                provider: model.routing.member(needsParameters: needsParameters),
                plugins: Self.plugins(for: model.modelIDs, options: options, carriesPDF: request.carriesPDF),
                // The response cache compares the whole body, and the session id differs for every session, so it goes in a
                // header while the cache is on, and new sessions can repeat an earlier request.
                sessionID: model.responseCache == nil ? Self.sessionID(request.firstPromptID) : nil,
                cacheControl: model.requestCacheControl?.directive
            ))
        request.sendsSessionTools = sendsSessionTools
        request.serverTools = try serverTools.map { try JSONValueEncoder.encode($0) }
        // The token limit goes as `max_tokens` to models that don't list `max_completion_tokens`.
        request.tokenLimitMember = lists(.maxCompletionTokens) ? .maxCompletionTokens : .maxTokens
        request.movedEffort = reasoning.movedEffort
        // A request that may reach a model whose structured outputs reject constraints sends the portable schema from
        // the start. Other hosts get the full schema, and the portable one only if they reject it. Either way, the
        // shared model checks the answer against the full schema.
        request.usesPortableSchema = model.modelIDs.contains(where: \.rejectsSchemaConstraints)
        // The cache mark on the last instructions caches the tools and instructions before it on the host, for the
        // session's later requests and for another session's that reach the same host.
        request.instructionsMark = try model.requestCacheControl.map {
            try JSONValueEncoder.members(of: InstructionsMark(cacheControl: $0.directive))
        }
    }

    /// The response cache's settings, the session id while the cache is on, the request for router metadata, which every
    /// request sends because only the router's report says a guardrail blocked it, and the app's name, address,
    /// categories and visibility.
    private func headers(firstPromptID: String?) -> [String: String] {
        var headers = model.responseCache?.headers(sessionID: Self.sessionID(firstPromptID)) ?? [:]
        headers[API.Header.routerMetadata] = "enabled"
        let categories = app.categories.prefix(OpenRouterApp.categoryLimit).map(\.rawValue)
        headers[API.Header.referer] = app.url?.absoluteString
        headers[API.Header.appTitle] = app.name
        headers[API.Header.appCategories] = categories.isEmpty ? nil : categories.joined(separator: ",")
        headers[API.Header.appVisibility] = app.isHidden ? "hidden" : nil
        return headers
    }

    /// The server tools' entries, or none when tool calls are disallowed.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` when there are server tools to send and the model or a
    ///   fallback doesn't take tools.
    private func serverTools(toolCallingMode: GenerationOptions.ToolCallingMode?) throws(LanguageModelError)
        -> [OpenRouterServerTool.Entry]
    {
        guard !model.serverTools.isEmpty, toolCallingMode?.kind != .disallowed else { return [] }
        guard lists(.tools) else {
            let description = "The model or one of its fallbacks doesn't take tools, so it can't call server tools."
            throw LanguageModelError.unsupported(.toolCalling, description)
        }
        return model.serverTools.map(\.entry)
    }

    /// The session's id: its first prompt's, up to the longest OpenRouter takes, or `nil` before the first prompt.
    private static func sessionID(_ firstPromptID: String?) -> String? {
        firstPromptID.map { String($0.prefix(sessionIDLimit)) }
    }

    /// The longest session id OpenRouter takes.
    private static var sessionIDLimit: Int { 256 }

    /// The reasoning setting: the nearest effort the model accepts, or for a model whose effort can't be chosen,
    /// whether to reason at all. `off` turns off the reasoning of a model that can stop reasoning even when `none`
    /// isn't among its efforts; a model that always reasons gets its nearest effort instead.
    ///
    /// - Returns: The setting, and the level asked for with the effort sent, when that effort isn't the level's own or
    ///   none is.
    private static func reasoning(
        _ level: ContextOptions.ReasoningLevel?,
        details: OpenRouterModel<some ModelEffort>
    ) -> (setting: Members.Reasoning?, movedEffort: MovedEffort?) {
        guard let level, details.reasoning.isSupported else { return (nil, nil) }
        let turnsOff = level == .off
        if details.reasoningEfforts.isEmpty {
            return (turnsOff && !details.reasoning.canBeTurnedOff ? nil : .enabled(!turnsOff), nil)
        }
        if turnsOff, details.reasoning.canBeTurnedOff, !details.reasoningEfforts.contains(where: { $0.reasoningLevel == .off }) {
            return (.enabled(false), nil)
        }
        let (effort, moved) = level.sentEffort(supporting: details.reasoningEfforts)
        return (effort.map(Members.Reasoning.effort), moved)
    }

    /// The output kinds to ask for: images and text when every model generates images and the request has no schema,
    /// so their images come back as data entries; otherwise none, which means text.
    ///
    /// Before the OS version that has data entries, and in a build with an SDK before Xcode 27.2's, images aren't
    /// asked for, since they couldn't reach the session.
    private static func modalities(_ outputs: Set<OpenRouterOutputModality>, hasSchema: Bool) -> [OpenRouterOutputModality]? {
        #if canImport(FoundationModels, _version: 2.1.14)
        guard #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *), !hasSchema, outputs.contains(.image) else {
            return nil
        }
        return outputs.contains(.text) ? [.image, .text] : [.image]
        #else
        return nil
        #endif
    }

    /// OpenRouter's plugins for a request: context compression, then the PDF engine when a message carries a PDF, then
    /// the settings of each router among the models, once each, in the order the models are tried.
    ///
    /// Context compression is off for every request, so the model sees the whole transcript, and one that doesn't fit
    /// throws `LanguageModelError.contextSizeExceeded`. Otherwise OpenRouter turns it on for hosts with 8,192 tokens of
    /// context or less, which a model listing more can still use, and for accounts that enable it, and it silently
    /// drops the middle of the transcript.
    private static func plugins(for ids: [OpenRouterModelID], options: OpenRouterOptions, carriesPDF: Bool) -> [Members.Plugin] {
        var plugins: [Members.Plugin] = [.contextCompression]
        if carriesPDF, let engine = options.pdfEngine {
            plugins.append(.fileParser(engine))
        }
        var seen: Set<OpenRouterModelID> = []
        plugins += ids.filter { seen.insert($0).inserted }.compactMap { router($0, options: options) }
        return plugins
    }

    /// The settings of a router model, under the plugin id that router reads, or `nil` for any other model or when
    /// the router has no settings. Each router silently ignores settings under another router's id.
    ///
    /// Routers are matched by id rather than by catalog entry, so a catalog update that retires one doesn't break
    /// the build.
    private static func router(_ id: OpenRouterModelID, options: OpenRouterOptions) -> Members.Plugin? {
        switch id {
        case .autoRouter: options.autoRouter.map { .autoRouter($0, plugin: .autoRouter) }
        case .autoBetaRouter: options.autoRouter.map { .autoRouter($0, plugin: .autoBetaRouter) }
        case .paretoCodeRouter: options.paretoRouter.map(Members.Plugin.paretoRouter)
        default: nil
        }
    }

    // MARK: While the answer streams

    /// Takes a chunk's facts, then the reasoning and images in its delta.
    ///
    /// The reasoning to show is the readable text of the delta's details, or its plain reasoning when it has no
    /// details, since an empty list carries no text; an empty list alone starts the reasoning entry.
    mutating func read(_ extras: OpenRouterChunkExtras) -> ChatCompletions.ChunkAdditions {
        if let provider = extras.provider {
            host = OpenRouterProviderName(rawValue: provider)
        }
        usage = extras.usage ?? usage
        if model.options.includesRouterMetadata { routerReport = extras.routerMetadata ?? routerReport }
        guard let delta = extras.choices?.first?.delta else { return ChatCompletions.ChunkAdditions() }
        if let details = delta.reasoningDetails {
            if reasoningDetails == nil { reasoningDetails = ReasoningDetails() }
            for detail in details { reasoningDetails?.append(detail) }
        }
        var additions = ChatCompletions.ChunkAdditions(imageURLs: (delta.images ?? []).compactMap(\.imageURL?.url))
        if let details = delta.reasoningDetails, !details.isEmpty {
            additions.reasoning = ReasoningDetails.readableText(in: details)
        } else if let reasoning = delta.reasoning, !reasoning.isEmpty {
            additions.reasoning = reasoning
        } else if delta.reasoningDetails != nil {
            additions.reasoning = ""
        }
        return additions
    }

    // MARK: When it ends, or fails

    /// The host, the response cache's report and the router's; the cost, its parts, whether the account's own key paid
    /// and the server tools' counts; and the reasoning details as the reasoning entry's signature.
    func additions(header: (String) -> String?) -> AnswerAdditions {
        var metadata = OpenRouterResponseCache.Report(header: header)?.metadata ?? [:]
        metadata.merge(routerReport?.metadata ?? [:]) { $1 }
        return AnswerAdditions(
            host: host?.rawValue, cost: usage?.cost.flatMap(Decimal.init(metadataNumber:)),
            webSearchCount: usage?.serverToolUseDetails?.webSearchRequests, metadata: metadata, usageMetadata: usage?.metadata ?? [:],
            reasoningSignature: reasoningDetails?.signature)
    }

    /// `LanguageModelError` for a failure Foundation Models has a case for, and `OpenRouterError` for the rest: with
    /// `invalidResponse` for a response the format couldn't use, naming the host unless an event couldn't be read, and
    /// with `server` for an answer that ended in the host's failure.
    func error(for failure: RequestFailure<OpenRouterErrorResponse>) -> any Error {
        switch failure.kind {
        case .rejected:
            OpenRouterFailure(failure).error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .errorEvent:
            OpenRouterFailure(streamError: failure.body ?? OpenRouterErrorResponse(message: failure.message), provider: host)
                .error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .unreadableEvent:
            OpenRouterError(message: failure.message, code: .invalidResponse)
        case .unusableAnswer:
            OpenRouterError(message: failure.message, code: .invalidResponse, provider: host)
        case .failedAnswer:
            OpenRouterError(message: failure.message, code: .server, provider: host)
        }
    }
}

// MARK: - Wire

/// The members of a streamed chunk that only OpenRouter sends, read from the same JSON as the format's own: the host,
/// the reasoning and images in the delta, the cost in the usage and the router's report. An error's members are read
/// as an `OpenRouterErrorResponse`.
///
/// Keys are listed one by one instead of converted from snake case, because a conversion would also rename the keys
/// inside `reasoning_details`, which go back to OpenRouter unchanged.
struct OpenRouterChunkExtras: Decodable {
    fileprivate struct Choice: Decodable {
        let delta: Delta?
    }

    fileprivate struct Delta: Decodable {
        let reasoning: String?
        let reasoningDetails: [JSONValue]?
        let images: [GeneratedImage]?

        private enum CodingKeys: String, CodingKey {
            case reasoning
            case reasoningDetails = "reasoning_details"
            case images
        }
    }

    /// An image the model generated, whole in one delta, usually as a data URL such as `data:image/png;base64,…`.
    fileprivate struct GeneratedImage: Decodable {
        struct ImageURL: Decodable {
            let url: String?
        }

        let imageURL: ImageURL?

        private enum CodingKeys: String, CodingKey {
            case imageURL = "image_url"
        }
    }

    /// What OpenRouter adds to the usage: the cost, its parts, whether the account's own key paid, and how often
    /// the server tools ran.
    struct Usage: Decodable {
        /// The parts of the cost, in US dollars.
        struct CostDetails: Decodable {
            let upstreamInferenceCost: Double?
            let upstreamInferencePromptCost: Double?
            let upstreamInferenceCompletionsCost: Double?
            let serverToolCost: Double?

            private enum CodingKeys: String, CodingKey {
                case upstreamInferenceCost = "upstream_inference_cost"
                case upstreamInferencePromptCost = "upstream_inference_prompt_cost"
                case upstreamInferenceCompletionsCost = "upstream_inference_completions_cost"
                case serverToolCost = "server_tool_cost"
            }
        }

        /// How often the server tools ran.
        struct ServerToolUseDetails: Decodable {
            let toolCallsRequested: Int?
            let toolCallsExecuted: Int?
            let webSearchRequests: Int?

            private enum CodingKeys: String, CodingKey {
                case toolCallsRequested = "tool_calls_requested"
                case toolCallsExecuted = "tool_calls_executed"
                case webSearchRequests = "web_search_requests"
            }
        }

        let cost: Double?
        let costDetails: CostDetails?
        let isBYOK: Bool?
        let serverToolUseDetails: ServerToolUseDetails?

        private enum CodingKeys: String, CodingKey {
            case cost
            case costDetails = "cost_details"
            case isBYOK = "is_byok"
            case serverToolUseDetails = "server_tool_use_details"
        }
    }

    /// What OpenRouter's router did for the request, on the last chunk or beside the error of a failed response. Every
    /// field is optional, since OpenRouter adds fields over time and leaves some out.
    struct RouterMetadata: Decodable {
        struct Endpoints: Decodable {
            struct Endpoint: Decodable {
                let provider: String?
                let model: String?
                let selected: Bool?
            }

            let available: [Endpoint]?
        }

        struct Attempt: Decodable {
            let provider: String?
            let model: String?
            let status: Int?
        }

        /// A plugin that changed the request or the answer.
        struct Stage: Decodable {
            let type: String?
            let name: String?
            let summary: String?
            /// The plugin's own details, which are free-form.
            let data: JSONValue?

            /// Whether the stage is a guardrail that blocked the request.
            var isGuardrailBlock: Bool { type == "guardrail" && data?["action"]?.stringValue == "blocked" }
        }

        let strategy: String?
        let attempt: Int?
        let attempts: [Attempt]?
        let endpoints: Endpoints?
        /// The milliseconds from sending the request to the host until its answer ended.
        let generationTime: Double?
        let region: String?
        let pipeline: [Stage]?

        /// Whether a guardrail blocked the request.
        var isGuardrailBlock: Bool { pipeline?.contains(where: \.isGuardrailBlock) == true }

        private enum CodingKeys: String, CodingKey {
            case strategy
            case attempt
            case attempts
            case endpoints
            case generationTime = "generation_time"
            case region
            case pipeline
        }
    }

    fileprivate let provider: String?
    fileprivate let choices: [Choice]?
    fileprivate let usage: Usage?
    fileprivate let routerMetadata: RouterMetadata?

    private enum CodingKeys: String, CodingKey {
        case provider
        case choices
        case usage
        case routerMetadata = "openrouter_metadata"
    }
}

/// OpenRouter's own members of a request's body: the fallback models, the output kinds, the settings only OpenRouter
/// takes, the routing, the plugins, the session id and the cache mark.
private struct Members: Encodable {
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
    fileprivate static let models: Self = "models"
    fileprivate static let modalities: Self = "modalities"
    fileprivate static let parallelToolCalls: Self = "parallel_tool_calls"
    fileprivate static let reasoning: Self = "reasoning"
    fileprivate static let topK: Self = "top_k"
    fileprivate static let frequencyPenalty: Self = "frequency_penalty"
    fileprivate static let presencePenalty: Self = "presence_penalty"
    fileprivate static let repetitionPenalty: Self = "repetition_penalty"
    fileprivate static let minP: Self = "min_p"
    fileprivate static let topA: Self = "top_a"
    fileprivate static let stop: Self = "stop"
    fileprivate static let logitBias: Self = "logit_bias"
    fileprivate static let verbosity: Self = "verbosity"
    fileprivate static let serviceTier: Self = "service_tier"
    fileprivate static let user: Self = "user"
    fileprivate static let provider: Self = "provider"
    fileprivate static let plugins: Self = "plugins"
    fileprivate static let sessionID: Self = "session_id"
    fileprivate static let cacheControl: Self = "cache_control"
}

/// The cache mark on the last content part of the last instructions.
private struct InstructionsMark: Encodable {
    let cacheControl: OpenRouterCacheControl.Directive

    private enum CodingKeys: String, CodingKey {
        case cacheControl = "cache_control"
    }
}

extension OpenRouterModelID {
    /// The router models that take settings.
    fileprivate static let autoRouter: Self = "openrouter/auto"
    fileprivate static let autoBetaRouter: Self = "openrouter/auto-beta"
    fileprivate static let paretoCodeRouter: Self = "openrouter/pareto-code"
}

extension OpenRouterOptions.ParallelToolCalls {
    /// The `parallel_tool_calls` value, or `nil` to leave the choice to the host.
    fileprivate var value: Bool? {
        switch self {
        case .automatic: nil
        case .allowed: true
        case .disallowed: false
        }
    }
}

extension OpenRouterInputModality {
    /// The kinds of audio and movies OpenRouter takes beyond the format's, each with its part: audio in the formats only
    /// OpenRouter takes, as `input_audio` with its format, then movies, as `video_url` data URLs, each in the order
    /// OpenRouter's kinds are matched.
    fileprivate static var media: [ChatCompletions.MediaPart] {
        let audio = audioTypes.compactMap { type in audioNames[type].map { ChatCompletions.MediaPart.audio(type, format: $0) } }
        let video = videoTypes.compactMap { type in videoNames[type].map { ChatCompletions.MediaPart.video(type, mediaType: $0) } }
        return audio + video
    }

    /// OpenRouter's `input_audio` format for each kind of audio it takes beyond WAV and MP3, which the format names.
    private static var audioNames: [UTType?: String] {
        [
            .aiff: "aiff", .mpeg4Audio: "m4a", UnnamedType.aacAudio: "aac", UnnamedType.flacAudio: "flac", UnnamedType.oggAudio: "ogg",
        ]
    }

    /// The media type OpenRouter names each kind of movie by in a `video_url` data URL.
    private static var videoNames: [UTType?: String] {
        [
            .mpeg4Movie: "video/mp4", .mpeg: "video/mpeg", .quickTimeMovie: "video/mov", UnnamedType.webMMovie: "video/webm",
        ]
    }
}
