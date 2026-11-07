import Foundation
package import FoundationModels
package import LanguageModelsCore

// MARK: - Request

extension ChatCompletions {
    /// One request in the format: what the format read of Foundation Models' request, and what a provider adds or
    /// chooses.
    ///
    /// The format writes its members in a fixed order: `model`, `messages`, `stream`, the session's `tools` and
    /// `tool_choice`, `response_format`, `temperature`, `top_p`, `seed`, the token limit and `metadata`, each only when the
    /// request sets it, then adds the provider's own, puts them all in the model's order and leaves out the ones its models
    /// don't list. An exchange's `prepare(_:)` adds the provider's headers and members and makes the few choices a provider
    /// has about the format's: it can't change the messages or the settings the app asked for. Every part is written the
    /// same way each time, so a provider's prompt cache stays valid across requests.
    package struct Request {
        // MARK: What the format read

        /// Foundation Models' request, for its tool calling mode, schema and reasoning level.
        package let generation: LanguageModelExecutorGenerationRequest

        /// The sampling settings the app asked for, within the format's temperature range.
        package let sampling: Sampling

        /// Whether a message carries a PDF.
        package let carriesPDF: Bool

        /// The id of the transcript's first prompt, which stays the same for the whole session; `nil` before the first
        /// prompt.
        package let firstPromptID: String?

        /// Whether the session has tools, which the format sends as functions.
        package var hasSessionTools: Bool {
            !sessionTools.isEmpty
        }

        // MARK: What an exchange adds or chooses

        /// The provider's headers, which take precedence over the authentication's.
        package var headers: [String: String] = [:]

        /// The provider's own members, which go in the model's order with the format's. Their keys are never the format's
        /// own.
        package var members = JSONObject()

        /// Whether the session's tools, and with them `tool_choice`, go out.
        package var sendsSessionTools = true

        /// Tools that run on the provider's servers, sent after the session's in `tools`.
        package var serverTools: [JSONValue] = []

        /// The member the token limit goes in: `max_completion_tokens`, the format's own, or `max_tokens`, the older
        /// member, for models that don't take it.
        package var tokenLimitMember = Member.maxCompletionTokens

        /// Whether the portable schema, which carries its constraints in descriptions, goes out from the start, as for a
        /// host known to reject them, rather than only if the host rejects a constraint of the full one.
        package var usesPortableSchema = false

        /// Members added to the last content part of the last instructions, such as a cache mark, so the tools and
        /// instructions before it are cached on the host; `nil` for none.
        package var instructionsMark: JSONObject?

        /// A reasoning level the provider sends as another effort, or leaves out, which the request logs.
        package var movedEffort: MovedEffort?

        // MARK: What the format keeps

        /// The transcript entries that carry an image, which an error for an image the host rejects names.
        let imageEntries: [Transcript.Entry]

        private let name: String
        private let providerName: String
        private let memberOrder: [Member]
        private let unsupportedMembers: Set<Member>
        private let messages: ChatCompletions.Messages
        private let sessionTools: [FunctionTool]
        private let responseFormats: (full: ResponseFormat, portable: ResponseFormat)?
        private let metadata: (json: JSONValue?, droppedKeys: [String])
    }
}

extension ChatCompletions {
    /// The key of a member of a request's body: one of the format's, or one a provider adds.
    ///
    /// A provider encodes its members under these keys, so each key is spelled once.
    package struct Member: ProviderVocabulary, CodingKey {
        package static let model: Self = "model"
        package static let messages: Self = "messages"
        package static let stream: Self = "stream"
        package static let tools: Self = "tools"
        package static let toolChoice: Self = "tool_choice"
        package static let responseFormat: Self = "response_format"
        package static let temperature: Self = "temperature"
        package static let topP: Self = "top_p"
        package static let seed: Self = "seed"
        package static let maxCompletionTokens: Self = "max_completion_tokens"
        package static let maxTokens: Self = "max_tokens"
        package static let metadata: Self = "metadata"

        /// The order the format writes its members in, each only when the request sets it.
        static let formatOrder: [Member] = [
            model, messages, stream, tools, toolChoice, responseFormat, temperature, topP, seed, maxCompletionTokens, maxTokens, metadata,
        ]

        /// The body's members that aren't options: the model, the transcript and `stream`.
        static var nonOptions: Set<String> {
            [model.rawValue, messages.rawValue, stream.rawValue]
        }

        package let rawValue: String

        package init(rawValue: String) {
            self.rawValue = rawValue
        }

        package var description: String { rawValue }

        package var stringValue: String { rawValue }

        package init(stringValue: String) {
            rawValue = stringValue
        }

        package var intValue: Int? { nil }

        package init?(intValue: Int) {
            nil
        }
    }
}

// MARK: - Reading

