import Foundation

// MARK: - Model list

/// The body of OpenRouter's `GET /models`, reduced to the fields the catalog uses.
///
/// Days decode into their type, so a fetch fails on one that isn't real instead of storing it.
struct OpenRouterModelsResponse: Decodable {
    struct Model: Decodable {
        struct AliasTarget: Decodable {
            let slug: String
        }

        struct Architecture: Decodable {
            let inputModalities: [String]
            let outputModalities: [String]
        }

        struct Reasoning: Decodable {
            /// The efforts a model accepts, as OpenRouter reports them.
            enum Efforts: Equatable {
                /// The model leaves `supported_efforts` out, so its effort can't be chosen.
                case unlisted
                /// The model sends `null`, so it accepts every effort.
                case any
                /// The words the model lists, in its order, each once.
                case listed([String])
            }

            let supportedEfforts: Efforts
            let defaultEffort: String?
            let mandatory: Bool?
            let defaultEnabled: Bool?

            private enum CodingKeys: String, CodingKey {
                case supportedEfforts
                case defaultEffort
                case mandatory
                case defaultEnabled
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                supportedEfforts =
                    if !container.contains(.supportedEfforts) {
                        .unlisted
                    } else if try container.decodeNil(forKey: .supportedEfforts) {
                        .any
                    } else {
                        .listed(try container.decode([String?].self, forKey: .supportedEfforts).compactMap(\.self).uniqued())
                    }
                defaultEffort = try container.decodeIfPresent(String.self, forKey: .defaultEffort)
                mandatory = try container.decodeIfPresent(Bool.self, forKey: .mandatory)
                defaultEnabled = try container.decodeIfPresent(Bool.self, forKey: .defaultEnabled)
            }
        }

        struct Pricing: Decodable {
            let inputCacheWrite: String?
        }

        let id: String
        let name: String
        let aliasTarget: AliasTarget?
        let created: Int
        let knowledgeCutoff: CatalogDay?
        let expirationDate: CatalogDay?
        let contextLength: Int?
        let architecture: Architecture
        let supportedParameters: [String]?
        let reasoning: Reasoning?
        let pricing: Pricing?
    }

    let data: [Model]

    static func decoded(from data: Data) throws -> OpenRouterModelsResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenRouterModelsResponse.self, from: data)
    }
}

// MARK: - Catalog

extension OpenRouterModelsResponse {
    /// The variant suffix of models that work only through OpenRouter's Batch API, not chat completions.
    private static let batchSuffix = ":batch"

    /// The vendor prefix of Anthropic's model ids.
    private static let anthropicVendor = "anthropic"

    /// The vendor prefix of Alibaba's Qwen model ids.
    private static let qwenVendor = "qwen"

    /// The models in catalog form.
    ///
    /// A model whose id ends in `:batch` is left out, because it works only through the Batch API. A model that
    /// accepts every effort lists `everyEffort`, and a model that doesn't list its efforts gets none, as its effort
    /// can't be chosen. A model whose reasoning is mandatory can't take `none`, so it never lists it. A default effort
    /// the model doesn't list is dropped.
    ///
    /// - Parameter everyEffort: Every effort word, highest first.
    /// - Returns: The models, in OpenRouter's order.
    func catalogModels(everyEffort: [String]) -> [CatalogModel] {
        data.filter { !$0.id.hasSuffix(Self.batchSuffix) }.map { model in
            let isReasoningMandatory = model.reasoning?.mandatory ?? false
            let parameters = Set(model.supportedParameters ?? []).sorted()
            var efforts =
                switch model.reasoning?.supportedEfforts {
                case .listed(let words)?: words
                case .any?: everyEffort
                case .unlisted?, nil: [String]()
                }
            if isReasoningMandatory { efforts.removeAll { $0 == EffortRanking.offWord } }
            return CatalogModel(
                id: model.id,
                displayName: model.name,
                aliasTarget: model.aliasTarget?.slug,
                releasedAt: model.created,
                knowledgeCutoff: model.knowledgeCutoff,
                expirationDate: model.expirationDate,
                contextSize: model.contextLength,
                inputModalities: Set(model.architecture.inputModalities).sorted(),
                outputModalities: Set(model.architecture.outputModalities).sorted(),
                supportedParameters: parameters,
                reasoningEfforts: efforts,
                defaultReasoningEffort: model.reasoning?.defaultEffort.flatMap { efforts.contains($0) ? $0 : nil },
                reasoning: Self.reasoning(
                    isMandatory: isReasoningMandatory,
                    isEnabledByDefault: model.reasoning?.defaultEnabled == true,
                    parameters: parameters
                ),
                cachesOnlyMarkedPrompts: Self.cachesOnlyMarkedPrompts(model)
            )
        }
    }

