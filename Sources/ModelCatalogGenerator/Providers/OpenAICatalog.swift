import Foundation

// MARK: - Model list

/// OpenAI's list of the models a key may use, `GET /v1/models`: the only list of the models OpenAI still serves, with
/// the day each shuts down.
struct OpenAIModelList: Decodable {
    private struct Model: Decodable {
        let id: String
        /// Seconds since 1970.
        let created: Int
        /// The day OpenAI shuts the model down, written as `yyyy-MM-dd`. Any other text fails to decode, so the model
        /// never loses its expiration.
        let shutdownDate: CatalogDay?

        private enum CodingKeys: String, CodingKey {
            case id, created
            case shutdownDate = "shutdown_date"
        }
    }

    private let data: [Model]

    static func decoded(from data: Data) throws -> OpenAIModelList {
        try JSONDecoder().decode(OpenAIModelList.self, from: data)
    }
}

// MARK: - Catalog

extension OpenAIModelList {
    /// The parameters every model takes.
    private static let commonParameters = ["max_output_tokens"]

    /// The parameters a model that calls tools takes.
    private static let toolParameters = ["parallel_tool_calls", "tool_choice", "tools"]

    /// The parameter of a model whose answers the host holds to a schema.
    private static let structuredOutputsParameter = "structured_outputs"

    /// The parameters of a model that takes sampling settings.
    private static let samplingParameters = ["temperature", "top_p"]

    /// Every parameter a model can take.
    static var everyParameter: Set<String> {
        Set(commonParameters + toolParameters + [structuredOutputsParameter] + samplingParameters + [CatalogModel.reasoningParameter])
    }

    /// What models.dev says about a served model.
    private enum Description {
        /// The model's entry, or its model's for a dated snapshot that models.dev doesn't list, with the snapshot's
        /// day.
        case entry(ModelsDevCatalog.Model, day: String?)
        /// The entry that would describe the model doesn't decode.
        case undecoded
        /// models.dev doesn't list the model.
        case missing
    }

    /// The models in catalog form: each model OpenAI serves that models.dev describes as a model that generates text,
    /// with what models.dev says it takes and does.
    ///
    /// The API description's lists of model ids don't decide which models the catalog lists: OpenAI serves models for
    /// the Responses API that they leave out, and may drop the id of a model it still serves. A model that works only
    /// with Chat Completions or another endpoint is left out by its id instead, as ``worksOnlyWithOtherEndpoints(_:)``
    /// tells.
    ///
    /// A model whose shutdown day has passed is left out, although OpenAI may still list it. A dated snapshot, such as
    /// `gpt-5-2025-08-07`, takes what its model, `gpt-5`, takes, and its model's name with its day, when models.dev
    /// doesn't list it. A model models.dev doesn't describe, such as one that only works with a tool of its own, is
    /// left out, since the catalog can't say what it takes, and so is one whose entry doesn't decode, which
    /// ``undescribedModelIDs(describedBy:today:)`` lists.
    ///
    /// A model that reasons and takes `none` is recorded as reasoning unless a request turns it off, which assumes its
    /// default effort isn't `none`; one that doesn't take `none` always reasons. No model records a default effort:
    /// neither models.dev nor OpenAI's lists give a model's own.
    ///
    /// - Parameters:
    ///   - descriptions: What models.dev says about OpenAI's models.
    ///   - everyEffort: Every effort word, highest first, which orders each model's efforts.
    ///   - today: The day of the fetch, in UTC.
    /// - Returns: The models, sorted by id.
    func catalogModels(
        describedBy descriptions: ModelsDevCatalog,
        everyEffort: [String],
        today: CatalogDay
    ) -> [CatalogModel] {
        candidates(today: today).compactMap { model in
            guard case .entry(let description, let day) = Self.description(of: model.id, in: descriptions),
                description.type == nil, description.modalities.output == [CatalogModel.textModality]
            else { return nil }
            let reasons = description.reasoning == true
            let efforts = reasons ? Self.highestFirst(description.efforts, ranking: everyEffort) : []
            var parameters = Self.commonParameters
            if description.toolCall == true { parameters += Self.toolParameters }
            if description.structuredOutput == true { parameters.append(Self.structuredOutputsParameter) }
            if description.temperature == true { parameters += Self.samplingParameters }
            if reasons { parameters.append(CatalogModel.reasoningParameter) }
            let displayName = day.map { "\(description.name) (\($0))" } ?? description.name
            return CatalogModel(
                id: model.id,
                displayName: displayName,
                aliasTarget: nil,
                releasedAt: model.created,
                knowledgeCutoff: description.knowledge.flatMap(Self.day(of:)),
                expirationDate: model.shutdownDate,
                contextSize: description.limit?.context,
                inputModalities: Set(description.modalities.input).sorted(),
                outputModalities: [CatalogModel.textModality],
                supportedParameters: parameters.sorted(),
                reasoningEfforts: efforts,
                defaultReasoningEffort: nil,
                reasoning: Self.reasoning(reasons: reasons, efforts: efforts),
                cachesOnlyMarkedPrompts: false
            )
        }
    }

