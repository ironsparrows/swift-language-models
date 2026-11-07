package import Foundation
package import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

// MARK: - Channel

/// Where one answer's output goes: the Foundation Models channel events of its response, reasoning, tool-call and data
/// entries, whatever format the provider streams it in.
///
/// Each kind of output keeps one entry id for the whole answer, because the framework only merges events into the entry
/// they name. Reasoning text that arrives after the answer's text starts isn't shown. For a format that reads tagged
/// reasoning, a block in `<think>` or `<thinking>` tags that opens the answer's text is reasoning too, in arrival order
/// with the provider's reasoning; the reasoning entry keeps the block as the model wrote it, so it goes back where the
/// model put it. Tool-call fragments
/// are routed by index into one tool-calls entry, so parallel calls form one round. Each piece of data the model
/// generates becomes a data entry of its own. The answer ends with its metadata and usage on the entry that finishes
/// it, and with the pages it cites on its response entry.
struct AnswerChannel {
    private let channel: LanguageModelExecutorGenerationChannel

    /// The origin the answer's reasoning entry carries, so that only the provider's own reasoning goes back.
    private let origin: ReasoningOrigin

    private let responseEntryID = UUID().uuidString
    private let reasoningEntryID = UUID().uuidString
    private let toolCallsEntryID = UUID().uuidString

    private var sentText = ""
    private var hasText = false
    private var hasReasoning = false
    /// The reasoning block that opens the answer's text, or `nil` for a format that doesn't read one.
    private var taggedReasoning: TaggedReasoning?
    private var toolCalls = ToolCallAssembler()
    private var citations: [Citation] = []

    /// - Parameters:
    ///   - channel: Where the answer's events go.
    ///   - origin: The origin the answer's reasoning entry carries.
    ///   - readsTaggedReasoning: Whether a block in reasoning tags that opens the answer's text is reasoning, as for a
    ///     format whose models may write their reasoning there. A format with reasoning of its own sends such text as
    ///     the answer's.
    init(channel: LanguageModelExecutorGenerationChannel, origin: ReasoningOrigin, readsTaggedReasoning: Bool) {
        self.channel = channel
        self.origin = origin
        taggedReasoning = readsTaggedReasoning ? TaggedReasoning() : nil
    }

    /// The text sent to the response entry, or empty when the answer ends in tool calls, since the round that answers
    /// them comes after.
    var responseText: String {
        toolCalls.isEmpty ? sentText : ""
    }

    /// Whether any of the answer's output has arrived: text, reasoning or a tool call.
    var hasOutput: Bool {
        hasText || hasReasoning || !toolCalls.isEmpty
    }

    /// Whether a fragment of a tool call has arrived.
    var hasToolCalls: Bool {
        !toolCalls.isEmpty
    }

    /// Sends the next part of the answer's text, with a reasoning block in tags that opens it sent as reasoning when
    /// the format reads one.
    ///
    /// - Parameters:
    ///   - delta: The next part of the text.
    ///   - model: The model that answered, once known, which the reasoning entry names.
    mutating func appendText(_ delta: String, model: String?) async {
        await send(taggedReasoning?.split(delta) ?? TaggedReasoning.Split(text: delta), model: model)
    }

    /// Sends reasoning text, which shows only until the answer's text starts. Empty text starts the reasoning entry
    /// without text.
    ///
    /// - Parameters:
    ///   - text: The reasoning text.
    ///   - model: The model that answered, once known, which the reasoning entry names.
    mutating func appendReasoning(_ text: String, model: String?) async {
        if !hasReasoning {
            hasReasoning = true
            await channel.send(.reasoning(entryID: reasoningEntryID, action: .updateMetadata(reasoningMetadata(model: model))))
        }
        guard !text.isEmpty, !hasText else { return }
        await channel.send(.reasoning(entryID: reasoningEntryID, action: .appendText(text, tokenCount: 1)))
    }

