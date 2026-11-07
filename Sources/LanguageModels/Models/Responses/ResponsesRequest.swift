import Foundation
package import FoundationModels
package import LanguageModelsCore

// MARK: - Request

extension Responses {
    /// One request in the format: what the format read of Foundation Models' request, and what a provider adds or
    /// chooses.
    ///
    /// The format writes its members in a fixed order: `model`, `input`, `stream`, `store`, `include`, `tools`,
    /// `tool_choice`, `text`, `reasoning`, `temperature`, `top_p`, `max_output_tokens` and `metadata`, each only when the
    /// request sets it, then the provider's own in the order they're written, and leaves out the ones its models don't
    /// list or don't take with the request. An exchange's `prepare(_:)` adds the provider's members and makes the few
    /// choices a provider has about the format's: it can't change the input or the settings the app asked for. Every
    /// part is written the same way each time, so a host's prompt cache stays valid across requests.
    package struct Request {
        // MARK: What the format read

        /// Foundation Models' request, for its tool calling mode, schema and reasoning level.
        package let generation: LanguageModelExecutorGenerationRequest

        /// The id of the transcript's first prompt, which stays the same for the whole session; `nil` before the first
        /// prompt.
        package let firstPromptID: String?

        /// Whether the session has tools, which the format sends as functions.
        package var hasSessionTools: Bool {
            !sessionTools.isEmpty
        }

        // MARK: What an exchange adds or chooses

        /// The provider's own members, which go after the format's. Their keys are never the format's own.
        package var members = JSONObject()

        /// Whether the session's tools, and with them `tool_choice`, go out.
        package var sendsSessionTools = true

        /// Tools that run on the provider's servers, sent after the session's in `tools`.
        package var serverTools: [JSONValue] = []

        /// The `reasoning` member, or `nil` to leave it out, so the model reasons as it does by default.
        package var reasoning: Reasoning?

        /// A reasoning level the provider sends as another effort, or leaves out, which the request logs.
        package var movedEffort: MovedEffort?

        /// Whether the provider keeps the response, as `store` asks.
        package var storage = Storage.automatic

        /// Whether the response carries each reasoning item's reasoning encrypted, as `include` asks, so the item can go
        /// back on later turns whether or not the provider keeps the response.
        package var asksForEncryptedReasoning = false

        /// Members added to `text` after its format, such as `verbosity`.
        package var textMembers = JSONObject()

        /// Members the request leaves out although the models list them, because the provider doesn't take them with the
        /// request's other settings, such as `temperature` while a model reasons. The request logs each one.
        package var leftOutMembers: Set<Member> = []

        // MARK: What the format keeps

        /// The transcript entries that carry an image, which an error for an image the host rejects names.
        let imageEntries: [Transcript.Entry]

        private let name: String
        private let providerName: String
        private let sampling: Sampling
        private let unsupportedMembers: Set<Member>
        private let input: Responses.Input
        private let sessionTools: [FunctionTool]
        private let textFormats: (full: TextFormat, portable: TextFormat)?
        private let metadata: (json: JSONValue?, droppedKeys: [String])
    }
}

extension Responses.Request {
    /// Whether the provider keeps the response.
    package enum Storage: Sendable {
        /// `store` stays out of the body, so the provider's default applies.
        case automatic

        /// `store` is `true`.
        case stored

        /// `store` is `false`, so later turns send back only the reasoning items that carry their reasoning encrypted,
        /// which ``Responses/Request/asksForEncryptedReasoning`` asks for.
        case notStored
    }
}