    /// The ids of the models the catalog could list but leaves out because the models.dev entries that would describe
    /// them don't decode, so it can't tell whether they generate text, or what they take.
    ///
    /// - Parameters:
    ///   - descriptions: What models.dev says about OpenAI's models.
    ///   - today: The day of the fetch, in UTC.
    /// - Returns: The ids.
    func undescribedModelIDs(describedBy descriptions: ModelsDevCatalog, today: CatalogDay) -> Set<String> {
        Set(
            candidates(today: today).map(\.id).filter { id in
                if case .undecoded = Self.description(of: id, in: descriptions) { true } else { false }
            }
        )
    }

    /// Whether a model works only with Chat Completions or with an endpoint other than the Responses API, which a word
    /// of its id tells:
    /// - `audio` and `search`: Chat Completions only, as `gpt-audio-mini` and `gpt-4o-search-preview`, since the
    ///   Responses API searches with a tool instead;
    /// - `instruct`: the legacy Completions endpoint only, as `gpt-3.5-turbo-instruct`;
    /// - `realtime`, `transcribe` and `tts`: the Realtime, transcription and speech endpoints, as `gpt-realtime`,
    ///   `gpt-4o-mini-transcribe` and `gpt-4o-mini-tts`.
    ///
    /// Only the id tells them apart, since models.dev may describe one as a model that generates text, and the API
    /// description's Chat Completions list names some of them.
    static func worksOnlyWithOtherEndpoints(_ id: String) -> Bool {
        id.contains(/(?:^|-)(?:audio|instruct|realtime|search|transcribe|tts)(?:-|$)/)
    }

    /// The served models the catalog could list, sorted by id: those whose shutdown day hasn't passed, other than
    /// those that work only with another endpoint.
    private func candidates(today: CatalogDay) -> [Model] {
        data.filter { model in
            !Self.worksOnlyWithOtherEndpoints(model.id) && model.shutdownDate.map { $0.start >= today.start } ?? true
        }.sorted { $0.id < $1.id }
    }

    /// What models.dev says about a served model: its own entry, or for a dated snapshot without one, its model's.
    private static func description(of id: String, in descriptions: ModelsDevCatalog) -> Description {
        if let model = descriptions.models[id] { return .entry(model, day: nil) }
        if descriptions.undecodedIDs.contains(id) { return .undecoded }
        guard let undated = undated(id) else { return .missing }
        if let model = descriptions.models[undated.id] { return .entry(model, day: undated.day) }
        return descriptions.undecodedIDs.contains(undated.id) ? .undecoded : .missing
    }

    /// A model's efforts, highest first: those the ranking knows in its order, then any other, highest first, as
    /// models.dev lists efforts lowest first.
    private static func highestFirst(_ efforts: [String], ranking: [String]) -> [String] {
        ranking.filter(efforts.contains) + efforts.filter { !ranking.contains($0) }.reversed()
    }

    /// Whether and when a model reasons: never for a model that doesn't reason, always for one that doesn't take
    /// `none`, and otherwise unless a request turns it off.
    private static func reasoning(reasons: Bool, efforts: [String]) -> CatalogReasoning {
        guard reasons else { return .unsupported }
        return efforts.contains(EffortRanking.offWord) ? .optional(enabledByDefault: true) : .mandatory
    }

    /// The model a dated snapshot's id names, and the snapshot's day, such as `gpt-5` and `2025-08-07` for
    /// `gpt-5-2025-08-07`, or `nil` for an id without a date.
    private static func undated(_ id: String) -> (id: String, day: String)? {
        guard let match = id.wholeMatch(of: /(.+)-(\d{4}-\d{2}-\d{2})/) else { return nil }
        return (String(match.1), String(match.2))
    }

    /// The day training data ends: the day itself, or the first day of a month written as `yyyy-MM`.
    private static func day(of knowledge: String) -> CatalogDay? {
        CatalogDay(knowledge) ?? CatalogDay("\(knowledge)-01")
    }
}

// MARK: - API description

/// OpenAI's OpenAPI description, reduced to what the catalog reads: the ids of the models its text APIs list, and the
/// effort words.
struct OpenAIAPIDescription: OpenAPIDescription {
    /// A schema, reduced to the string `enum` values of its `anyOf` choices.
    struct Schema: OpenAPIWordSchema {
        fileprivate let choices: [Choice]

        private enum CodingKeys: String, CodingKey {
            case choices = "anyOf"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        }

