// MARK: - Model

/// One model as a catalog snapshot stores it: only the facts the generated code uses, in a stable order.
struct CatalogModel: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    /// The id of the model an alias points to now.
    let aliasTarget: String?
    /// Seconds since 1970.
    let releasedAt: Int
    let knowledgeCutoff: CatalogDay?
    /// The day the source stops serving the model.
    let expirationDate: CatalogDay?
    let contextSize: Int?
    /// Sorted.
    let inputModalities: [String]
    /// Sorted.
    let outputModalities: [String]
    /// Sorted.
    let supportedParameters: [String]
    /// Highest first, as the provider lists them; empty when the model's effort can't be chosen.
    let reasoningEfforts: [String]
    let defaultReasoningEffort: String?
    /// Whether and when the model reasons.
    let reasoning: CatalogReasoning
    /// Whether the model's hosts cache a prompt only when the request marks it.
    let cachesOnlyMarkedPrompts: Bool
    /// The effort words the model accepted before and no longer does, sorted, each with the day it stopped. Its effort
    /// type keeps them as deprecated members.
    var removedReasoningEfforts: [CatalogWord] = []

    /// The modality that every catalog model outputs.
    static let textModality = "text"

    /// The request parameter that sets a model's reasoning, which every source names alike.
    static let reasoningParameter = "reasoning"
}

extension CatalogModel {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, aliasTarget, releasedAt, knowledgeCutoff, expirationDate, contextSize
        case inputModalities, outputModalities, supportedParameters, reasoningEfforts, defaultReasoningEffort, reasoning
        case cachesOnlyMarkedPrompts, removedReasoningEfforts
    }

    /// The two flags that snapshots stored before `reasoning`, when OpenRouter was the only source.
    private enum FlagCodingKeys: String, CodingKey {
        case isReasoningMandatory
        case reasonsByDefault
    }

    /// Decodes a model, including one from an older snapshot: without `reasoning`, it's decided from OpenRouter's
    /// flags and parameters, as a fetch did then, without `cachesOnlyMarkedPrompts`, it's `false`, and without
    /// `removedReasoningEfforts`, it has none.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        aliasTarget = try container.decodeIfPresent(String.self, forKey: .aliasTarget)
        releasedAt = try container.decode(Int.self, forKey: .releasedAt)
        knowledgeCutoff = try container.decodeIfPresent(CatalogDay.self, forKey: .knowledgeCutoff)
        expirationDate = try container.decodeIfPresent(CatalogDay.self, forKey: .expirationDate)
        contextSize = try container.decodeIfPresent(Int.self, forKey: .contextSize)
        inputModalities = try container.decode([String].self, forKey: .inputModalities)
        outputModalities = try container.decode([String].self, forKey: .outputModalities)
        supportedParameters = try container.decode([String].self, forKey: .supportedParameters)
        reasoningEfforts = try container.decode([String].self, forKey: .reasoningEfforts)
        defaultReasoningEffort = try container.decodeIfPresent(String.self, forKey: .defaultReasoningEffort)
        cachesOnlyMarkedPrompts = try container.decodeIfPresent(Bool.self, forKey: .cachesOnlyMarkedPrompts) ?? false
        removedReasoningEfforts = try container.decodeIfPresent([CatalogWord].self, forKey: .removedReasoningEfforts) ?? []
        if let reasoning = try container.decodeIfPresent(CatalogReasoning.self, forKey: .reasoning) {
            self.reasoning = reasoning
        } else {
            let flags = try decoder.container(keyedBy: FlagCodingKeys.self)
            reasoning = OpenRouterModelsResponse.reasoning(
                isMandatory: try flags.decodeIfPresent(Bool.self, forKey: .isReasoningMandatory) ?? false,
                isEnabledByDefault: try flags.decodeIfPresent(Bool.self, forKey: .reasonsByDefault) ?? false,
                parameters: supportedParameters
            )
        }
    }
}

extension CatalogModel {
    /// Encodes a model, leaving out `removedReasoningEfforts` when it's empty, as it is for most models, and every
    /// optional value that's `nil`.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(aliasTarget, forKey: .aliasTarget)
        try container.encode(releasedAt, forKey: .releasedAt)
        try container.encodeIfPresent(knowledgeCutoff, forKey: .knowledgeCutoff)
        try container.encodeIfPresent(expirationDate, forKey: .expirationDate)
        try container.encodeIfPresent(contextSize, forKey: .contextSize)
        try container.encode(inputModalities, forKey: .inputModalities)
        try container.encode(outputModalities, forKey: .outputModalities)
        try container.encode(supportedParameters, forKey: .supportedParameters)
        try container.encode(reasoningEfforts, forKey: .reasoningEfforts)
        try container.encodeIfPresent(defaultReasoningEffort, forKey: .defaultReasoningEffort)
        try container.encode(reasoning, forKey: .reasoning)
        try container.encode(cachesOnlyMarkedPrompts, forKey: .cachesOnlyMarkedPrompts)
        if !removedReasoningEfforts.isEmpty {
            try container.encode(removedReasoningEfforts, forKey: .removedReasoningEfforts)
        }
    }
}

// MARK: - Reasoning

/// Whether and when a catalog model reasons, as one value, so no impossible combination of flags can reach the code.
///
/// A snapshot stores it as one word: `unsupported`, `offByDefault`, `onByDefault` or `mandatory`.
enum CatalogReasoning: Equatable, Sendable, CaseIterable {
    case unsupported
    case optional(enabledByDefault: Bool)
    case mandatory

    static let allCases: [CatalogReasoning] = [
        .unsupported, .optional(enabledByDefault: false), .optional(enabledByDefault: true), .mandatory,
    ]

    /// The word a snapshot stores.
    var word: String {
        switch self {
        case .unsupported: "unsupported"
        case .optional(enabledByDefault: false): "offByDefault"
        case .optional(enabledByDefault: true): "onByDefault"
        case .mandatory: "mandatory"
        }
    }
}

extension CatalogReasoning: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let word = try container.decode(String.self)
        guard let reasoning = Self.allCases.first(where: { $0.word == word }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(word)' isn't a kind of reasoning.")
        }
        self = reasoning
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(word)
    }
}

// MARK: - Words

/// A word of an open vocabulary, as a catalog snapshot stores it.
struct CatalogWord: Codable, Equatable, Sendable {
    let word: String
    /// What the word means, from the source's API description.
    let summary: String?
    /// The day the word disappeared from its source, or `nil` while the source uses it.
    let removedOn: CatalogDay?

    init(_ word: String, summary: String? = nil, removedOn: CatalogDay? = nil) {
        self.word = word
        self.summary = summary
        self.removedOn = removedOn
    }

    /// The word as removed on the given day, unless it was removed earlier.
    func removed(on day: CatalogDay) -> CatalogWord {
        CatalogWord(word, summary: summary, removedOn: removedOn ?? day)
    }
}

// MARK: - Removed models

/// A model that disappeared from its source, kept so its generated member stays, marked deprecated.
struct RemovedModel: Codable, Equatable, Sendable {
    let model: CatalogModel
    /// The day the model disappeared.
    let removedOn: CatalogDay
}
