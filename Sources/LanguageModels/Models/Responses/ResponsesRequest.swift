import Foundation
import FoundationModels
import LanguageModelsCore

/// The body of a Responses `POST` for one Foundation Models request, with the dialect's members.
///
/// The format writes its members in a fixed order, then the dialect's own in the order the dialect writes them, and
/// leaves out the ones its models don't list or don't take with the request. Every part is written the same way each
/// time, so a provider's prompt cache stays valid across requests.
struct ResponsesRequest: FormatRequest {
    let body: JSONValue

    /// The same body with its response schema in portable form, to send instead when a host rejects a constraint of
    /// the full schema, or `nil` when the request has no schema.
    let portableSchemaBody: JSONValue?

    /// What the request leaves out or changes from what the app asked for, so that its models and the provider take
    /// it, in the log's order: settings the models don't list or the provider doesn't take, then a token limit below
    /// the fewest the format takes, then metadata past the limits, then a moved reasoning effort.
    let adjustments: [RequestAdjustment]

    /// The transcript entries that carry an image, which an error for an image the host rejects names.
    let imageEntries: [Transcript.Entry]

    /// The request for Foundation Models' request in a dialect.
    ///
    /// - Throws: `LanguageModelError` when the format or the dialect can't take the transcript, the tools or the
    ///   schema, and the dialect's errors.
    init<Dialect: ResponsesDialect>(_ request: LanguageModelExecutorGenerationRequest, dialect: Dialect) throws {
        let schema = request.schema
        let input = try Input(request.transcript, dialect: dialect)
        let options = request.generationOptions
        let sessionTools = try Self.tools(request)
        let textFormats = try schema.map(Self.textFormats)
        let sampling = Sampling(options, temperatureRange: 0...2)
        let metadata = RequestMetadata.limited(request.metadata)
        let plan = try dialect.body(BodyContext(request, sampling: sampling, carriesPDF: input.carriesPDF))

        let sendsSessionTools = plan.sessionTools == .sent && !sessionTools.isEmpty
        let tools = try sendsSessionTools ? sessionTools.map(JSONValueEncoder.encode) : []
        let items = plan.storage == .notStored ? input.withEncryptedReasoningOnly : input.items
        let tokenLimit = options.maximumResponseTokens.map { max($0, Self.fewestOutputTokens) }
        var members: JSONObject = [
            Responses.Member.model.rawValue: .string(dialect.modelID.rawValue),
            Responses.Member.input.rawValue: try JSONValueEncoder.encode(items),
            Responses.Member.stream.rawValue: true,
            Responses.Member.store.rawValue: Self.store(plan.storage),
            Responses.Member.include.rawValue: plan.asksForEncryptedReasoning ? .array([.string(Self.encryptedReasoning)]) : nil,
            Responses.Member.tools.rawValue: tools.isEmpty ? nil : .array(tools),
            Responses.Member.toolChoice.rawValue: sendsSessionTools ? options.toolCallingMode?.toolChoice : nil,
            Responses.Member.text.rawValue: try Self.text(format: textFormats?.full, extras: plan.textExtras),
            Responses.Member.reasoning.rawValue: try plan.reasoning.flatMap { $0.isEmpty ? nil : try JSONValueEncoder.encode($0) },
            Responses.Member.temperature.rawValue: sampling.temperature.map(JSONValue.number),
            Responses.Member.topP.rawValue: sampling.topP.map(JSONValue.number),
            Responses.Member.maxOutputTokens.rawValue: tokenLimit.map(JSONValue.integer),
            Responses.Member.metadata.rawValue: metadata.json,
        ]
        for extra in try JSONValueEncoder.members(of: plan.extras).members {
            assert(members[extra.key] == nil, "\(Dialect.name) adds \(extra.key), which the format writes.")
            if members[extra.key] == nil { members[extra.key] = extra.value }
        }

        var adjustments: [RequestAdjustment] = metadata.droppedKeys.isEmpty ? [] : [.droppedMetadata(keys: metadata.droppedKeys)]
        let present = members.members.map(\.key)
        let unlisted = present.filter { key in
            let member = Responses.Member(rawValue: key)
            return Dialect.listedMembers.contains(member) && !dialect.lists(member)
        }
        if !unlisted.isEmpty {
            for key in unlisted { members[key] = nil }
            adjustments.append(.unlistedParameters(unlisted))
        }
        // The format has no member for `top_k` or a seed, and the plan leaves out what the provider doesn't take with
        // the request's other settings.
        let leftOut = present.filter { !unlisted.contains($0) && plan.leftOutMembers.contains(Responses.Member(rawValue: $0)) }
        for key in leftOut { members[key] = nil }
        let unsent = leftOut + (sampling.topK == nil ? [] : [Self.topK]) + (sampling.seed == nil ? [] : [Self.seed])
        if !unsent.isEmpty {
            adjustments.append(.unsentSettings(unsent))
        }
        if let requested = options.maximumResponseTokens, let sent = tokenLimit, sent != requested,
            members[Responses.Member.maxOutputTokens.rawValue] != nil
        {
            adjustments.append(.raisedTokenLimit(requested: requested, sent: sent))
        }
        if let moved = plan.movedEffort {
            adjustments.append(.movedEffort(requested: moved.requested, sent: moved.sent))
        }

        body = .object(members)
        if let format = textFormats?.portable, members[Responses.Member.text.rawValue] != nil {
            var portable = members
            portable[Responses.Member.text.rawValue] = try Self.text(format: format, extras: plan.textExtras)
            portableSchemaBody = .object(portable)
        } else {
            portableSchemaBody = nil
        }
        imageEntries = input.imageEntries
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
    private static func textFormats(_ schema: GenerationSchema) throws -> (full: TextFormat, portable: TextFormat) {
        let json = try JSONValue(schema, strict: true)
        return (TextFormat(name: schema.wireName, schema: json), TextFormat(name: schema.wireName, schema: json.portableSchema))
    }

    /// The `text` member: the response schema's format, then the dialect's members, or `nil` when there's neither.
    private static func text(format: TextFormat?, extras: (any Encodable & Sendable)?) throws -> JSONValue? {
        var text = JSONObject()
        if let format { text["format"] = try JSONValueEncoder.encode(format) }
        if let extras {
            for member in try JSONValueEncoder.members(of: extras).members { text[member.key] = member.value }
        }
        return text.members.isEmpty ? nil : .object(text)
    }

    private static func store(_ storage: ResponsesBodyPlan<some Encodable>.Storage) -> JSONValue? {
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