    /// Adds one tool-call fragment to its call, as ``ToolCallAssembler/add(index:id:name:arguments:)`` routes it, and
    /// sends the arguments it starts or adds.
    mutating func addToolCall(index: Int?, id: String?, name: String?, arguments: String?) async {
        if let arguments = toolCalls.add(index: index, id: id, name: name, arguments: arguments) {
            await channel.send(arguments.event(in: toolCallsEntryID))
        }
    }

    /// Adds a page the answer cites, once.
    mutating func cite(_ citation: Citation) {
        if !citations.contains(citation) { citations.append(citation) }
    }

    /// Sends data the model generated as a data entry of its own.
    ///
    /// Before the OS version that has data entries, and in a build with an SDK before Xcode 27.2's, nothing is sent.
    func sendData(_ data: GeneratedData) async {
        #if canImport(FoundationModels, _version: 2.1.14)
        guard #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) else { return }
        await channel.send(.data(entryID: UUID().uuidString, action: .update(contentType: data.contentType, content: data.content)))
        #endif
    }

    /// Sends the text held back while it could still be the start of a reasoning block, once the stream is over.
    ///
    /// - Parameter model: The model that answered, which the reasoning entry names.
    private mutating func finishText(model: String?) async {
        guard let split = taggedReasoning?.finish() else { return }
        await send(split, model: model)
    }

    /// Ends the tool calls: sends empty JSON as the arguments of each call that got none.
    ///
    /// - Throws: The problem when a call never got its name or its arguments aren't a whole JSON object, before any
    ///   tool runs with them.
    private func finishToolCalls() async throws(StreamProblem) {
        let calls: [ToolCallAssembler.Arguments]
        do {
            calls = try toolCalls.finish()
        } catch {
            switch error {
            case .missingName: throw .toolCallWithoutName
            case .incompleteArguments(let toolName): throw .incompleteToolArguments(toolName: toolName)
            }
        }
        for arguments in calls {
            await channel.send(arguments.event(in: toolCallsEntryID))
        }
    }

    /// Ends an answer whose stream ended: sends the text held back, then empty JSON as the arguments of each call that
    /// got none, then the reasoning signature and the answer's facts and usage, unless the answer fails anyway.
    ///
    /// The answer fails, in this order, when the model declined, a content filter stopped it, it reached its token
    /// limit inside a tool call or a guided answer, the host says it failed, or a call never got its name or has
    /// arguments that aren't a whole JSON object. An answer cut off at its token limit otherwise ends like any other,
    /// with `length` as its finish reason, since Foundation Models has no error for it.
    ///
    /// - Parameters:
    ///   - report: What the format's own members reported about the answer.
    ///   - facts: What the provider adds to them.
    ///   - refusal: The refusal text the model sent, empty for none.
    ///   - requiresCompleteAnswer: Whether the answer must be whole, as a guided answer must.
    ///   - failedAnswer: The format's error for an answer the host says failed, or `nil` when it doesn't say so.
    /// - Throws: ``StreamProblem`` for a problem the format reports as a failure of its own, such as the token limit
    ///   reached inside a tool call, and otherwise the error the answer ends in, such as Foundation Models' refusal.
    mutating func finish(
        report: AnswerReport,
        facts: AnswerAdditions,
        refusal: String,
        requiresCompleteAnswer: Bool,
        failedAnswer: (any Error)? = nil
    ) async throws {
        await finishText(model: report.model)
        let ending = AnswerEnding(
            refusal: refusal, finishReason: report.finishReason, hasToolCalls: hasToolCalls,
            requiresCompleteAnswer: requiresCompleteAnswer)
        if ending == .tokenLimitInToolCall { throw StreamProblem.tokenLimitInToolCall }
        if let error = ending?.error(responseText: responseText, host: facts.host) ?? failedAnswer { throw error }
        try await finishToolCalls()
        await end(report: report, facts: facts)
    }

