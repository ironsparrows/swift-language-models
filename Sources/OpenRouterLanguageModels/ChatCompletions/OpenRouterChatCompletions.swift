import Foundation
import FoundationModels
import LanguageModels

/// OpenRouter's dialect of the Chat Completions format: the fallback models, routing, plugins, server tools, session
/// id and cache marks its requests add, the parameters its models list, the headers that name the app, and the
/// reasoning, images, costs and errors its chunks carry.
///
/// The format's executor creates one for each request, from the model and its request executor, and does the rest.
///
/// Every hook with a default is in the extension that declares the conformance, so a misspelled one draws a warning
/// instead of silently keeping the default; the hooks of OpenRouter's own types have no default to fall back to.
struct OpenRouterChatCompletions<Effort: ModelEffort> {
    /// The model and its fallbacks.
    let model: OpenRouterLanguageModel<ContextOptions.ReasoningLevel>

    /// The model's details narrowed to what each fallback also supports.
    let details: OpenRouterModel<ContextOptions.ReasoningLevel>

    /// Where requests go and how they name the app.
    let configuration: OpenRouterLanguageModel<ContextOptions.ReasoningLevel>.RequestExecutor.Configuration

    init(model: OpenRouterLanguageModel<Effort>, executor: OpenRouterLanguageModel<Effort>.RequestExecutor) {
        self.model = OpenRouterLanguageModel(model)
        details = model.sharedDetails
        configuration = .init(executor.configuration)
    }
}

extension OpenRouterChatCompletions: ChatCompletionsDialect {
    typealias Model = OpenRouterLanguageModel<Effort>
    typealias ErrorBody = OpenRouterErrorResponse
    typealias ProviderError = OpenRouterError
    typealias BodyExtras = OpenRouterBodyExtras
    typealias ReplayMembers = OpenRouterReplayMembers
    typealias ChunkExtras = OpenRouterChunkExtras
    typealias StreamState = OpenRouterStreamState

    static var name: String { API.name }

    static var reasoningOrigin: ReasoningOrigin { .openRouter }

    var modelID: OpenRouterModelID { model.routing.modelID(for: model.details.id) }

    var baseURL: URL {
        get throws(OpenRouterError) { try API.baseURL(configuration.baseURL) }
    }

    var connection: Connection { model.connection(configuration.settings) }

    var imageEncoding: ImageEncoding { configuration.settings.images }

    static var memberOrder: [ChatCompletions.Member] { ChatCompletions.Member.openRouterOrder }

    static var listedMembers: Set<ChatCompletions.Member> { ChatCompletions.Member.openRouterListed }

    /// The response cache's settings, the session id while the cache is on, the request for router metadata, which every
    /// request sends because only the router's report says a guardrail blocked it, and the app's name, address,
    /// categories and visibility.
    func headers(_ context: HeaderContext) -> [HTTPHeaderName: String] {
        var headers = model.responseCache?.headers(sessionID: Self.sessionID(context.firstPromptID)) ?? [:]
        headers[API.Header.routerMetadata] = "enabled"
        let app = configuration.app
        let categories = app.categories.prefix(OpenRouterApp.categoryLimit).map(\.rawValue)
        headers[API.Header.referer] = app.url?.absoluteString
        headers[API.Header.appTitle] = app.name
        headers[API.Header.appCategories] = categories.isEmpty ? nil : categories.joined(separator: ",")
        headers[API.Header.appVisibility] = app.isHidden ? "hidden" : nil
        return headers
    }

    /// Whether the model and each fallback list a parameter, which OpenRouter names as the body does.
    func lists(_ member: ChatCompletions.Member) -> Bool {
        details.supportedParameters.contains(OpenRouterParameter(rawValue: member.rawValue))
    }

