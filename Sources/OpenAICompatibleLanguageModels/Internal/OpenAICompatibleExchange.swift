import Foundation
import FoundationModels
import LanguageModels
import UniformTypeIdentifiers

// MARK: - As a Chat Completions or Responses model

extension OpenAICompatibleLanguageModel {
    /// This model as a Chat Completions model: what is true for every request, and the provider's part in each.
    ///
    /// - Parameter configuration: Where requests go and how they're sent.
    /// - Returns: The model.
    func chatCompletions(_ configuration: Executor.Configuration) -> ChatCompletions.Model<OpenAICompatibleExchange> {
        let provider = configuration.provider
        var model = ChatCompletions.Model(
            name: details.id.rawValue, url: configuration.baseURL, connection: connection(configuration), providerName: provider.name,
            images: configuration.settings.images,
            reasoningOrigin: API.reasoningOrigin(provider: provider.reasoningName, format: .chatCompletions), capabilities: capabilities,
            reaching: [details] + fallbacks, exchange: OpenAICompatibleExchange(model: self))
        model.memberOrder = OpenAICompatibleExchange.memberOrder
        model.unsupportedMembers = provider.unsupportedMembers
        model.finishReasons = provider.finishReasons
        return model
    }

    /// This model as a Responses model: what is true for every request, and the provider's part in each.
    ///
    /// - Parameter configuration: Where requests go and how they're sent.
    /// - Returns: The model.
    func responses(_ configuration: Executor.Configuration) -> Responses.Model<OpenAICompatibleExchange> {
        let provider = configuration.provider
        return Responses.Model(
            name: details.id.rawValue, url: configuration.baseURL, connection: connection(configuration), providerName: provider.name,
            images: configuration.settings.images,
            reasoningOrigin: API.reasoningOrigin(provider: provider.reasoningName, format: .responses),
            phasesKey: OpenAICompatibleResponseMetadata.phasesKey, serverToolsKey: OpenAICompatibleResponseMetadata.serverToolsKey,
            capabilities: capabilities, reaching: [details] + fallbacks, exchange: OpenAICompatibleExchange(model: self))
    }
}

// MARK: - Exchange

/// A provider's part in one exchange, in either format: the attachments the model takes, the requests the provider
/// refuses, the reasoning effort, the usage chunk and the token limit's member it asks for, the app's own members, the
/// storage, the reasoning that goes back, the reasoning and thought signature in each chunk, the host and request id,
/// and what the provider's failures become.
///
/// Every method with a default is here, in the type that declares the conformances, so a misspelled one draws a warning
/// instead of silently keeping the default, and neither format's default is picked over the other's.
struct OpenAICompatibleExchange: ChatCompletions.Exchange, Responses.Exchange {
    /// The model's details, with its provider.
    private let details: OpenAICompatibleModel

    /// The app's request settings.
    private let options: OpenAICompatibleOptions

    /// The thought signatures the answer's chunks carried so far.
    private var signatures = ThoughtSignatures()

    /// The order of a Chat Completions request's members, which never changes, since a provider's prompt cache depends
    /// on it. An app's member of a key the module writes takes that member's place, and the others go after them,
    /// sorted by key.
    fileprivate static let memberOrder: [ChatCompletions.Member] = [
        .model, .messages, .stream, .streamOptions, .tools, .toolChoice, .responseFormat, .reasoningEffort, .thinking, .temperature,
        .topP, .seed, .maxCompletionTokens, .maxTokens, .metadata,
    ]

    fileprivate init(model: OpenAICompatibleLanguageModel) {
        details = model.details
        options = model.options
    }

    /// The provider the model runs on.
    private var provider: OpenAICompatibleProvider {
        details.provider
    }

    // MARK: While the request is read

