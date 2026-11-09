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

/// A provider's part in one exchange, in either format: the attachments the model takes, the reasoning effort, the
/// usage chunk and the token limit's member it asks for, the app's own members, the storage, the reasoning in each
/// chunk, the request id, and what the provider's failures become.
///
/// Every method with a default is here, in the type that declares the conformances, so a misspelled one draws a warning
/// instead of silently keeping the default, and neither format's default is picked over the other's.
struct OpenAICompatibleExchange: ChatCompletions.Exchange, Responses.Exchange {
    /// The model's details, with its provider.
    private let details: OpenAICompatibleModel

    /// The app's request settings.
    private let options: OpenAICompatibleOptions

    /// The order of a Chat Completions request's members, which never changes, since a provider's prompt cache depends
    /// on it. An app's member of a key the module writes takes that member's place, and the others go after them,
    /// sorted by key.
    fileprivate static let memberOrder: [ChatCompletions.Member] = [
        .model, .messages, .stream, .streamOptions, .tools, .toolChoice, .responseFormat, .reasoningEffort, .temperature, .topP,
        .seed, .maxCompletionTokens, .maxTokens, .metadata,
    ]

    fileprivate init(model: OpenAICompatibleLanguageModel) {
        details = model.details
        options = model.options
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
    /// Completions none, since a provider reads reasoning back only in a member of its own.
    func replays(_ reasoning: Transcript.Reasoning) -> Bool {
        details.provider.format == .responses && (reasoning.writer.map(details.id.names) ?? true)
    }

    /// No members on an answer that goes back, or on its tool calls.
    func replayMembers(for answer: ChatCompletions.ReplayedAnswer) -> ChatCompletions.ReplayMembers {
        ChatCompletions.ReplayMembers()
    }

    // MARK: Before it is sent

    /// Asks for a usage chunk, sends the token limit as `max_tokens` and the reasoning effort as `reasoning_effort`, and
    /// adds the app's own members over the format's.
    ///
    /// A request that sets a reasoning level sends the nearest effort the model accepts, for a model that reasons; an
    /// app member `reasoning_effort` replaces it, and then nothing is logged as moved.
    func prepare(_ request: inout ChatCompletions.Request) throws {
        let (effort, movedEffort) = reasoningEffort(request.generation.contextOptions.reasoningLevel)
        request.members = try JSONValueEncoder.members(
            of: ChatCompletionsMembers(streamOptions: ChatCompletionsMembers.StreamOptions(includeUsage: true), reasoningEffort: effort))
        request.tokenLimitMember = .maxTokens
        request.overridingMembers = options.overridingMembers
        request.movedEffort = options.additionalMembers[ChatCompletions.Member.reasoningEffort.rawValue] == nil ? movedEffort : nil
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
    /// sends the same text in both shows it once.
    mutating func read(_ extras: OpenAICompatibleChunkExtras) -> ChatCompletions.ChunkAdditions {
        ChatCompletions.ChunkAdditions(reasoning: extras.reasoning)
    }

    // MARK: When it ends, or fails

    /// The request's id, on the entry that ends the answer.
    func additions(header: (String) -> String?) -> AnswerAdditions {
        AnswerAdditions(requestID: header(API.Header.requestID))
    }

    /// What a failure becomes: `LanguageModelError` for a rate limit, an oversized context, a content filter, a timeout
    /// or an image the provider can't use, and `OpenAICompatibleError` otherwise, such as for a rejected key or a quota
    /// that ran out, with `invalidResponse` for a stream the format couldn't use.
    func error(for failure: RequestFailure<OpenAICompatibleErrorBody>) -> any Error {
        let providerName = details.provider.name
        let requestID = failure.header(API.Header.requestID)
        switch failure.kind {
        case .rejected:
            return OpenAICompatibleFailure(failure, providerName: providerName)
                .error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .errorEvent, .failedAnswer:
            return OpenAICompatibleFailure(
                streamError: failure.body, message: failure.message, providerName: providerName, requestID: requestID
            )
            .error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .unreadableEvent, .unusableAnswer:
            return OpenAICompatibleError(providerName: providerName, message: failure.message, code: .invalidResponse, requestID: requestID)
        }
    }
}

// MARK: - Wire

/// The members of a streamed chunk that the module reads beyond the format's own: the reasoning in the delta, whose
/// member differs by provider. A member of another kind than the module reads is passed over.
struct OpenAICompatibleChunkExtras: Decodable {
    /// The delta's reasoning: its `reasoning_content`, or else its `reasoning`, whichever first holds text.
    fileprivate let reasoning: String?

    init(from decoder: any Decoder) throws {
        let chunk = try decoder.container(keyedBy: Key.self)
        let choices = try? chunk.decodeIfPresent([Choice].self, forKey: .choices)
        reasoning = choices?.first?.delta?.reasoning
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

        init(from decoder: any Decoder) throws {
            let delta = try decoder.container(keyedBy: Key.self)
            let spellings = [Key.reasoningContent, .reasoning].lazy.compactMap { try? delta.decodeIfPresent(String.self, forKey: $0) }
            reasoning = spellings.first { !$0.isEmpty }
        }
    }

    private enum Key: String, CodingKey {
        case choices
        case delta
        case reasoning
        case reasoningContent = "reasoning_content"
    }
}

/// The members the module adds to a Chat Completions request: the ask for a usage chunk, and the reasoning effort when
/// one is sent.
private struct ChatCompletionsMembers: Encodable {
    struct StreamOptions: Encodable {
        let includeUsage: Bool

        private enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    let streamOptions: StreamOptions
    let reasoningEffort: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ChatCompletions.Member.self)
        try container.encode(streamOptions, forKey: .streamOptions)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
    }
}

extension ChatCompletions.Member {
    fileprivate static let streamOptions: Self = "stream_options"
    fileprivate static let reasoningEffort: Self = "reasoning_effort"
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