extension Responses {
    /// The key of a member of a request's body: one of the format's, or one a provider adds.
    package struct Member: ProviderVocabulary {
        fileprivate static let model: Self = "model"
        fileprivate static let input: Self = "input"
        fileprivate static let stream: Self = "stream"
        fileprivate static let store: Self = "store"
        fileprivate static let include: Self = "include"
        package static let tools: Self = "tools"
        package static let toolChoice: Self = "tool_choice"
        fileprivate static let text: Self = "text"
        package static let reasoning: Self = "reasoning"
        package static let temperature: Self = "temperature"
        package static let topP: Self = "top_p"
        package static let maxOutputTokens: Self = "max_output_tokens"
        fileprivate static let metadata: Self = "metadata"

        /// The body's members that aren't options: the model, the input and `stream`.
        static var nonOptions: Set<String> {
            [model.rawValue, input.rawValue, stream.rawValue]
        }

        package let rawValue: String

        package init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

// MARK: - Reading

extension Responses.Request {
    /// The request for Foundation Models' request, before its exchange prepares it.
    ///
    /// - Parameters:
    ///   - generation: Foundation Models' request.
    ///   - model: The model, whose data says how the format reads the request.
    ///   - exchange: The provider's part, which checks the attachments and picks the reasoning that goes back.
    /// - Throws: `LanguageModelError` when the format or the exchange can't take the transcript, the tools or the
    ///   schema, and the exchange's errors.
    init<Exchange: Responses.Exchange>(
        _ generation: LanguageModelExecutorGenerationRequest,
        model: Responses.Model<Exchange>,
        exchange: Exchange
    ) throws {
        input = try Responses.Input(generation.transcript, model: model, exchange: exchange)
        sessionTools = try Self.tools(generation)
        textFormats = try generation.schema.map(Self.textFormats)
        sampling = Sampling(generation.generationOptions, temperatureRange: 0...2)
        metadata = RequestMetadata.limited(generation.metadata)
        self.generation = generation
        name = model.name
        providerName = model.providerName
        unsupportedMembers = model.unsupportedMembers
        firstPromptID = generation.transcript.firstPromptID
        imageEntries = input.imageEntries
    }

    /// The session's tools as functions, or none when the request has none.
    ///
    /// Foundation Models sends no tools when tool calling is disallowed, so there's nothing to forbid here.
    private static func tools(_ request: LanguageModelExecutorGenerationRequest) throws -> [FunctionTool] {
        try request.enabledToolDefinitions.map { tool in
            FunctionTool(name: tool.name, description: tool.description, parameters: try JSONValue(tool.parameters, strict: false))
        }
    }

    /// Structured outputs with a strict schema, in full and in portable form.
    ///
    /// Some hosts reject constraints such as `minimum`, `maxItems` and `pattern`, so the portable form moves them into
    /// the description, where the model still reads them.
    private static func textFormats(_ schema: GenerationSchema) throws -> (full: TextFormat, portable: TextFormat) {
        let json = try JSONValue(schema, strict: true)
        return (TextFormat(name: schema.wireName, schema: json), TextFormat(name: schema.wireName, schema: json.portableSchema))
    }
}

// MARK: - Body

extension Responses.Request {
    /// The request's body, with the exchange's members and choices. Its adjustments are, in the log's order, settings
    /// the models don't list, the provider doesn't take or the format has no member for, then a token limit below the
    /// fewest the format takes, then metadata it leaves out, then a moved reasoning effort.
    ///
    /// - Throws: An error when a member can't be encoded.
    func body() throws -> RequestBody {
        let options = generation.generationOptions
        let sendsTools = sendsSessionTools && hasSessionTools
        let tools = try (sendsTools ? sessionTools.map(JSONValueEncoder.encode) : []) + serverTools
        let tokenLimit = options.maximumResponseTokens.map { max($0, Self.fewestOutputTokens) }
        var body: JSONObject = [
            Responses.Member.model.rawValue: .string(name),
            Responses.Member.input.rawValue: try input.json(for: storage),
            Responses.Member.stream.rawValue: true,
            Responses.Member.store.rawValue: Self.store(storage),
            Responses.Member.include.rawValue: asksForEncryptedReasoning ? .array([.string(Self.encryptedReasoning)]) : nil,
            Responses.Member.tools.rawValue: tools.isEmpty ? nil : .array(tools),
            Responses.Member.toolChoice.rawValue: sendsTools ? options.toolCallingMode?.toolChoice : nil,
            Responses.Member.text.rawValue: try text(format: textFormats?.full),
            Responses.Member.reasoning.rawValue: try reasoning.flatMap { $0.isEmpty ? nil : try JSONValueEncoder.encode($0) },
            Responses.Member.temperature.rawValue: sampling.temperature.map(JSONValue.number),
            Responses.Member.topP.rawValue: sampling.topP.map(JSONValue.number),
            Responses.Member.maxOutputTokens.rawValue: tokenLimit.map(JSONValue.integer),
            Responses.Member.metadata.rawValue: metadata.json,
        ]
        body.add(members, from: providerName)

        var adjustments: [RequestAdjustment] = metadata.droppedKeys.isEmpty ? [] : [.droppedMetadata(keys: metadata.droppedKeys)]
        let present = body.members.map(\.key)
        let unlisted = present.filter { unsupportedMembers.contains(Responses.Member(rawValue: $0)) }
        if !unlisted.isEmpty {
            for key in unlisted { body[key] = nil }
            adjustments.append(.unlistedParameters(unlisted))
        }
        // The format has no member for `top_k` or a seed, and the exchange leaves out what the provider doesn't take with
        // the request's other settings.
        let leftOut = present.filter { !unlisted.contains($0) && leftOutMembers.contains(Responses.Member(rawValue: $0)) }
        for key in leftOut { body[key] = nil }
        let unsent = leftOut + (sampling.topK == nil ? [] : [Self.topK]) + (sampling.seed == nil ? [] : [Self.seed])
        if !unsent.isEmpty {
            adjustments.append(.unsentSettings(unsent))
        }
        if let requested = options.maximumResponseTokens, let sent = tokenLimit, sent != requested,
            body[Responses.Member.maxOutputTokens.rawValue] != nil
        {
            adjustments.append(.raisedTokenLimit(requested: requested, sent: sent))
        }
        if let movedEffort {
            adjustments.append(.movedEffort(requested: movedEffort.requested, sent: movedEffort.sent))
        }

        var portable: JSONValue?
        if let format = textFormats?.portable, body[Responses.Member.text.rawValue] != nil {
            var members = body
            members[Responses.Member.text.rawValue] = try text(format: format)
            portable = .object(members)
        }
        return RequestBody(json: .object(body), portableJSON: portable, adjustments: RequestAdjustment.inLogOrder(adjustments))
    }

    /// The `text` member: the response schema's format, then the exchange's members, or `nil` when there's neither.
    private func text(format: TextFormat?) throws -> JSONValue? {
        var text = JSONObject()
        if let format { text["format"] = try JSONValueEncoder.encode(format) }
        for member in textMembers.members { text[member.key] = member.value }
        return text.members.isEmpty ? nil : .object(text)
    }

    /// The value of `store`, or `nil` when it stays out of the body.
    private static func store(_ storage: Storage) -> JSONValue? {
        switch storage {
        case .automatic: nil
        case .stored: true
        case .notStored: false
        }
    }

    /// What `include` asks for so that each reasoning item carries its reasoning encrypted.
    private static let encryptedReasoning = "reasoning.encrypted_content"

    /// The names of the sampling settings the format has no member for.
    private static let topK = "top_k"
    private static let seed = "seed"

    /// The fewest output tokens the format takes as `max_output_tokens`.
    private static let fewestOutputTokens = 16
}

// MARK: - Wire

extension Responses.Request {
    /// The `reasoning` member: how hard the model reasons and what it reports of its reasoning. A value left `nil`
    /// stays out of the member.
    package struct Reasoning: Encodable, Sendable, Equatable {
        /// The effort, such as `low`, in the provider's word for it.
        private var effort: String?

        /// The summary of its reasoning the model writes, such as `auto`.
        private var summary: String?

        package init(effort: String? = nil, summary: String? = nil) {
            self.effort = effort
            self.summary = summary
        }

        /// Whether the member carries no value, so it stays out of the body.
        fileprivate var isEmpty: Bool {
            effort == nil && summary == nil
        }
    }
}

/// One of the session's tools, as a function with `strict` off, so the host doesn't rewrite its schema.
private struct FunctionTool: Encodable {
    let name: String
    let description: String

    /// The JSON Schema of the arguments, which no fixed type can hold.
    let parameters: JSONValue

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        try container.encode("function", forKey: "type")
        try container.encode(name, forKey: "name")
        try container.encode(description, forKey: "description")
        try container.encode(parameters, forKey: "parameters")
        // Left out, `strict` defaults to on, and OpenAI then holds the arguments to a strict form of the schema
        // that it makes up.
        try container.encode(false, forKey: "strict")
    }
}

/// Structured outputs with a strict schema, as `text.format`.
private struct TextFormat: Encodable {
    let name: String

    /// The JSON Schema of the answer, which no fixed type can hold.
    let schema: JSONValue

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        try container.encode("json_schema", forKey: "type")
        try container.encode(name, forKey: "name")
        try container.encode(schema, forKey: "schema")
        try container.encode(true, forKey: "strict")
    }
}