    /// Checks that the model takes an attachment, as Foundation Models does before a request.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` with `.vision` for an image when the model doesn't take
    ///   images, and `LanguageModelError.unsupportedTranscriptContent` for data of a kind the model doesn't take.
    func checkAttachment(_ kind: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {
        switch kind {
        case .image:
            guard details.capabilities.contains(.vision) else {
                throw LanguageModelError.unsupported(.vision, "The model doesn't take images.")
            }
        case .data(let type):
            guard details.supportsDataAttachmentType(type) else {
                throw LanguageModelError.unsupported(entry, "The model doesn't take attachments of type \(type.identifier).")
            }
        }
    }

    /// Whether the provider's own reasoning goes back on later turns: in Responses, as the answer's `reasoning` items,
    /// only to the model that wrote it, or to the model it's a dated version of, and when it names no writer; in Chat
    /// Completions, as the provider reads it back, in a member of its own or as its thought signature, to any of its
    /// models or only to the one that wrote it.
    func replays(_ reasoning: Transcript.Reasoning) -> Bool {
        let toWriter = reasoning.writer.map(details.id.names) ?? true
        switch provider.format {
        case .chatCompletions:
            switch provider.reasoningReplay {
            case .notSent: return false
            case .reasoningContent: return true
            case .reasoning, .thoughtSignatures: return toWriter
            }
        case .responses:
            return toWriter
        }
    }

    /// The members an answer goes back with, as its provider reads them: its reasoning in a member of the provider's,
    /// or its thought signature on its first tool call or its message.
    func replayMembers(for answer: ChatCompletions.ReplayedAnswer) -> ChatCompletions.ReplayMembers {
        provider.reasoningReplay.members(for: answer)
    }

    // MARK: Before it is sent

    /// Asks for a usage chunk unless the provider reports usage unasked, sends the token limit in the provider's member
    /// and the reasoning effort as `reasoning_effort`, with `thinking` for a provider that takes it, and adds the app's
    /// own members over the format's.
    ///
    /// A request that sets a reasoning level sends the nearest effort the model accepts, for a model that reasons, and
    /// to a provider that takes `thinking`, `thinking` too: disabled for the level `off` and for a model that doesn't
    /// reason, and enabled for any other level. An app member `reasoning_effort` replaces the effort and goes without
    /// the provider's `thinking`, and an app member `thinking` replaces the provider's. A moved effort is logged unless
    /// the app's members carry the effort or the model doesn't reason for the request.
    ///
    /// - Throws: `LanguageModelError.unsupportedCapability` with `.guidedGeneration` for a schema sent with tools to a
    ///   provider that refuses the two together, and with `.toolCalling` for a required tool call while the model
    ///   reasons, to a provider that takes one only with reasoning off.
    func prepare(_ request: inout ChatCompletions.Request) throws {
        let generation = request.generation
        if provider.refusesSchemaWithTools, generation.schema != nil, request.hasSessionTools {
            let description = "\(provider.name) doesn't take a schema in a request that also sends tools."
            throw LanguageModelError.unsupported(.guidedGeneration, description)
        }
        let level = generation.contextOptions.reasoningLevel
        let (effort, movedEffort) = reasoningEffort(level)
        let appMembers = options.additionalMembers
        let appEffort = appMembers[ChatCompletions.Member.reasoningEffort.rawValue].map { JSONValue($0) }
        let appThinking = provider.sendsThinking ? appMembers[ChatCompletions.Member.thinking.rawValue].map { JSONValue($0) } : nil
        // The provider's own `thinking` follows the level, so it never goes with an app's effort.
        let thinking = appEffort == nil && provider.sendsThinking ? Thinking(level: level, reasons: details.reasoning.isSupported) : nil
        let reasons = Thinking.reasons(thinking: appThinking ?? thinking?.json, effort: appEffort?.stringValue ?? effort)
        if provider.refusesRequiredCallWhileReasoning, reasons, request.hasSessionTools,
            generation.generationOptions.toolCallingMode?.kind == .required
        {
            let description = """
                \(provider.name) takes a required tool call only with reasoning off, so a request that requires one needs the \
                reasoning level off.
                """
            throw LanguageModelError.unsupported(.toolCalling, description)
        }
        request.members = try JSONValueEncoder.members(
            of: ChatCompletionsMembers(
                streamOptions: provider.asksForUsage ? ChatCompletionsMembers.StreamOptions(includeUsage: true) : nil,
                reasoningEffort: effort, thinking: thinking))
        request.tokenLimitMember = provider.tokenLimitMember
        request.overridingMembers = options.overridingMembers
        request.movedEffort = appEffort == nil && reasons ? movedEffort : nil
    }

    /// Sends the reasoning effort in `reasoning`, the storage the options ask for, and the app's own members over the
    /// format's.
    ///
    /// A request that sets a reasoning level sends the nearest effort the model accepts, for a model that reasons.
    func prepare(_ request: inout Responses.Request) throws {
        let (effort, movedEffort) = reasoningEffort(request.generation.contextOptions.reasoningLevel)
        if let effort { request.reasoning = Responses.Request.Reasoning(effort: effort) }
        request.movedEffort = movedEffort
        request.storage = options.storage.storage
        request.overridingMembers = options.overridingMembers
    }

    /// The effort to send for a reasoning level, which is the nearest the model accepts, and the move the request logs
    /// when that effort isn't the level's own or none is sent.
    private func reasoningEffort(_ level: ContextOptions.ReasoningLevel?) -> (String?, MovedEffort?) {
        guard let level, details.reasoning.isSupported else { return (nil, nil) }
        return level.sentEffort(supporting: details.reasoningEfforts)
    }

    // MARK: While the answer streams

    /// Takes the reasoning in a chunk's delta: its `reasoning_content`, or else its `reasoning`, so a provider that
    /// sends the same text in both shows it once. For a provider whose answers carry thought signatures, keeps the
    /// first one a tool call carries and the first one the answer's text carries.
    mutating func read(_ extras: OpenAICompatibleChunkExtras) -> ChatCompletions.ChunkAdditions {
        if provider.reasoningReplay == .thoughtSignatures { signatures.read(extras) }
        return ChatCompletions.ChunkAdditions(reasoning: extras.reasoning)
    }

    // MARK: When it ends, or fails

    /// The company that ran the model, the request's id from the first of the provider's headers that has one, and the
    /// answer's thought signature, on the entry that ends the answer.
    func additions(header: (String) -> String?) -> AnswerAdditions {
        AnswerAdditions(
            host: provider.host, requestID: provider.requestIDHeaders.lazy.compactMap(header).first,
            reasoningSignature: signatures.signature)
    }

    /// What a failure becomes: `LanguageModelError` for a rate limit, an oversized context, a content filter, a timeout
    /// or an image the provider can't use, `GeneratedContent.ParsingError` for a guided answer the provider says broke
    /// its schema, and `OpenAICompatibleError` otherwise, such as for a rejected key or a quota that ran out, with
    /// `invalidResponse` for a stream the format couldn't use.
    func error(for failure: RequestFailure<OpenAICompatibleErrorBody>) -> any Error {
        let requestID = provider.requestIDHeaders.lazy.compactMap(failure.header).first
        switch failure.kind {
        case .rejected:
            return OpenAICompatibleFailure(failure, provider: provider, requestID: requestID)
                .error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .errorEvent, .failedAnswer:
            return OpenAICompatibleFailure(streamError: failure.body, message: failure.message, provider: provider, requestID: requestID)
                .error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .unreadableEvent, .unusableAnswer:
            return OpenAICompatibleError(
                providerName: provider.name, message: failure.message, code: .invalidResponse, requestID: requestID)
        }
    }
}

// MARK: - Wire

/// The members of a streamed chunk that the module reads beyond the format's own: the reasoning in the delta, whose
/// member differs by provider, and the thought signatures that the delta and its tool calls carry in
/// `extra_content.google.thought_signature`. A member of another kind than the module reads is passed over.
struct OpenAICompatibleChunkExtras: Decodable {
    /// The delta's reasoning: its `reasoning_content`, or else its `reasoning`, whichever first holds text.
    let reasoning: String?