        /// The string values of every choice, in order, each once.
        var values: [String] {
            choices.flatMap(\.values).uniqued()
        }
    }

    /// One choice of a schema's `anyOf`: its string values.
    fileprivate struct Choice: Decodable {
        let values: [String]

        private enum CodingKeys: String, CodingKey {
            case values = "enum"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            values = container.decodeStringValues(forKey: .values)
        }
    }

    /// The schemas that list model ids: Chat Completions' models, which the Responses API takes too, and the models
    /// only the Responses API takes.
    static let modelIDSchemaNames = ["ModelIdsShared", "ModelIdsResponses"]

    let components: OpenAPIComponents<Schema>

    /// The ids of the models the description lists for Chat Completions and the Responses API. OpenAI doesn't keep
    /// these lists whole, so they don't decide which models the catalog lists.
    func listedModelIDs() throws(MissingSchema) -> Set<String> {
        var ids: Set<String> = []
        for name in Self.modelIDSchemaNames {
            ids.formUnion(try words(ofSchema: name))
        }
        return ids
    }

    /// Every effort word, highest first, as the description lists them lowest first.
    func efforts() throws(MissingSchema) -> [String] {
        try words(ofSchema: Self.effortSchemaName).reversed()
    }
}

// MARK: - models.dev

/// The models.dev catalog, reduced to OpenAI's models and the facts the catalog reads about them: what each takes and
/// does, which OpenAI's own model list doesn't say.
struct ModelsDevCatalog: Decodable {
    /// One of OpenAI's models.
    fileprivate struct Model: Decodable {
        struct Modalities: Decodable {
            let input: [String]
            let output: [String]
        }

        struct Limit: Decodable {
            let context: Int?
        }

        /// A way a request can set the model's reasoning, such as its `effort`, with the values it takes.
        struct ReasoningOption: Decodable {
            let type: String
            let values: [String]?
        }

        let name: String
        /// The kind of model, such as `image` or `embedding`, or `nil` for a model that generates text.
        let type: String?
        let reasoning: Bool?
        private let reasoningOptions: [ReasoningOption]?
        let toolCall: Bool?
        let structuredOutput: Bool?
        let temperature: Bool?
        /// The month or day the training data ends, as `yyyy-MM` or `yyyy-MM-dd`.
        let knowledge: String?
        let modalities: Modalities
        let limit: Limit?

        private enum CodingKeys: String, CodingKey {
            case name, type, reasoning, temperature, knowledge, modalities, limit
            case reasoningOptions = "reasoning_options"
            case toolCall = "tool_call"
            case structuredOutput = "structured_output"
        }

        /// The effort words the model takes, in models.dev's order, lowest first.
        var efforts: [String] {
            reasoningOptions?.first { $0.type == ModelsDevCatalog.effortOption }?.values ?? []
        }
    }

    private struct Provider: Decodable {
        let models: [String: Entry]
    }

    /// A model's entry, or `nil` for one that doesn't decode, so one broken entry, such as an image model's the catalog
    /// never reads, doesn't fail the rest.
    private struct Entry: Decodable {
        let model: Model?

        init(from decoder: any Decoder) throws {
            model = try? Model(from: decoder)
        }
    }

    /// The kind of reasoning option that lists the efforts.
    private static let effortOption = "effort"

    /// The provider's key in the catalog.
    private static let providerKey = "openai"

    /// OpenAI's models, by id, without those whose entries don't decode.
    fileprivate let models: [String: Model]

    /// The ids of the models whose entries don't decode, sorted.
    let undecodedIDs: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: JSONKey.self)
        let entries = try container.decode(Provider.self, forKey: JSONKey(stringValue: Self.providerKey)).models
        models = entries.compactMapValues(\.model)
        undecodedIDs = entries.filter { $0.value.model == nil }.keys.sorted()
    }

    static func decoded(from data: Data) throws -> ModelsDevCatalog {
        try JSONDecoder().decode(ModelsDevCatalog.self, from: data)
    }

    /// OpenAI's part of the catalog as a JSON document whose models are a list, so its shape doesn't name each model's
    /// id: `{"models": [...]}`.
    ///
    /// - Throws: An error when `data` isn't the catalog.
    static func shapeDocument(of data: Data) throws -> Data {
        guard let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let provider = catalog[providerKey] as? [String: Any], let models = provider["models"] as? [String: Any]
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "It has no \(providerKey) models."))
        }
        let sorted = models.sorted { $0.key < $1.key }.map(\.value)
        return try JSONSerialization.data(withJSONObject: ["models": sorted], options: [.sortedKeys])
    }
}

/// A JSON key named at run time.
private struct JSONKey: CodingKey {
    let stringValue: String

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    var intValue: Int? { nil }

    init?(intValue: Int) {
        nil
    }
}
