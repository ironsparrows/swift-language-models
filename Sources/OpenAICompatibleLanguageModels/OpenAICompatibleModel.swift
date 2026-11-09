public import Foundation
public import FoundationModels
public import LanguageModels
public import UniformTypeIdentifiers

// MARK: - Model

/// What an app says about a model on a provider that speaks OpenAI's formats: its id, its provider, and what it can do.
///
/// Name the model as its provider's API does, and the provider it runs on. What the model can do defaults to what the
/// provider's models can, and the provider has the last word at run time: a setting it rejects throws its error.
///
/// ```swift
/// let details = OpenAICompatibleModel("local-model", on: local, contextSize: 32_768, reasoning: .onByDefault)
/// ```
///
/// There's no catalog behind it, so the details record no release date, no removal and no default effort.
public struct OpenAICompatibleModel: ModelDetails, Hashable {
    /// The model's id, as its provider's API spells it, such as `local-model`.
    public let id: OpenAICompatibleModelID

    /// The provider the model runs on, which every request goes to.
    public let provider: OpenAICompatibleProvider

    /// The model's human-readable name.
    public let displayName: String

    /// The size of the model's context window, in tokens, or `nil` when it isn't known.
    public let contextSize: Int?

    /// Whether and when the model reasons.
    public let reasoning: ModelReasoning

    /// The reasoning levels the model accepts, highest first, or none when it doesn't reason. A request sends the
    /// nearest of them to the level it asks for.
    public let reasoningEfforts: [ContextOptions.ReasoningLevel]

    /// The kinds of data the model accepts as prompt attachments, such as images.
    public let dataAttachmentTypes: Set<UTType>

    /// What the model supports besides reasoning, which ``reasoning`` says.
    private let listedCapabilities: Set<LanguageModelCapabilities.Capability>

    /// Creates a model's details.
    ///
    /// Each value left out takes the provider's default. For a provider described by its name and URL, a model takes
    /// tools, guided generation and images, reasons only when a request asks it to, and accepts the efforts `xhigh`,
    /// `high`, `medium`, `low`, `minimal` and `none`.
    ///
    /// - Parameters:
    ///   - id: The model's id, as its provider's API spells it.
    ///   - provider: The provider the model runs on.
    ///   - displayName: The model's human-readable name, or `nil` for its id.
    ///   - capabilities: What the model supports besides reasoning: tool calling, guided generation and vision. `nil`
    ///     takes the provider's default. Reasoning follows `reasoning`.
    ///   - contextSize: The size of the model's context window, in tokens, or `nil` when it isn't known.
    ///   - reasoning: Whether and when the model reasons, or `nil` for the provider's default.
    ///   - efforts: The reasoning levels the model accepts, highest first, or `nil` for the provider's default. A model
    ///     that doesn't reason accepts none, whatever this says.
    ///   - attachments: The kinds of data the model accepts as prompt attachments, such as `UTType.pdf`, or `nil` for
    ///     images when the model takes them, as its capabilities say, and nothing else.
    public init(
        _ id: OpenAICompatibleModelID,
        on provider: OpenAICompatibleProvider,
        displayName: String? = nil,
        capabilities: Set<LanguageModelCapabilities.Capability>? = nil,
        contextSize: Int? = nil,
        reasoning: ModelReasoning? = nil,
        efforts: [ContextOptions.ReasoningLevel]? = nil,
        attachments: Set<UTType>? = nil
    ) {
        let reasoning = reasoning ?? provider.defaultReasoning
        self.id = id
        self.provider = provider
        self.displayName = displayName ?? id.rawValue
        listedCapabilities = (capabilities ?? provider.defaultCapabilities).subtracting([.reasoning])
        self.contextSize = contextSize
        self.reasoning = reasoning
        reasoningEfforts = reasoning.isSupported ? efforts ?? provider.defaultEfforts : []
        dataAttachmentTypes = attachments ?? (listedCapabilities.contains(.vision) ? [.image] : [])
    }

    /// What the model supports: what its details list, and reasoning when it reasons.
    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(Array(listedCapabilities) + (reasoning.isSupported ? [.reasoning] : []))
    }

    /// The effort the model uses when a request doesn't set a level: `nil`, since the details don't record it.
    public var defaultReasoningEffort: ContextOptions.ReasoningLevel? {
        nil
    }

    /// The day the provider stopped listing the model: `nil`, since there's no catalog to record it.
    public var removalDate: Date? {
        nil
    }

    /// The data kinds the model generates besides text: none, since answers come back as text.
    public var dataEntryTypes: Set<UTType> {
        []
    }

    /// Hashes the model's id and provider, which equal details always share.
    ///
    /// - Parameter hasher: The hasher to feed them to.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(provider)
    }
}

// MARK: - Model id

/// A model's id at a provider that speaks OpenAI's formats, such as `local-model`.
///
/// A distinct type, so text that isn't a model id, such as a display name, can't be passed by mistake.
///
/// To make ids from strings, name the initializer in full, since a bare `OpenAICompatibleModelID.init` could also mean
/// the string-literal one:
///
/// ```swift
/// let ids = savedIDs.map(OpenAICompatibleModelID.init(rawValue:))
/// ```
public struct OpenAICompatibleModelID: ProviderVocabulary {
    /// The id as the provider's API spells it.
    public let rawValue: String

    /// Creates an id from the provider's spelling of it.
    ///
    /// - Parameter rawValue: The id, such as `"local-model"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension OpenAICompatibleModelID {
    /// Whether a model that answered, as its answer names it, is this one: the same id, or a dated version of it, such
    /// as `local-model-2026-10-01` for `local-model`.
    func names(_ answeringModel: String) -> Bool {
        answeringModel == rawValue || answeringModel.wholeMatch(of: /(.+)-\d{4}-\d{2}-\d{2}/).map { String($0.1) == rawValue } == true
    }
}