    /// Ends the answer: the reasoning entry with the provider's signature, then the answer's facts and usage on the
    /// entry that ends it.
    ///
    /// - Parameters:
    ///   - report: What the format's own members reported about the answer.
    ///   - facts: What the provider adds to them.
    private mutating func end(report: AnswerReport, facts: AnswerAdditions) async {
        await endReasoning(signature: facts.reasoningSignature, model: report.model)
        await sendFacts(report: report, facts: facts)
    }

    /// Ends the reasoning entry, when the provider has a signature for it or the model wrote a block in its answer's
    /// text: with the signature, and with the metadata that sending it back needs.
    private mutating func endReasoning(signature: Data?, model: String?) async {
        guard signature != nil || taggedReasoning?.block != nil else { return }
        await appendReasoning("", model: model)
        if let signature {
            await channel.send(.reasoning(entryID: reasoningEntryID, action: .updateSignature(signature, tokenCount: 0)))
        }
        // The model may arrive after the reasoning started, and the block is known only now; replay needs both.
        await channel.send(.reasoning(entryID: reasoningEntryID, action: .updateMetadata(reasoningMetadata(model: model))))
    }

    /// Sends the answer's facts and usage on the entry that ends it: the response entry, or the tool-calls entry when
    /// tool calls end the answer.
    private func sendFacts(report: AnswerReport, facts: AnswerAdditions) async {
        let usage = report.usage
        let usageMetadata = usage.map { usage in
            ProviderUsageMetadata(cost: facts.cost, cacheWriteTokenCount: usage.cacheWriteTokens, webSearchCount: facts.webSearchCount)
                .channelMetadata.merging(facts.usageMetadata) { $1 }
        }
        // Citations point into the answer's text, so they go on the response entry even when tool calls end the answer.
        var metadata = ProviderResponseMetadata(
            model: report.model, host: facts.host, responseID: report.responseID, requestID: facts.requestID,
            finishReason: report.finishReason, serviceTier: report.serviceTier, citations: toolCalls.isEmpty ? citations : []
        ).channelMetadata
        metadata.merge(facts.metadata) { $1 }
        // Foundation Models keeps only the last request's usage on a response, so each request's usage facts also go
        // on the entry that ends it, where a response whose tool calls ran reads every request's cost.
        metadata.merge(usageMetadata ?? [:]) { $1 }
        if toolCalls.isEmpty {
            if !hasText { await channel.send(.response(entryID: responseEntryID, action: .appendText("", tokenCount: 0))) }
            await channel.send(.response(entryID: responseEntryID, action: .updateMetadata(metadata)))
            if let usage, let usageMetadata {
                await channel.send(
                    .response(
                        entryID: responseEntryID, action: .updateUsage(input: usage.input, output: usage.output, metadata: usageMetadata))
                )
            }
        } else {
            if hasText, !citations.isEmpty {
                await channel.send(
                    .response(
                        entryID: responseEntryID, action: .updateMetadata(ProviderResponseMetadata(citations: citations).channelMetadata)))
            }
            // Foundation Models gives the tool-calls entry no readable metadata, so the round's facts go on its first call.
            if let first = toolCalls.firstCall {
                await channel.send(
                    .toolCalls(
                        entryID: toolCallsEntryID,
                        action: .toolCall(id: first.id, name: first.toolName, action: .updateMetadata(metadata))))
            }
            if let usage, let usageMetadata {
                await channel.send(
                    .toolCalls(
                        entryID: toolCallsEntryID, action: .updateUsage(input: usage.input, output: usage.output, metadata: usageMetadata))
                )
            }
        }
    }

    /// The reasoning entry's metadata: the origin, the model that wrote it once known, and the block that opened the
    /// answer's text once the answer ended.
    private func reasoningMetadata(model: String?) -> [String: any ConvertibleToGeneratedContent] {
        origin.metadata(model: model, taggedBlock: taggedReasoning?.block)
    }

    /// Sends a split of the answer's text: its reasoning, then its answer text.
    private mutating func send(_ split: TaggedReasoning.Split, model: String?) async {
        if !split.reasoning.isEmpty { await appendReasoning(split.reasoning, model: model) }
        guard !split.text.isEmpty else { return }
        hasText = true
        sentText += split.text
        await channel.send(.response(entryID: responseEntryID, action: .appendText(split.text, tokenCount: 1)))
    }
}

