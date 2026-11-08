import Foundation
import FoundationModels
import LanguageModels
import UniformTypeIdentifiers

// MARK: - As a Responses model

extension OpenAILanguageModel {
    /// This model as a Responses model: what is true for every request, and OpenAI's part in each.
    ///
    /// - Parameter configuration: Where requests go and how they're sent.
    /// - Returns: The model.
    /// - Throws: `OpenAIError` with `invalidRequest` when there's no valid base URL.
    func responses(_ configuration: Executor.Configuration) throws(OpenAIError) -> Responses.Model<OpenAIExchange> {
        let exchange = OpenAIExchange(model: OpenAILanguageModel<ContextOptions.ReasoningLevel>(self))
        var model = Responses.Model(
            name: details.id.rawValue, url: try API.baseURL(configuration.baseURL), connection: connection(configuration.settings),
            providerName: API.name, images: configuration.settings.images, reasoningOrigin: API.reasoningOrigin,
            phasesKey: OpenAIResponseMetadata.phasesKey, serverToolsKey: OpenAIResponseMetadata.serverToolsKey, capabilities: capabilities,
            reaching: [details] + fallbacks, exchange: exchange)
        model.unsupportedMembers = OpenAIExchange.listedMembers.filter { !exchange.lists($0) }
        // `developer` for a model that reasons, and `system` for one that doesn't, as models before reasoning models take
        // instructions.
        model.instructionsRole = details.reasoning.isSupported ? .developer : .system
        return model
    }
}

// MARK: - Exchange

/// OpenAI's part in one exchange: the reasoning effort and summary, the storage, the options only OpenAI has, the server
/// tools, the settings each model takes, the reasoning items that go back on later turns, the request id, and what
/// OpenAI's failures become.
///
/// Every method with a default is here, in the type that declares the conformance, so a misspelled one draws a warning
/// instead of silently keeping the default.
struct OpenAIExchange: Responses.Exchange {
    /// The model.
    fileprivate let model: OpenAILanguageModel<ContextOptions.ReasoningLevel>

    /// The model's details.
    private var details: OpenAIModel<ContextOptions.ReasoningLevel> { model.details }

    /// The settings that go out only to models that take them.
    fileprivate static let listedMembers: Set<Responses.Member> = [
        .temperature, .topP, .maxOutputTokens, .tools, .toolChoice, .reasoning, Members.parallelToolCallsKey,
    ]

    /// Whether the model takes a setting, which the catalog names as the body does.
    fileprivate func lists(_ member: Responses.Member) -> Bool {
        details.supportedParameters.contains(OpenAIParameter(rawValue: member.rawValue))
    }

    // MARK: While the request is read