    /// Whether and when a model reasons: mandatory reasoning wins, and otherwise a model reasons only when it takes
    /// the `reasoning` parameter, which turns reasoning on or off.
    ///
    /// - Parameters:
    ///   - isMandatory: Whether the model always reasons.
    ///   - isEnabledByDefault: Whether the model reasons when a request doesn't say.
    ///   - parameters: The request parameters the model takes.
    /// - Returns: The model's reasoning.
    static func reasoning(isMandatory: Bool, isEnabledByDefault: Bool, parameters: [String]) -> CatalogReasoning {
        if isMandatory { return .mandatory }
        return parameters.contains(CatalogModel.reasoningParameter) ? .optional(enabledByDefault: isEnabledByDefault) : .unsupported
    }

    /// Whether a model's hosts cache a prompt only when the request marks it: Anthropic's for Claude, and Alibaba's
    /// for the Qwen models that list a cache write price. A negative price, which OpenRouter uses for a price that
    /// depends on the request, isn't one.
    private static func cachesOnlyMarkedPrompts(_ model: Model) -> Bool {
        let vendor = model.id.drop { $0 == "~" }.prefix { $0 != "/" }
        return vendor == anthropicVendor || (vendor == qwenVendor && model.pricing?.inputCacheWrite?.hasPrefix("-") == false)
    }
}

// MARK: - API description

/// OpenRouter's OpenAPI description, reduced to the schemas the catalog reads.
struct OpenRouterAPIDescription: OpenAPIDescription {
    /// A schema, reduced to its description, its string values and its properties.
    struct Schema: OpenAPIWordSchema {
        let description: String?
        /// The schema's string `enum` values, in order, each once.
        let values: [String]
        let properties: [String: Property]

        private enum CodingKeys: String, CodingKey {
            case description
            case values = "enum"
            case properties
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            values = container.decodeStringValues(forKey: .values).uniqued()
            properties = try container.decodeIfPresent([String: Property].self, forKey: .properties) ?? [:]
        }
    }

    /// A property of a schema: its own description, or a reference to the schema that describes it.
    struct Property: Decodable {
        let description: String?
        let reference: String?

        private enum CodingKeys: String, CodingKey {
            case description
            case reference = "$ref"
        }
    }

    /// Every schema whose words the catalog reads.
    static var wordSchemaNames: [String] {
        CatalogSource.openrouter.vocabularies.map(schemaName(of:)) + [effortSchemaName]
    }

    let components: OpenAPIComponents<Schema>

    /// The schema that lists a vocabulary's words.
    static func schemaName(of vocabulary: CatalogVocabulary) -> String {
        switch vocabulary {
        case .inputModalities: "InputModality"
        case .outputModalities: "OutputModality"
        case .parameters: "Parameter"
        case .searchContextSizes: "SearchQualityLevel"
        case .webFetchEngines: "WebFetchEngineEnum"
        case .webSearchEngines: "WebSearchEngineEnum"
        case .webSearchModes: "WebSearchMode"
        }
    }

    /// Every effort word, highest first, as the description lists them.
    func efforts() throws(MissingSchema) -> [String] {
        try words(ofSchema: Self.effortSchemaName)
    }

    /// The words of each vocabulary. A parameter's summary is the description of its chat request field.
    func vocabularies() throws(MissingSchema) -> [CatalogVocabulary: [CatalogWord]] {
        let requestFields = components.schemas["ChatRequest"]?.properties ?? [:]
        var vocabularies: [CatalogVocabulary: [CatalogWord]] = [:]
        for vocabulary in CatalogSource.openrouter.vocabularies {
            vocabularies[vocabulary] = try words(of: vocabulary).map { word in
                CatalogWord(word, summary: vocabulary == .parameters ? requestFields[word].flatMap(summary) : nil)
            }
        }
        return vocabularies
    }

    private func words(of vocabulary: CatalogVocabulary) throws(MissingSchema) -> [String] {
        try words(ofSchema: Self.schemaName(of: vocabulary))
    }

    /// A property's description, or that of the schema it refers to, on one line and ending in a period.
    private func summary(of property: Property) -> String? {
        let referenced = property.reference?.split(separator: "/").last.flatMap { components.schemas[String($0)]?.description }
        guard let text = property.description ?? referenced else { return nil }
        let line = SourceText.docText(text)
        guard let last = line.last else { return nil }
        return ".!?".contains(last) ? line : line + "."
    }
}