// MARK: - Tool calls

/// An answer's tool calls, assembled from their fragments as they arrive.
///
/// Fragments are routed by index, so parallel calls form one round. A fragment without an index continues the last
/// call, unless it brings a new id, which starts the next call. A call starts once it has a name, with an id made up if
/// the model sent none or one another call already uses, so the calls keep their order and none replaces another.
/// Argument text that arrives before the name is held until the call starts.
struct ToolCallAssembler {
    private var calls: [Int: Call] = [:]
    private var lastIndex: Int?

    /// Starts an answer with no tool calls.
    init() {}

    /// Whether no fragment has arrived.
    var isEmpty: Bool {
        calls.isEmpty
    }

    /// Adds one fragment to its call.
    ///
    /// - Parameters:
    ///   - index: The call's index in the answer, when the fragment names one.
    ///   - id: The call's id, when the fragment brings one.
    ///   - name: The tool's name, when the fragment brings it.
    ///   - arguments: The next part of the call's argument text.
    /// - Returns: The text to append to the call's arguments: all of it so far when the fragment starts the call, even
    ///   none, which announces the call; otherwise the fragment's own. `nil` when the call hasn't started or the
    ///   fragment has no text.
    mutating func add(index: Int?, id: String?, name: String?, arguments: String?) -> Arguments? {
        let index = self.index(of: index, id: id)
        lastIndex = index
        var call = calls[index] ?? Call()
        let wasStarted = call.id != nil && call.name != nil
        if call.id == nil, let id, !id.isEmpty, !calls.values.contains(where: { $0.id == id }) { call.id = id }
        if call.name == nil, let name, !name.isEmpty { call.name = name }
        if call.name != nil, call.id == nil { call.id = "call_\(UUID().uuidString)" }
        call.pendingArguments += arguments ?? ""
        var arguments: Arguments?
        if let id = call.id, let name = call.name, !wasStarted || !call.pendingArguments.isEmpty {
            arguments = Arguments(callID: id, toolName: name, text: call.pendingArguments)
            call.argumentText += call.pendingArguments
            call.pendingArguments = ""
        }
        calls[index] = call
        return arguments
    }

    /// The id and tool name of the first call to start, in index order, which carries the round's facts, or `nil`
    /// before any call has started.
    fileprivate var firstCall: (id: String, toolName: String)? {
        for (_, call) in calls.sorted(by: { $0.key < $1.key }) {
            if let id = call.id, let name = call.name { return (id, name) }
        }
        return nil
    }

    /// Ends the calls.
    ///
    /// Foundation Models reads arguments that stop partway, so arguments that aren't a whole JSON object are refused
    /// here, before any tool runs with them.
    ///
    /// - Returns: An empty JSON object, in index order, as the arguments of each call that got none, since a call to a
    ///   tool without arguments may send none, and Foundation Models parses them as JSON.
    /// - Throws: ``Failure/missingName`` when a call never got its name, and ``Failure/incompleteArguments(toolName:)``
    ///   when a call's arguments aren't a whole JSON object.
    func finish() throws(Failure) -> [Arguments] {
        var arguments: [Arguments] = []
        for (_, call) in calls.sorted(by: { $0.key < $1.key }) {
            guard let id = call.id, let name = call.name else { throw .missingName }
            if call.argumentText.isEmpty {
                arguments.append(Arguments(callID: id, toolName: name, text: "{}"))
            } else if case .object? = try? JSONValue(json: Data(call.argumentText.utf8)) {
                continue
            } else {
                throw .incompleteArguments(toolName: name)
            }
        }
        return arguments
    }

    /// The index of the call a fragment belongs to.
    private func index(of index: Int?, id: String?) -> Int {
        if let index { return index }
        guard let last = lastIndex else { return 0 }
        guard let id, !id.isEmpty, let lastID = calls[last]?.id, id != lastID else { return last }
        return (calls.keys.max() ?? last) + 1
    }
}

