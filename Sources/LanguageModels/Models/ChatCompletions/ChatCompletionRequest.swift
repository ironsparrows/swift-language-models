import Foundation
import FoundationModels
import LanguageModelsCore

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