    /// The first thought signature that a tool call of the delta carries.
    let callSignature: String?

    /// The thought signature that the delta itself carries, as on the last chunk of an answer with no tool call.
    let textSignature: String?

    init(from decoder: any Decoder) throws {
        let chunk = try decoder.container(keyedBy: Key.self)
        let choices = try? chunk.decodeIfPresent([Choice].self, forKey: .choices)
        let delta = choices?.first?.delta
        reasoning = delta?.reasoning
        callSignature = delta?.toolCalls?.lazy.compactMap(\.extraContent?.signature).first
        textSignature = delta?.extraContent?.signature
    }

    private struct Choice: Decodable {
        let delta: Delta?

        init(from decoder: any Decoder) throws {
            let choice = try decoder.container(keyedBy: Key.self)
            delta = try? choice.decodeIfPresent(Delta.self, forKey: .delta)
        }
    }

    private struct Delta: Decodable {
        let reasoning: String?
        let extraContent: ExtraContent?
        let toolCalls: [ToolCall]?

        init(from decoder: any Decoder) throws {
            let delta = try decoder.container(keyedBy: Key.self)
            let spellings = [Key.reasoningContent, .reasoning].lazy.compactMap { try? delta.decodeIfPresent(String.self, forKey: $0) }
            reasoning = spellings.first { !$0.isEmpty }
            extraContent = try? delta.decodeIfPresent(ExtraContent.self, forKey: .extraContent)
            toolCalls = try? delta.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        }
    }