extension ChatCompletions.Request {
    /// The request for Foundation Models' request, before its exchange prepares it.
    ///
    /// - Parameters:
    ///   - generation: Foundation Models' request.
    ///   - model: The model, whose data says how the format reads the request.
    ///   - exchange: The provider's part, which checks the attachments and picks the reasoning that goes back.
    /// - Throws: `LanguageModelError` when the format or the exchange can't take the transcript, the tools or the
    ///   schema, and the exchange's errors.
    init<Exchange: ChatCompletions.Exchange>(
        _ generation: LanguageModelExecutorGenerationRequest,
        model: ChatCompletions.Model<Exchange>,
        exchange: Exchange
    ) throws {
        messages = try ChatCompletions.Messages(generation.transcript, model: model, exchange: exchange)
        sessionTools = try Self.tools(generation)
        responseFormats = try generation.schema.map(Self.responseFormats)
        sampling = Sampling(generation.generationOptions, temperatureRange: 0...2)
        metadata = RequestMetadata.limited(generation.metadata)
        self.generation = generation
        name = model.name
        providerName = model.providerName
        memberOrder = model.memberOrder
        unsupportedMembers = model.unsupportedMembers
        carriesPDF = messages.carriesPDF
        firstPromptID = generation.transcript.firstPromptID
        imageEntries = messages.imageEntries
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
    private static func responseFormats(_ schema: GenerationSchema) throws -> (full: ResponseFormat, portable: ResponseFormat) {
        let json = try JSONValue(schema, strict: true)
        return (ResponseFormat(name: schema.wireName, schema: json), ResponseFormat(name: schema.wireName, schema: json.portableSchema))
    }
}

// MARK: - Body

extension ChatCompletions.Request {
    /// The request's body, with the exchange's members and choices. Its adjustments are, in the log's order, settings
    /// the models don't list, then metadata past the limits, then a moved reasoning effort.
    ///
    /// - Throws: An error when a member can't be encoded.
    func body() throws -> RequestBody {
        let options = generation.generationOptions
        let sendsTools = sendsSessionTools && hasSessionTools
        let tools = try (sendsTools ? sessionTools.map(JSONValueEncoder.encode) : []) + serverTools
        let sentFormat = usesPortableSchema ? responseFormats?.portable : responseFormats?.full
        var body: JSONObject = [
            ChatCompletions.Member.model.rawValue: .string(name),
            ChatCompletions.Member.messages.rawValue: try messages.json(marking: instructionsMark),
            ChatCompletions.Member.stream.rawValue: true,
            ChatCompletions.Member.tools.rawValue: tools.isEmpty ? nil : .array(tools),
            ChatCompletions.Member.toolChoice.rawValue: sendsTools ? options.toolCallingMode?.toolChoice : nil,
            ChatCompletions.Member.responseFormat.rawValue: try sentFormat.map(JSONValueEncoder.encode),
            ChatCompletions.Member.temperature.rawValue: sampling.temperature.map(JSONValue.number),
            ChatCompletions.Member.topP.rawValue: sampling.topP.map(JSONValue.number),
            ChatCompletions.Member.seed.rawValue: sampling.seed.map(Sampling.json(seed:)),
            // The token limit goes out as the request asks: a host that routes it picks a model that answers that long.
            tokenLimitMember.rawValue: options.maximumResponseTokens.map(JSONValue.integer),
            ChatCompletions.Member.metadata.rawValue: metadata.json,
        ]
        body.add(members, from: providerName)
        body = body.ordered(by: memberOrder.map(\.rawValue))

        var adjustments: [RequestAdjustment] = metadata.droppedKeys.isEmpty ? [] : [.droppedMetadata(keys: metadata.droppedKeys)]
        let unlisted = body.members.map(\.key).filter { unsupportedMembers.contains(ChatCompletions.Member(rawValue: $0)) }
        if !unlisted.isEmpty {
            for key in unlisted { body[key] = nil }
            adjustments.append(.unlistedParameters(unlisted))
        }
        if let movedEffort {
            adjustments.append(.movedEffort(requested: movedEffort.requested, sent: movedEffort.sent))
        }

        var portable: JSONValue?
        if let format = responseFormats?.portable, !usesPortableSchema, body[ChatCompletions.Member.responseFormat.rawValue] != nil {
            var members = body
            members[ChatCompletions.Member.responseFormat.rawValue] = try JSONValueEncoder.encode(format)
            portable = .object(members)
        }
        return RequestBody(json: .object(body), portableJSON: portable, adjustments: RequestAdjustment.inLogOrder(adjustments))
    }
}

// MARK: - Wire

/// One of the session's tools, as a function.
private struct FunctionTool: Encodable {
    let name: String
    let description: String

    /// The JSON Schema of the arguments, which no fixed type can hold.
    let parameters: JSONValue

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        try container.encode("function", forKey: "type")
        var function = container.nestedContainer(keyedBy: JSONKey.self, forKey: "function")
        try function.encode(name, forKey: "name")
        try function.encode(description, forKey: "description")
        try function.encode(parameters, forKey: "parameters")
    }
}

/// Structured outputs with a strict schema.
private struct ResponseFormat: Encodable {
    let name: String

    /// The JSON Schema of the answer, which no fixed type can hold.
    let schema: JSONValue

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        try container.encode("json_schema", forKey: "type")
        var format = container.nestedContainer(keyedBy: JSONKey.self, forKey: "json_schema")
        try format.encode(name, forKey: "name")
        try format.encode(true, forKey: "strict")
        try format.encode(schema, forKey: "schema")
    }
}
