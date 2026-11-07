public import Foundation
public import FoundationModels
public import LanguageModels
public import UniformTypeIdentifiers

// MARK: - Model

/// What OpenRouter reports about one of its models.
///
/// Each model in the catalog is a static member whose effort type lists exactly the levels that model accepts. A
/// model picked at runtime uses `ContextOptions.ReasoningLevel` as its effort type instead.
public struct OpenRouterModel<Effort: ModelEffort>: ModelDetails, Hashable {
    /// The model's OpenRouter id, such as `typesafe/jev-router`.
    public let id: OpenRouterModelID

    /// The model's human-readable name.
    public let displayName: String

    /// When OpenRouter first listed the model, or `nil` when the details don't record it.
    public let releaseDate: Date?

    /// The model that an alias, such as `~deepseek/deepseek-pro-latest`, points to now, or `nil` for a model that
    /// isn't an alias.
    public let aliasTarget: OpenRouterModelID?

    /// The day the model's training data ends, at midnight UTC.
    public let knowledgeCutoff: Date?

    /// The day OpenRouter retires the model, at midnight UTC.
    public let expirationDate: Date?

    /// The day OpenRouter stopped listing the model, at midnight UTC, as this release's catalog records it, or `nil`
    /// for a model the catalog doesn't record as removed.
    ///
    /// The catalog keeps a removed model's member, marked deprecated, and leaves it out of ``catalogModels`` and
    /// ``init(catalogID:)``. A request that may reach the model, as its model or a fallback, logs an error and, in a
    /// debug build, shows a runtime warning.
    public var removalDate: Date? {
        ModelRemovals.openRouter.removalDate(of: id.rawValue)
    }

    /// The size of the model's context window, in tokens.
    public let contextSize: Int?

    /// The kinds of input the model accepts, such as text, images or files.
    public let inputModalities: Set<OpenRouterInputModality>

    /// The kinds of output the model generates, such as text or images.
    public let outputModalities: Set<OpenRouterOutputModality>

    /// The request parameters the model accepts, such as `tools` or `seed`.
    public let supportedParameters: Set<OpenRouterParameter>

    /// Whether and when the model reasons.
    public let reasoning: ModelReasoning

    /// The reasoning levels the model accepts, highest first, or none when its level can't be chosen.
    public let reasoningEfforts: [Effort]

    /// The level OpenRouter uses when a request doesn't set one.
    public let defaultReasoningEffort: Effort?

    /// Whether the model's hosts cache a prompt only when the request marks it, as Anthropic's do for Claude and
    /// Alibaba's for the Qwen models that list a cache write price.
    ///
    /// ``OpenRouterCacheControl/automatic`` marks a request only when every model it may reach caches only marked
    /// prompts. It treats a Claude model as one even when this is `false`.
    public let cachesOnlyMarkedPrompts: Bool

    /// Creates a model's details.
    ///
    /// - Parameters:
    ///   - id: The model's OpenRouter id.
    ///   - displayName: The model's human-readable name.
    ///   - releaseDate: When OpenRouter first listed the model, or `nil` when it isn't known.
    ///   - aliasTarget: The model an alias points to now.
    ///   - knowledgeCutoff: The day the model's training data ends.
    ///   - expirationDate: The day OpenRouter retires the model.
    ///   - contextSize: The size of the model's context window, in tokens.
    ///   - inputModalities: The kinds of input the model accepts.
    ///   - outputModalities: The kinds of output the model generates.
    ///   - supportedParameters: The request parameters the model accepts.
    ///   - reasoning: Whether and when the model reasons.
    ///   - reasoningEfforts: The reasoning levels the model accepts, highest first.
    ///   - defaultReasoningEffort: The level OpenRouter uses when a request doesn't set one.
    ///   - cachesOnlyMarkedPrompts: Whether the model's hosts cache a prompt only when the request marks it.
    public init(
        id: OpenRouterModelID,
        displayName: String,
        releaseDate: Date? = nil,
        aliasTarget: OpenRouterModelID? = nil,
        knowledgeCutoff: Date? = nil,
        expirationDate: Date? = nil,
        contextSize: Int? = nil,
        inputModalities: Set<OpenRouterInputModality> = [.text],
        outputModalities: Set<OpenRouterOutputModality> = [.text],
        supportedParameters: Set<OpenRouterParameter>,
        reasoning: ModelReasoning = .unsupported,
        reasoningEfforts: [Effort] = [],
        defaultReasoningEffort: Effort? = nil,
        cachesOnlyMarkedPrompts: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.releaseDate = releaseDate
        self.aliasTarget = aliasTarget
        self.knowledgeCutoff = knowledgeCutoff
        self.expirationDate = expirationDate
        self.contextSize = contextSize
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.supportedParameters = supportedParameters
        self.reasoning = reasoning
        self.reasoningEfforts = reasoningEfforts
        self.defaultReasoningEffort = defaultReasoningEffort
        self.cachesOnlyMarkedPrompts = cachesOnlyMarkedPrompts
    }

    /// What the model supports, from the request parameters and input kinds it accepts.
    ///
    /// Guided generation needs `structured_outputs`, so the host holds the answer to the schema. A model with only
    /// JSON mode, `response_format`, could answer with JSON that breaks the schema's guides and still decodes, so a
    /// guided request to it is refused instead.
    public var capabilities: LanguageModelCapabilities {
        var capabilities: [LanguageModelCapabilities.Capability] = []
        if supportedParameters.contains(.tools) { capabilities.append(.toolCalling) }
        if supportedParameters.contains(.structuredOutputs) { capabilities.append(.guidedGeneration) }
        if reasoning.isSupported { capabilities.append(.reasoning) }
        if inputModalities.contains(.image) { capabilities.append(.vision) }
        return LanguageModelCapabilities(capabilities)
    }

