import Foundation
import FoundationModels
import LanguageModels
import UniformTypeIdentifiers

/// OpenAI's dialect of the Responses format: the reasoning effort and summary, the storage, the options only OpenAI
/// has, the settings each model takes, the reasoning items that go back on later turns, the request id, and what
/// OpenAI's failures become.
///
/// The format's executor creates one for each request, from the model and its request executor, and does the rest.
///
/// Every hook with a default is in the extension that declares the conformance, so a misspelled one draws a warning
/// instead of silently keeping the default; the hooks of OpenAI's own types have no default to fall back to.
struct OpenAIResponses<Effort: ModelEffort> {
    /// The model.
    let model: OpenAILanguageModel<ContextOptions.ReasoningLevel>

    /// Where requests go and how long they wait.
    let configuration: OpenAILanguageModel<ContextOptions.ReasoningLevel>.RequestExecutor.Configuration

    init(model: OpenAILanguageModel<Effort>, executor: OpenAILanguageModel<Effort>.RequestExecutor) {
        self.model = OpenAILanguageModel(model)
        configuration = .init(executor.configuration)
    }

    /// The model's details.
    var details: OpenAIModel<ContextOptions.ReasoningLevel> { model.details }
}

extension OpenAIResponses: ResponsesDialect {
    typealias Model = OpenAILanguageModel<Effort>
    typealias ProviderError = OpenAIError
    typealias BodyExtras = OpenAIBodyExtras
    typealias StreamState = OpenAIStreamState

    static var name: String { API.name }

    static var reasoningOrigin: ReasoningOrigin { .openAIResponses }

    static var phasesMetadataKey: String { OpenAIMetadataKey.phases }

    /// The settings that go out only to models that take them.
    static var listedMembers: Set<Responses.Member> {
        [.temperature, .topP, .maxOutputTokens, .tools, .toolChoice, .reasoning, OpenAIBodyExtras.parallelToolCallsKey]
    }

    var modelID: OpenAIModelID { details.id }

    var baseURL: URL {
        get throws(OpenAIError) { try API.baseURL(configuration.baseURL) }
    }

    var connection: ProviderConnection { model.connection(configuration.settings) }

    var imageEncoding: ImageEncoding { configuration.settings.images }

    /// `developer` for a model that reasons, and `system` for one that doesn't, as models before reasoning models take
    /// instructions.
    var instructionsRole: InstructionsRole { details.reasoning.isSupported ? .developer : .system }

    /// Whether the model takes a setting, which the catalog names as the body does.
    func lists(_ member: Responses.Member) -> Bool {
        details.supportedParameters.contains(OpenAIParameter(rawValue: member.rawValue))
    }

    /// Checks that the model takes an attachment, as Foundation Models does before a request.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` with `.vision` for an image when the model doesn't take
    ///   images, and `LanguageModelError.unsupportedTranscriptContent` for data of a kind the model doesn't take.
    func check(_ attachment: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {
        switch attachment {
        case .image:
            guard details.inputModalities.contains(.image) else {
                throw LanguageModelError.unsupported(.vision, "The model doesn't take images.")
            }
        case .data(let type):
            guard let input = OpenAIInputModality(carrying: type), details.inputModalities.contains(input) else {
                throw LanguageModelError.unsupported(entry, "The model doesn't take attachments of type \(type.identifier).")
            }
        }
    }

    /// Whether OpenAI's reasoning goes back: only to the model that wrote it, or to the model it's a dated snapshot
    /// of, since encrypted reasoning suits only that model.
    func replays(_ reasoning: Transcript.Reasoning) -> Bool {
        reasoning.writer.map(details.id.names) ?? true
    }
}

extension OpenAIResponses {
    /// OpenAI's members and the format's reasoning, storage and `text` members, with each setting the model doesn't
    /// take with the request left out.
    ///
    /// A model that reasons takes `temperature` and `top_p` only while its effort is `none`, so a request that sets
    /// another effort, or goes to a model that always reasons, leaves them out. A request that sets no effort for a
    /// model that can stop reasoning sends them as the app set them, as the official SDKs do, since the catalog's
    /// default effort doesn't always match the model's own: GPT-5.4 mini takes them, although its catalog default is
    /// `medium`. Every request of a model that reasons asks for its reasoning encrypted, so its reasoning items go
    /// back on later turns whether or not OpenAI keeps the response.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` when tool calls are required and the model doesn't take
    ///   tools, or when the request has a response schema and the model doesn't take structured outputs.
    func body(_ context: BodyContext) throws(LanguageModelError) -> ResponsesBodyPlan<BodyExtras> {
        let options = model.options
        let sendsSessionTools = context.hasSessionTools && lists(.tools)
        if context.hasSessionTools, !sendsSessionTools, context.toolCallingMode?.kind == .required {
            throw LanguageModelError.unsupported(.toolCalling, "The model doesn't take tools, so it can't be made to call one.")
        }
        if context.hasSchema, !details.supportedParameters.contains(.structuredOutputs) {
            throw LanguageModelError.unsupported(
                .guidedGeneration, "The model doesn't take structured outputs, so it can't hold its answer to a schema.")
        }
        let (effort, movedEffort) = reasoningEffort(context.reasoningLevel)
        var plan = ResponsesBodyPlan(
            extras: BodyExtras(
                // The parallel calls concern only the session's tools.
                parallelToolCalls: sendsSessionTools ? options.parallelToolCalls.value : nil,
                serviceTier: options.serviceTier,
                promptCacheKey: options.cacheKey.flatMap { Self.cacheKey($0, firstPromptID: context.firstPromptID) },
                safetyIdentifier: options.endUserID
            ))
        plan.sessionTools = sendsSessionTools ? .sent : .leftOut
        plan.storage = options.storage.planned
        plan.textExtras = options.verbosity.map(OpenAITextExtras.init)
        plan.movedEffort = movedEffort
        if details.reasoning.isSupported {
            plan.reasoning = ResponsesBodyPlan.Reasoning(effort: effort, summary: options.reasoningSummary?.rawValue)
            plan.asksForEncryptedReasoning = true
            let reasons = effort.map { $0 != ContextOptions.ReasoningLevel.off.effortWord } ?? (details.reasoning == .mandatory)
            if reasons { plan.leftOutMembers = [.temperature, .topP] }
        }
        return plan
    }

    /// The effort to send for a reasoning level: the nearest the model accepts, and the level with the effort sent
    /// when that effort isn't the level's own or none is.
    private func reasoningEffort(_ level: ContextOptions.ReasoningLevel?) -> (String?, MovedEffort?) {
        guard let level, details.reasoning.isSupported else { return (nil, nil) }
        return level.sentEffort(supporting: details.reasoningEfforts)
    }

    /// The cache key's text: the session's first prompt's id, or the app's own key; `nil` before the first prompt.
    private static func cacheKey(_ key: OpenAIOptions.CacheKey, firstPromptID: String?) -> String? {
        switch key.kind {
        case .session: firstPromptID
        case .named(let name): name
        }
    }
}

extension OpenAIOptions.ParallelToolCalls {
    /// The `parallel_tool_calls` value, or `nil` to leave the choice to OpenAI.
    fileprivate var value: Bool? {
        switch self {
        case .automatic: nil
        case .allowed: true
        case .disallowed: false
        }
    }
}

extension OpenAIOptions.Storage {
    /// The format's storage for the option.
    fileprivate var planned: ResponsesBodyPlan<OpenAIBodyExtras>.Storage {
        switch self {
        case .automatic: .automatic
        case .stored: .stored
        case .notStored: .notStored
        }
    }
}