    /// Checks that every model takes an attachment, as Foundation Models does before a request.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` with `.vision` for an image attachment when a model doesn't
    ///   take images, and `LanguageModelError.unsupportedTranscriptContent` for a data attachment a model doesn't take,
    ///   images included, as `supportsDataAttachmentType` refuses it.
    func check(_ attachment: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {
        try checkAttachment(attachment, in: entry)
    }

    /// Audio in the formats only OpenRouter takes, as `input_audio` with its format, then movies, as `video_url` data
    /// URLs, each in the order OpenRouter's kinds are matched.
    static var extraMedia: [MediaPart] { openRouterMedia }

    /// Whether OpenRouter's reasoning goes back: only to the model that wrote it.
    func replays(_ reasoning: Transcript.Reasoning) -> Bool {
        model.replaysReasoning(writtenBy: reasoning.writer)
    }
}

extension OpenRouterChatCompletions {
    /// OpenRouter's members, and each setting that the model or a fallback doesn't list left out.
    ///
    /// A model's list holds every parameter any of its hosts takes, so with tools or a schema, when the request asks
    /// for hosts that take all it sends, each setting sent also narrows its hosts.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` when tool calls are required and a model doesn't take
    ///   `tool_choice`, when there are server tools and a model doesn't take tools, and for a schema when a model
    ///   doesn't take structured outputs.
    func body(_ context: BodyContext) throws(LanguageModelError) -> ChatCompletionsBodyPlan<BodyExtras> {
        let options = model.options
        // A model that doesn't take tools gets none of the session's, and requiring a call needs `tool_choice`, the
        // only way to require one.
        let sendsSessionTools = context.hasSessionTools && lists(.tools)
        if sendsSessionTools, context.toolCallingMode?.kind == .required, !lists(.toolChoice) {
            let description = "The model or one of its fallbacks doesn't take tool_choice, so it can't be made to call a tool."
            throw LanguageModelError.unsupported(.toolCalling, description)
        }
        let serverTools = try serverTools(toolCallingMode: context.toolCallingMode)
        if context.hasSchema, !details.supportedParameters.contains(.structuredOutputs) {
            let description = "The model or one of its fallbacks doesn't take structured outputs, so it can't hold its answer to a schema."
            throw LanguageModelError.unsupported(.guidedGeneration, description)
        }
        let needsParameters = sendsSessionTools || !serverTools.isEmpty || context.hasSchema
        let sampling = context.sampling
        // A request with tools or a schema needs hosts that take every parameter it sends, so greedy sampling's `top_k`
        // 1 goes only with requests that have neither, to models that list it.
        let greedyTopK = sampling.isGreedy && !needsParameters && lists(.topK) ? 1 : nil
        let reasoning = Self.reasoning(context.reasoningLevel, details: details)
        let fallbackIDs = model.fallbacks.map { model.routing.modelID(for: $0.id) }
        let extras = BodyExtras(
            models: fallbackIDs.isEmpty ? nil : fallbackIDs,
            modalities: Self.modalities(details.outputModalities, hasSchema: context.hasSchema),
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
            logitBias: options.logitBias.map(BodyExtras.LogitBias.init),
            verbosity: options.verbosity,
            serviceTier: options.serviceTier,
            user: options.endUserID,
            provider: model.routing.member(needsParameters: needsParameters),
            plugins: Self.plugins(for: model.modelIDs, options: options, carriesPDF: context.carriesPDF),
            // The response cache compares the whole body, and the session id differs for every session, so it goes in a
            // header while the cache is on, and new sessions can repeat an earlier request.
            sessionID: model.responseCache == nil ? Self.sessionID(context.firstPromptID) : nil,
            cacheControl: model.requestCacheControl?.directive
        )
        var plan = ChatCompletionsBodyPlan(extras: extras)
        plan.sessionTools = sendsSessionTools ? .sent : .leftOut
        plan.serverTools = serverTools
        // The token limit goes as `max_tokens` to models that don't list `max_completion_tokens`.
        plan.tokenLimit = lists(.maxCompletionTokens) ? .maxCompletionTokens : .maxTokens
        plan.movedEffort = reasoning.movedEffort
        // A request that may reach a model whose structured outputs reject constraints sends the portable schema from
        // the start. Other hosts get the full schema, and the portable one only if they reject it. Either way, the
        // model's executor checks the answer against the full schema.
        plan.schema = model.modelIDs.contains(where: \.rejectsSchemaConstraints) ? .portable : .full
        // The cache mark on the last instructions caches the tools and instructions before it on the host, for the
        // session's later requests and for another session's that reach the same host.
        plan.instructionsMark = model.requestCacheControl.map { InstructionsMark(cacheControl: $0.directive) }
        return plan
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
    ) -> (setting: BodyExtras.Reasoning?, movedEffort: MovedEffort?) {
        guard let level, details.reasoning.isSupported else { return (nil, nil) }
        let turnsOff = level == .off
        if details.reasoningEfforts.isEmpty {
            return (turnsOff && !details.reasoning.canBeTurnedOff ? nil : .enabled(!turnsOff), nil)
        }
        if turnsOff, details.reasoning.canBeTurnedOff, !details.reasoningEfforts.contains(where: { $0.reasoningLevel == .off }) {
            return (.enabled(false), nil)
        }
        let (effort, moved) = level.sentEffort(supporting: details.reasoningEfforts)
        return (effort.map(BodyExtras.Reasoning.effort), moved)
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
    private static func plugins(for ids: [OpenRouterModelID], options: OpenRouterOptions, carriesPDF: Bool) -> [BodyExtras.Plugin] {
        var plugins: [BodyExtras.Plugin] = [.contextCompression]
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
    private static func router(_ id: OpenRouterModelID, options: OpenRouterOptions) -> BodyExtras.Plugin? {
        switch id {
        case .autoRouter: options.autoRouter.map { .autoRouter($0, plugin: .autoRouter) }
        case .autoBetaRouter: options.autoRouter.map { .autoRouter($0, plugin: .autoBetaRouter) }
        case .paretoCodeRouter: options.paretoRouter.map(BodyExtras.Plugin.paretoRouter)
        default: nil
        }
    }
}

extension OpenRouterChatCompletions {
    /// The cache mark on the last content part of the last instructions.
    private struct InstructionsMark: Encodable, Sendable {
        let cacheControl: OpenRouterCacheControl.Directive

        private enum CodingKeys: String, CodingKey {
            case cacheControl = "cache_control"
        }
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