    private struct ToolCall: Decodable {
        let extraContent: ExtraContent?

        init(from decoder: any Decoder) throws {
            let call = try decoder.container(keyedBy: Key.self)
            extraContent = try? call.decodeIfPresent(ExtraContent.self, forKey: .extraContent)
        }
    }

    /// The `extra_content` of a delta or a tool call: its `google.thought_signature`, when it's text that isn't empty.
    private struct ExtraContent: Decodable {
        let signature: String?

        init(from decoder: any Decoder) throws {
            let extra = try decoder.container(keyedBy: Key.self)
            let google = try? extra.nestedContainer(keyedBy: Key.self, forKey: .google)
            let signature = try? google?.decodeIfPresent(String.self, forKey: .thoughtSignature)
            self.signature = signature?.isEmpty == false ? signature : nil
        }
    }

    private enum Key: String, CodingKey {
        case choices
        case delta
        case reasoning
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
        case extraContent = "extra_content"
        case google
        case thoughtSignature = "thought_signature"
    }
}

/// The members the module adds to a Chat Completions request: the ask for a usage chunk, and the reasoning effort, with
/// `thinking`, when one is sent.
private struct ChatCompletionsMembers: Encodable {
    struct StreamOptions: Encodable {
        let includeUsage: Bool

        private enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    let streamOptions: StreamOptions?
    let reasoningEffort: String?
    let thinking: Thinking?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ChatCompletions.Member.self)
        try container.encodeIfPresent(streamOptions, forKey: .streamOptions)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encodeIfPresent(thinking, forKey: .thinking)
    }
}

extension ChatCompletions.Member {
    fileprivate static let streamOptions: Self = "stream_options"
    fileprivate static let reasoningEffort: Self = "reasoning_effort"
    fileprivate static let thinking: Self = "thinking"
}

extension OpenAICompatibleOptions.Storage {
    /// The format's storage for the option.
    fileprivate var storage: Responses.Request.Storage {
        switch self {
        case .automatic: .automatic
        case .stored: .stored
        case .notStored: .notStored
        }
    }
}