extension ToolCallAssembler {
    /// Text to append to the arguments of a started call.
    struct Arguments: Equatable {
        let callID: String
        let toolName: String
        let text: String

        /// The event that appends the text to the call in the answer's tool-calls entry.
        fileprivate func event(in entryID: String) -> LanguageModelExecutorGenerationChannel.Event {
            .toolCalls(
                entryID: entryID,
                action: .toolCall(id: callID, name: toolName, action: .appendArguments(text, tokenCount: text.isEmpty ? 0 : 1))
            )
        }
    }

    /// Why the calls can't end.
    enum Failure: Error {
        /// A call never got its name.
        case missingName

        /// A call's arguments aren't a whole JSON object, such as ones that stop partway.
        case incompleteArguments(toolName: String)
    }

    /// One call as its fragments arrive.
    private struct Call {
        var id: String?
        var name: String?
        /// Argument text that arrived before the call's name, held until the call can start.
        var pendingArguments = ""
        /// The argument text sent so far.
        var argumentText = ""
    }
}

// MARK: - Tagged reasoning

/// Reasoning that a model writes at the start of its answer's text, between `<think>` and `</think>` or `<thinking>`
/// and `</thinking>`, instead of sending it as reasoning.
///
/// The answer's text goes through ``split(_:)`` delta by delta, and comes out as the block's reasoning and the answer
/// after it. Only a block that opens the text counts, after any whitespace, so a tag later in the answer stays text.
/// The tags and the whitespace before and after the block leave the answer, and the whole block stays in ``block`` as
/// the model wrote it. A tag may be split across deltas anywhere, so text that may still be one is held back until
/// it's clear: the start of the text until it does or doesn't open a block, and the end of the reasoning while it may
/// begin the closing tag. Text that turns out not to open a block comes out unchanged.
///
/// A block that the answer never closes, such as one cut off at the token limit, is reasoning to the end, as it was
/// shown while it streamed.
struct TaggedReasoning {
    /// The block that opened the text, as the model wrote it: the whitespace before it, its tags and reasoning, and
    /// the whitespace after it. It's set once ``finish()`` ends the text, and `nil` when the text didn't open with a
    /// block.
    private(set) var block: String?

    private var state = State.opening(held: "")

    /// The block's text so far, as the model wrote it.
    private var written = ""

    /// Starts reading an answer's text.
    init() {}

    /// Splits the next delta of the answer's text.
    ///
    /// - Returns: The reasoning and the answer text the delta completes; either may be empty while text is held back.
    mutating func split(_ delta: String) -> Split {
        var split = Split()
        var rest = Substring(delta)
        while !rest.isEmpty {
            switch state {
            case .opening(let held):
                let text = held + rest
                rest = ""
                let start = text.drop { $0.isWhitespace }
                if let tag = Tag.all.first(where: { start.hasPrefix($0.opening) }) {
                    rest = start.dropFirst(tag.opening.count)
                    written = String(text[..<rest.startIndex])
                    state = .inside(closing: tag.closing, held: "")
                } else if start.isEmpty || Tag.all.contains(where: { $0.opening.hasPrefix(start) }) {
                    state = .opening(held: text)
                } else {
                    split.text += text
                    state = .answer
                }
            case .inside(let closing, let held):
                let text = held + rest
                rest = ""
                if let range = text.firstRange(of: closing) {
                    split.reasoning += text[..<range.lowerBound]
                    written += text[..<range.upperBound]
                    rest = text[range.upperBound...]
                    state = .closed
                } else {
                    let end = text.index(text.endIndex, offsetBy: -Self.partialLength(of: text, toward: closing))
                    split.reasoning += text[..<end]
                    written += text[..<end]
                    state = .inside(closing: closing, held: String(text[end...]))
                }
            case .closed:
                let answer = rest.drop { $0.isWhitespace }
                written += rest[..<answer.startIndex]
                rest = answer
                if !answer.isEmpty { state = .answer }
            case .answer:
                split.text += rest
                rest = ""
            }
        }
        return split
    }

