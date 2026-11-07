import Foundation
import FoundationModels
package import LanguageModelsCore

// MARK: - Request

/// The body of a Chat Completions `POST` for one Foundation Models request, with the dialect's members.
///
/// The format writes its members in a fixed order, then adds the dialect's own, puts them all in the dialect's order
/// and leaves out the ones its models don't list. Every part is written the same way each time, so a provider's prompt
/// cache stays valid across requests.
struct ChatCompletionRequest: FormatRequest {
    let body: JSONValue

    /// The same body with its response schema in portable form, to send instead when a host rejects a constraint of
    /// the full schema, or `nil` when the request has no schema or already sends the portable one.
    let portableSchemaBody: JSONValue?

    /// What the request leaves out or changes from what the app asked for, so that its models and the provider take
    /// it: settings the models don't list, then metadata past the limits, then a moved reasoning effort.
    let adjustments: [RequestAdjustment]

    /// The transcript entries that carry an image, which an error for an image the host rejects names.
    let imageEntries: [Transcript.Entry]

    /// The request for Foundation Models' request in a dialect.
    ///
    /// - Throws: `LanguageModelError` when the format or the dialect can't take the transcript, the tools or the
    ///   schema, and the dialect's errors.
    init<Dialect: ChatCompletionsDialect>(_ request: LanguageModelExecutorGenerationRequest, dialect: Dialect) throws {
        let schema = request.schema
        let messages = try Messages(request.transcript, dialect: dialect)
        let options = request.generationOptions
        let sessionTools = try Self.tools(request)
        let responseFormats = try schema.map(Self.responseFormats)
        let sampling = Sampling(options, temperatureRange: 0...2)
        let metadata = RequestMetadata.limited(request.metadata)
        let plan = try dialect.body(BodyContext(request, sampling: sampling, carriesPDF: messages.carriesPDF))

        let sendsSessionTools = plan.sessionTools == .sent && !sessionTools.isEmpty
        let tools =
            try (sendsSessionTools ? sessionTools.map(JSONValueEncoder.encode) : [])
            + plan.serverTools.map { try JSONValueEncoder.encode($0) }
        let marks = try plan.instructionsMark.map { try JSONValueEncoder.members(of: $0) }
        let sentFormat = plan.schema == .portable ? responseFormats?.portable : responseFormats?.full
        let tokenLimit: ChatCompletions.Member = plan.tokenLimit == .maxTokens ? .maxTokens : .maxCompletionTokens
        var members: JSONObject = [
            ChatCompletions.Member.model.rawValue: .string(dialect.modelID.rawValue),
            ChatCompletions.Member.messages.rawValue: try JSONValueEncoder.encode(
                marks.map(messages.markingLastInstructions) ?? messages.messages),
            ChatCompletions.Member.stream.rawValue: true,
            ChatCompletions.Member.tools.rawValue: tools.isEmpty ? nil : .array(tools),
            ChatCompletions.Member.toolChoice.rawValue: sendsSessionTools ? options.toolCallingMode?.toolChoice : nil,
            ChatCompletions.Member.responseFormat.rawValue: try sentFormat.map(JSONValueEncoder.encode),
            ChatCompletions.Member.temperature.rawValue: sampling.temperature.map(JSONValue.number),
            ChatCompletions.Member.topP.rawValue: sampling.topP.map(JSONValue.number),
            ChatCompletions.Member.seed.rawValue: sampling.seed.map(Sampling.json(seed:)),
            // The token limit goes out as the request asks: a host that routes it picks a model that answers that long.
            tokenLimit.rawValue: options.maximumResponseTokens.map(JSONValue.integer),
            ChatCompletions.Member.metadata.rawValue: metadata.json,
        ]
        for extra in try JSONValueEncoder.members(of: plan.extras).members {
            assert(members[extra.key] == nil, "\(Dialect.name) adds \(extra.key), which the format writes.")
            if members[extra.key] == nil { members[extra.key] = extra.value }
        }
        members = members.ordered(by: Dialect.memberOrder.map(\.rawValue))

        var adjustments: [RequestAdjustment] = metadata.droppedKeys.isEmpty ? [] : [.droppedMetadata(keys: metadata.droppedKeys)]
        let unlisted = members.members.map(\.key).filter { key in
            let member = ChatCompletions.Member(rawValue: key)
            return Dialect.listedMembers.contains(member) && !dialect.lists(member)
        }
        if !unlisted.isEmpty {
            for key in unlisted { members[key] = nil }
            adjustments.append(.unlistedParameters(unlisted))
        }
        if let moved = plan.movedEffort {
            adjustments.append(.movedEffort(requested: moved.requested, sent: moved.sent))
        }

        body = .object(members)
        if let format = responseFormats?.portable, plan.schema == .full, members[ChatCompletions.Member.responseFormat.rawValue] != nil {
            var portable = members
            portable[ChatCompletions.Member.responseFormat.rawValue] = try JSONValueEncoder.encode(format)
            portableSchemaBody = .object(portable)
        } else {
            portableSchemaBody = nil
        }
        imageEntries = messages.imageEntries
        self.adjustments = RequestAdjustment.inLogOrder(adjustments)
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

/// What a dialect's ``ChatCompletionsDialect/body(_:)`` adds to a request's body, and the choices it makes about the
/// format's own members.
///
/// The format writes its members in a fixed order: `model`, `messages`, `stream`, the session's `tools` and
/// `tool_choice`, `response_format`, `temperature`, `top_p`, `seed`, the token limit and `metadata`, each only when the
/// request sets it. The plan adds the provider's members and makes the few choices a provider has about the format's:
/// it can't change the messages or the settings the app asked for.
package struct ChatCompletionsBodyPlan<Extras: Encodable> {
    /// The provider's own members.
    package var extras: Extras

    /// Whether the session's tools, and with them `tool_choice`, go out.
    package var sessionTools = SessionTools.sent

    /// Tools that run on the provider's servers, sent after the session's in `tools`.
    package var serverTools: [any Encodable & Sendable] = []

    /// The member the token limit goes in.
    package var tokenLimit = TokenLimit.maxCompletionTokens

    /// The form the response schema goes in.
    package var schema = SchemaForm.full

    /// Members added to the last content part of the last instructions, such as a cache mark, so the tools and
    /// instructions before it are cached on the host; `nil` for none.
    package var instructionsMark: (any Encodable & Sendable)?

    /// A reasoning level the provider sends as another effort, or leaves out, which the request logs.
    package var movedEffort: MovedEffort?

    package init(extras: Extras) {
        self.extras = extras
    }

    /// Whether the session's tools go out.
    package enum SessionTools: Sendable {
        /// The session's tools go out as functions, with `tool_choice` when the app chose how they're called.
        case sent

        /// Neither the session's tools nor `tool_choice` go out, as for models that don't take tools.
        case leftOut
    }

    /// The member the request's token limit goes in.
    package enum TokenLimit: Sendable {
        /// `max_completion_tokens`, the format's own.
        case maxCompletionTokens

        /// `max_tokens`, the older member, for models that don't take `max_completion_tokens`.
        case maxTokens
    }

    /// The form of the response schema.
    package enum SchemaForm: Sendable {
        /// The full schema, and the portable one only if the host rejects one of its constraints.
        case full

        /// The portable schema from the start, which carries its constraints in descriptions, as for a host known to
        /// reject them.
        case portable
    }
}

extension ChatCompletions {
    /// The key of a member of a request's body: one of the format's, or one a provider adds.
    ///
    /// A provider's ``ChatCompletionsDialect/BodyExtras`` encodes its members under these keys, so each key is spelled
    /// once.
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
        package static let formatOrder: [Member] = [
            model, messages, stream, tools, toolChoice, responseFormat, temperature, topP, seed, maxCompletionTokens, maxTokens, metadata,
        ]

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

// MARK: - Wire

extension ChatCompletionRequest {
    /// One of the session's tools, as a function.
    struct FunctionTool: Encodable {
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
    struct ResponseFormat: Encodable {
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
}