    /// Checks that the model takes an attachment, as Foundation Models does before a request.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` with `.vision` for an image when the model doesn't take
    ///   images, and `LanguageModelError.unsupportedTranscriptContent` for data of a kind the model doesn't take.
    func checkAttachment(_ kind: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {
        switch kind {
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

    /// Whether OpenAI's reasoning goes back: only when this model wrote it, or a dated snapshot of this model did,
    /// since encrypted reasoning suits only that model. Reasoning that names no writer goes back too.
    func replays(_ reasoning: Transcript.Reasoning) -> Bool {
        reasoning.writer.map(details.id.names) ?? true
    }

    // MARK: Before it is sent

    /// Adds OpenAI's members and server tools, sets the format's reasoning, storage, `include` and `text` members, and
    /// leaves out each setting the model doesn't take with the request.
    ///
    /// A model that reasons takes `temperature` and `top_p` only while its effort is `none`, so a request that sets
    /// another effort, or goes to a model that always reasons, leaves them out. A request that sets no effort for a
    /// model that can stop reasoning sends them as the app set them, since the catalog's default effort doesn't always
    /// match the model's own: GPT-5.4 mini takes them, although its catalog default is `medium`. Every request of a
    /// model that reasons asks for its reasoning encrypted, so its reasoning items go back on later turns whether or
    /// not OpenAI keeps the response.
    ///
    /// The server tools go after the session's tools, unless tool calls are disallowed, and the answer keeps their calls,
    /// so they go back on later turns. A web search that lists its sources asks for them in `include`, after the
    /// encrypted reasoning.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` when a call to the session's tools is required and the model
    ///   doesn't take tools, when there are server tools to send and the model doesn't take tools, when one generates
    ///   images where no image could arrive, or when the request has a response schema and the model doesn't take
    ///   structured outputs.
    func prepare(_ request: inout Responses.Request) throws {
        let options = model.options
        let generation = request.generation
        let sendsSessionTools = request.hasSessionTools && lists(.tools)
        if request.hasSessionTools, !sendsSessionTools, generation.generationOptions.toolCallingMode?.kind == .required {
            throw LanguageModelError.unsupported(.toolCalling, "The model doesn't take tools, so it can't be made to call one.")
        }
        let serverTools = try serverTools(toolCallingMode: generation.generationOptions.toolCallingMode)
        if generation.schema != nil, !details.supportedParameters.contains(.structuredOutputs) {
            throw LanguageModelError.unsupported(
                .guidedGeneration, "The model doesn't take structured outputs, so it can't hold its answer to a schema.")
        }
        let (effort, movedEffort) = reasoningEffort(generation.contextOptions.reasoningLevel)
        request.members = try JSONValueEncoder.members(
            of: Members(
                // The parallel calls concern only the session's tools.
                parallelToolCalls: sendsSessionTools ? options.parallelToolCalls.value : nil,
                serviceTier: options.serviceTier,
                promptCacheKey: options.cacheKey.flatMap { Self.cacheKey($0, firstPromptID: request.firstPromptID) },
                safetyIdentifier: options.endUserID,
                // The limit concerns only the server tools.
                maximumToolCalls: serverTools.isEmpty ? nil : options.maximumServerToolCalls
            ))
        request.sendsSessionTools = sendsSessionTools
        request.serverTools = try serverTools.map { try JSONValueEncoder.encode($0) }
        request.serverToolCalls = Set(serverTools.map(\.call))
        request.storage = options.storage.storage
        if let verbosity = options.verbosity {
            request.textMembers = try JSONValueEncoder.members(of: TextMembers(verbosity: verbosity))
        }
        request.movedEffort = movedEffort
        if details.reasoning.isSupported {
            request.reasoning = Responses.Request.Reasoning(effort: effort, summary: options.reasoningSummary?.rawValue)
            request.include = [.encryptedReasoning]
            let reasons = effort.map { $0 != ContextOptions.ReasoningLevel.off.effortWord } ?? (details.reasoning == .mandatory)
            if reasons { request.leftOutMembers = [.temperature, .topP] }
        }
        for value in serverTools.flatMap(\.include) where !request.include.contains(value) {
            request.include.append(value)
        }
    }

    /// The server tools' entries, or none when tool calls are disallowed.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` when there are server tools to send and the model doesn't
    ///   take tools, or when one generates images where no image could arrive: before OS 27.2, or in an app built
    ///   without Xcode 27.2's SDK.
    private func serverTools(toolCallingMode: GenerationOptions.ToolCallingMode?) throws(LanguageModelError)
        -> [OpenAIServerTool.Entry]
    {
        guard !model.serverTools.isEmpty, toolCallingMode?.kind != .disallowed else { return [] }
        guard lists(.tools) else {
            throw LanguageModelError.unsupported(.toolCalling, "The model doesn't take tools, so it can't call server tools.")
        }
        let entries = model.serverTools.map(\.entry)
        if !Self.receivesGeneratedData, entries.contains(where: { $0.generatedFormat != nil }) {
            throw LanguageModelError.unsupported(
                .toolCalling, "Generated images arrive as data entries, which need OS 27.2 and an app built with Xcode 27.2's SDK.")
        }
        return entries
    }

    /// Whether an answer can carry data the model generates, such as an image: from OS 27.2, in an app built with Xcode
    /// 27.2's SDK.
    private static var receivesGeneratedData: Bool {
        #if canImport(FoundationModels, _version: 2.1.14)
        if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) { return true }
        #endif
        return false
    }

    /// The effort to send for a reasoning level, which is the nearest the model accepts, and the move the request logs
    /// when that effort isn't the level's own or none is sent.
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

    // MARK: When it ends, or fails

    /// The request's id, on the entry that ends the answer.
    func additions(header: (String) -> String?) -> AnswerAdditions {
        AnswerAdditions(requestID: header(API.Header.requestID))
    }

    /// What a failure becomes: `LanguageModelError` for a rate limit, an oversized context, a safety system, a timeout
    /// or an image OpenAI can't use, and `OpenAIError` otherwise, such as for a quota that ran out, with
    /// `invalidResponse` for a stream the format couldn't use.
    func error(for failure: RequestFailure<APIErrorBody>) -> any Error {
        let requestID = failure.header(API.Header.requestID)
        switch failure.kind {
        case .rejected:
            return OpenAIFailure(failure).error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .errorEvent, .failedAnswer:
            return OpenAIFailure(streamError: failure.body, requestID: requestID)
                .error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .unreadableEvent, .unusableAnswer:
            return OpenAIError(message: failure.message, code: .invalidResponse, requestID: requestID)
        }
    }
}

// MARK: - Wire

/// The members of a Responses request that only OpenAI's options set, each left out when the option keeps OpenAI's
/// default.
private struct Members: Encodable {
    let parallelToolCalls: Bool?
    let serviceTier: OpenAIServiceTier?
    let promptCacheKey: String?
    let safetyIdentifier: String?
    let maximumToolCalls: Int?

    private enum CodingKeys: String, CodingKey {
        case parallelToolCalls = "parallel_tool_calls"
        case serviceTier = "service_tier"
        case promptCacheKey = "prompt_cache_key"
        case safetyIdentifier = "safety_identifier"
        case maximumToolCalls = "max_tool_calls"
    }

    /// The key of `parallel_tool_calls`, which goes out only to models that take tools.
    static let parallelToolCallsKey = Responses.Member(rawValue: CodingKeys.parallelToolCalls.rawValue)
}

/// The members OpenAI adds to `text`: how long and detailed the answer is.
private struct TextMembers: Encodable {
    let verbosity: OpenAIOptions.Verbosity
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
    fileprivate var storage: Responses.Request.Storage {
        switch self {
        case .automatic: .automatic
        case .stored: .stored
        case .notStored: .notStored
        }
    }
}