    /// Ends the text, giving back what was held: the start of the text as answer text, or the end of a block that
    /// never closed as reasoning.
    mutating func finish() -> Split {
        defer { state = .answer }
        switch state {
        case .opening(let held):
            return Split(text: held)
        case .inside(_, let held):
            written += held
            block = written
            return Split(reasoning: held)
        case .closed, .answer:
            block = written.isEmpty ? nil : written
            return Split()
        }
    }

    /// How many characters at the end of the text begin the tag, and may be the first part of a tag split across
    /// deltas.
    private static func partialLength(of text: String, toward tag: String) -> Int {
        (1..<tag.count).reversed().first { text.hasSuffix(tag.prefix($0)) } ?? 0
    }
}

extension TaggedReasoning {
    /// What a delta of the answer's text holds: the reasoning, which comes first, and the answer text after it.
    struct Split: Equatable {
        fileprivate(set) var reasoning = ""
        fileprivate(set) var text = ""
    }

    private enum State {
        /// Before the text shows whether it opens a block, holding the text so far.
        case opening(held: String)

        /// Inside a block, holding the end of its text while it may begin the closing tag.
        case inside(closing: String, held: String)

        /// After the closing tag, dropping whitespace.
        case closed

        /// In the answer, where text passes through.
        case answer
    }

    /// A pair of tags that encloses a block.
    private struct Tag {
        static let all = [Tag(name: "think"), Tag(name: "thinking")]

        let opening: String
        let closing: String

        init(name: String) {
            opening = "<\(name)>"
            closing = "</\(name)>"
        }
    }
}

// MARK: - Generated data

/// Data a model generated, of a kind, such as an image, which an answer sends as a data entry of its own.
struct GeneratedData {
    let contentType: UTType
    let content: Data
}

// MARK: - Ending

/// Why an answer that arrived whole fails anyway: the model declined, a content filter stopped it, or it reached its
/// token limit inside a tool call or a guided answer.
private enum AnswerEnding: Equatable {
    /// The model declined, with its explanation.
    case refusal(String)

    /// A content filter stopped the answer.
    case contentFilter

    /// The answer reached its token limit inside a tool call, so no tool may get partial arguments. Each format reports
    /// it as a failure of its own.
    case tokenLimitInToolCall

    /// A guided answer reached its token limit, so it would decode as a wrong value.
    case tokenLimitInGuidedAnswer

    /// The way an answer fails, or `nil` when it ended well, in this order: a refusal, a content filter, then the token
    /// limit.
    ///
    /// - Parameters:
    ///   - refusal: The refusal text the model sent, empty for none.
    ///   - finishReason: Why the answer ended.
    ///   - hasToolCalls: Whether the answer has tool calls.
    ///   - requiresCompleteAnswer: Whether the answer must be whole, as a guided answer must.
    init?(refusal: String, finishReason: FinishReason?, hasToolCalls: Bool, requiresCompleteAnswer: Bool) {
        switch finishReason {
        case _ where !refusal.isEmpty: self = .refusal(refusal)
        case .contentFilter?: self = .contentFilter
        case .length? where hasToolCalls: self = .tokenLimitInToolCall
        case .length? where requiresCompleteAnswer: self = .tokenLimitInGuidedAnswer
        default: return nil
        }
    }

    /// The error the answer ends in, or `nil` for ``tokenLimitInToolCall``, which the format reports as a failure of
    /// its own.
    ///
    /// - Parameters:
    ///   - responseText: The answer's text, which a parsing error carries.
    ///   - host: The company whose servers ran the model, when the provider names one.
    /// - Returns: `LanguageModelError.refusal` or `.guardrailViolation`, or `GeneratedContent.ParsingError`.
    func error(responseText: String, host: String?) -> (any Error)? {
        let metadata = ProviderErrorMetadata(host: host).contextMetadata
        switch self {
        case .refusal(let refusal):
            return LanguageModelError(.refusal, message: refusal, metadata: metadata)
        case .contentFilter:
            return LanguageModelError(.guardrailViolation, message: "A content filter stopped the response.", metadata: metadata)
        case .tokenLimitInToolCall:
            return nil
        case .tokenLimitInGuidedAnswer:
            return GeneratedContent.ParsingError(
                rawContent: responseText, debugDescription: "The answer reached its token limit before it was complete.")
        }
    }
}