    /// The attachment kinds the model accepts: those of its input kinds, and PDF documents, which OpenRouter reads for
    /// a model that can't read them itself.
    public var dataAttachmentTypes: Set<UTType> {
        Set(attachmentInputs(pdfEngine: nil).flatMap(\.contentTypes))
    }

    /// The data kinds of the outputs the model generates besides text, which answers carry as data entries.
    public var dataEntryTypes: Set<UTType> {
        Set(outputModalities.compactMap(\.contentType))
    }

    /// The input kinds the model takes as attachments with a PDF engine: its own, and files, since OpenRouter reads a
    /// PDF for a model that can't, unless the engine is `native`, which only a model that reads PDFs itself has.
    func attachmentInputs(pdfEngine: OpenRouterOptions.PDFEngine?) -> Set<OpenRouterInputModality> {
        pdfEngine == .native ? inputModalities : inputModalities.union([.file])
    }

    /// Hashes the model's id, which equal details always share, so details of any effort type can be hashed.
    ///
    /// - Parameter hasher: The hasher to feed the id to.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension OpenRouterModel where Effort == ContextOptions.ReasoningLevel {
    /// The same model with its efforts in their open form, so models with different effort types fit in one list.
    ///
    /// - Parameter typed: A model from the catalog.
    public init(_ typed: OpenRouterModel<some ModelEffort>) {
        self.init(
            id: typed.id,
            displayName: typed.displayName,
            releaseDate: typed.releaseDate,
            aliasTarget: typed.aliasTarget,
            knowledgeCutoff: typed.knowledgeCutoff,
            expirationDate: typed.expirationDate,
            contextSize: typed.contextSize,
            inputModalities: typed.inputModalities,
            outputModalities: typed.outputModalities,
            supportedParameters: typed.supportedParameters,
            reasoning: typed.reasoning,
            reasoningEfforts: typed.reasoningEfforts.map(\.reasoningLevel),
            defaultReasoningEffort: typed.defaultReasoningEffort?.reasoningLevel,
            cachesOnlyMarkedPrompts: typed.cachesOnlyMarkedPrompts
        )
    }
}

extension OpenRouterModel where Effort == ContextOptions.ReasoningLevel {
    /// The details narrowed to what another model also supports: the parameters, input and output kinds and efforts
    /// both take, the smaller limits, reasoning only when both reason, and caching only marked prompts only when both
    /// do. The id, name and dates stay these.
    func sharing(_ other: Self) -> Self {
        Self(
            id: id,
            displayName: displayName,
            releaseDate: releaseDate,
            aliasTarget: aliasTarget,
            knowledgeCutoff: knowledgeCutoff,
            expirationDate: expirationDate,
            contextSize: contextSize.smallerLimit(other.contextSize),
            inputModalities: inputModalities.intersection(other.inputModalities),
            outputModalities: outputModalities.intersection(other.outputModalities),
            supportedParameters: supportedParameters.intersection(other.supportedParameters),
            reasoning: reasoning.sharing(other.reasoning),
            reasoningEfforts: reasoningEfforts.filter { other.reasoningEfforts.contains($0) },
            defaultReasoningEffort: defaultReasoningEffort == other.defaultReasoningEffort ? defaultReasoningEffort : nil,
            cachesOnlyMarkedPrompts: cachesOnlyMarkedPrompts && other.cachesOnlyMarkedPrompts
        )
    }
}

// MARK: - Model id

/// An OpenRouter model id, such as `typesafe/jev-router`.
///
/// A distinct type, so text that isn't an OpenRouter id, such as a display name or another provider's id, can't be
/// passed by mistake.
///
/// To make ids from strings, name the initializer in full, since a bare `OpenRouterModelID.init` could also mean the
/// string-literal one:
///
/// ```swift
/// let ids = savedIDs.map(OpenRouterModelID.init(rawValue:))
/// ```
public struct OpenRouterModelID: ProviderVocabulary {
    /// The id as OpenRouter's API spells it.
    public let rawValue: String

    /// Creates an id from OpenRouter's spelling of it.
    ///
    /// - Parameter rawValue: The id, such as `"typesafe/jev-router"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension OpenRouterModelID {
    /// Anthropic's vendor name in a model id.
    private static let anthropic: Substring = "anthropic"

    /// Whether the id names an Anthropic model, or an alias of one, such as `~anthropic/claude-haiku-latest`.
    var isAnthropic: Bool { vendor == Self.anthropic }

    /// The vendors whose structured outputs, by their own documentation, reject schema constraints such as `minimum`
    /// and `maxItems`, so a request that may reach one of their models sends the portable schema from the start.
    private static let vendorsRejectingSchemaConstraints: Set<Substring> = [anthropic]

    /// Whether the id names a model whose structured outputs reject schema constraints, or an alias of one.
    var rejectsSchemaConstraints: Bool { Self.vendorsRejectingSchemaConstraints.contains(vendor) }

    /// The vendor the id starts with, such as `anthropic` for `anthropic/claude-haiku-5.5` and for its alias
    /// `~anthropic/claude-haiku-latest`.
    private var vendor: Substring {
        rawValue.drop { $0 == "~" }.prefix { $0 != "/" }
    }
}