extension FinishReason {
    /// The reason for an answer a content filter stopped, which throws instead of ending an entry.
    fileprivate static let contentFilter: Self = "content_filter"
}

// MARK: - Facts and usage

/// What an answer's stream reports about it in a format's own members: the model that answered, the response id, the
/// service tier, the usage and why the answer ended.
///
/// Each format fills it from its own events. A fact that an event reports replaces the earlier one, and one it leaves
/// out keeps its earlier value.
struct AnswerReport {
    /// The model that answered, as the answer names it.
    var model: String?

    /// The answer's id.
    var responseID: String?

    /// The processing tier that served the answer, in the host's word for it.
    var serviceTier: String?

    /// The usage as Foundation Models' running totals.
    var usage: AnswerUsage?

    /// Why the answer ended, once an event says so. A stream that ends without one was cut off.
    var finishReason: FinishReason?
}

/// An answer's usage as Foundation Models' running totals, with the prompt tokens written to the host's cache.
struct AnswerUsage {
    fileprivate let input: LanguageModelExecutorGenerationChannel.Usage.Input
    fileprivate let output: LanguageModelExecutorGenerationChannel.Usage.Output
    fileprivate let cacheWriteTokens: Int?

    /// - Parameters:
    ///   - inputTokens: The prompt's tokens, cached ones included.
    ///   - cachedTokens: The prompt's tokens read from the host's cache.
    ///   - cacheWriteTokens: The prompt's tokens written to the host's cache, when the host reports them.
    ///   - outputTokens: The answer's tokens, reasoning included.
    ///   - reasoningTokens: The answer's reasoning tokens.
    init(inputTokens: Int, cachedTokens: Int, cacheWriteTokens: Int?, outputTokens: Int, reasoningTokens: Int) {
        input = .init(totalTokenCount: inputTokens, cachedTokenCount: cachedTokens)
        output = .init(totalTokenCount: outputTokens, reasoningTokenCount: reasoningTokens)
        self.cacheWriteTokens = cacheWriteTokens
    }
}

/// What a provider adds to an answer once it's over: the facts every provider shares, as typed values, its own facts,
/// and its reasoning signature.
package struct AnswerAdditions {
    /// The company whose servers ran the model, once known.
    private(set) var host: String?

    /// The provider's id for the request that got the answer.
    fileprivate var requestID: String?

    /// What the answer cost, in US dollars.
    fileprivate var cost: Decimal?

    /// The web searches the provider ran for the answer.
    fileprivate var webSearchCount: Int?

    /// The provider's own facts, as its typed value writes them, for the metadata of the entry that ends the answer.
    var metadata: [String: any ConvertibleToGeneratedContent]

    /// The provider's own facts, as its typed value writes them, for the metadata of the answer's usage.
    fileprivate var usageMetadata: [String: any ConvertibleToGeneratedContent]

    /// The signature of the answer's reasoning entry, such as reasoning in the provider's form that goes back on later
    /// turns, or `nil` when there's none.
    var reasoningSignature: Data?

    package init(
        host: String? = nil,
        requestID: String? = nil,
        cost: Decimal? = nil,
        webSearchCount: Int? = nil,
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        usageMetadata: [String: any ConvertibleToGeneratedContent] = [:],
        reasoningSignature: Data? = nil
    ) {
        self.host = host
        self.requestID = requestID
        self.cost = cost
        self.webSearchCount = webSearchCount
        self.metadata = metadata
        self.usageMetadata = usageMetadata
        self.reasoningSignature = reasoningSignature
    }
}
