import Foundation
import FoundationModels
import LanguageModelsCore

// MARK: - Stream

/// One answer's stream: turns the format's events into the answer's output, which an ``AnswerChannel`` sends as
/// Foundation Models channel events.
///
/// Text deltas go to the response entry as they are, since the format has reasoning of its own, and reasoning
/// summaries and reasoning text to the reasoning entry, which each `reasoning` output item starts, with a blank line
/// between the parts of a summary. Function calls are told apart by their output index, so the calls of one answer form
/// one round, and a call whose arguments arrive whole, only in `response.output_item.done`, gets them from there. The
/// answer's `reasoning` items become its reasoning entry's signature, with the places of its messages and calls when
/// they came between them, and the `phase` of each of its messages, with the length of the message's text, goes in its
/// metadata, so both go back on later turns in their order. A cited page's offsets count from the start of the
/// answer's text. In a guided answer, as the official SDKs parse
/// it, only the first message with no phase or the `final_answer` phase holds the answer: the text of the others, such
/// as `commentary`, stays out of the response text, so the answer decodes, and goes in the metadata with its phase.
struct ResponsesAnswerStream<Dialect: ResponsesDialect>: StreamedAnswer {
    private let dialect: Dialect
    private let imageEntries: [Transcript.Entry]
    private let requiresCompleteAnswer: Bool

    /// What the answer's events reported about it so far.
    private(set) var report = AnswerReport()

    /// What the dialect tracks across the answer.
    private(set) var state: Dialect.StreamState

    private var output: AnswerChannel
    private var refusal = ""

    /// The answer's `reasoning` items, as `response.output_item.done` carried them, with their output indexes.
    private var reasoningItems: [(index: Int?, item: ReasoningItem)] = []

    /// The answer's messages, by output index.
    private var messages: [Int: Message] = [:]

    /// The output index of the message that holds a guided answer, once one starts.
    private var answerIndex: Int?

    /// The answer's function calls: their ids by output index, the last one to start, and the argument text sent so
    /// far for each, by id.
    private var callIDs: [Int: String] = [:]
    private var lastCallID: String?
    private var sentArguments: [String: String] = [:]

    /// The part of the reasoning the last reasoning text belongs to, so a new part starts after a blank line.
    private var lastReasoningPart: ReasoningPart?

    /// Starts the stream of an answer.
    ///
    /// - Parameters:
    ///   - channel: Where the answer's events go.
    ///   - dialect: The provider's dialect.
    ///   - headers: The headers of the response whose stream carries the answer.
    ///   - imageEntries: The request's entries that carry an image, which an error for an image the host rejects names.
    ///   - requiresCompleteAnswer: Whether an answer cut off at its token limit is an error, as for guided generation,
    ///     where a partial answer would decode as a wrong value.
    init(
        channel: LanguageModelExecutorGenerationChannel, dialect: Dialect, headers: ResponseHeaders,
        imageEntries: [Transcript.Entry], requiresCompleteAnswer: Bool
    ) {
        self.dialect = dialect
        self.imageEntries = imageEntries
        self.requiresCompleteAnswer = requiresCompleteAnswer
        output = AnswerChannel(channel: channel, origin: Dialect.reasoningOrigin, readsTaggedReasoning: false)
        state = dialect.streamState(headers)
    }

    /// The text sent to the response entry, or empty when the answer ends in tool calls, since the round that answers
    /// them comes after.
    var responseText: String {
        output.responseText
    }

    /// Whether any of the answer's output has arrived: text, reasoning or a tool call.
    var hasOutput: Bool {
        output.hasOutput
    }

    /// The company whose servers ran the model, when the dialect names one.
    var host: String? {
        dialect.facts(of: state).host
    }
}

extension ResponsesAnswerStream {
    /// One of an answer's messages: its `phase`, once known, its text, and whether the text is held out of the answer's
    /// text, as a guided answer's `commentary` is.
    private struct Message {
        var phase: String?
        var text = ""
        var isHeldOut = false

        /// The message as the metadata keeps it: its phase with the length of its text, counted on the whole text
        /// since a character can span deltas, or with the text itself when it's held out.
        var kept: MessagePhase {
            isHeldOut ? MessagePhase(phase: phase, heldText: text) : MessagePhase(phase: phase, length: text.count)
        }
    }

    /// The part of an answer's reasoning a reasoning text belongs to: its output item, and its summary or content
    /// part.
    private struct ReasoningPart: Equatable {
        let outputIndex: Int?
        let index: Int?
    }
}

// MARK: - Receiving

extension ResponsesAnswerStream {
    /// Sends the events for one server-sent event.
    ///
    /// - Returns: Whether the event ends the stream: `response.completed`, `response.incomplete`, or a `[DONE]`.
    /// - Throws: The dialect's error for an event that can't be read, an `error` event and a failed response.
    mutating func receive(_ event: ServerSentEvent) async throws -> Bool {
        let streamed: ResponseEvent.Streamed?
        do {
            streamed = try ResponseEvent.Streamed(event)
        } catch {
            throw unreadable(error)
        }
        switch streamed {
        case .event(let event, let data)?:
            return try await receive(event, data: data)
        case .done?:
            return true
        case nil:
            return false
        }
    }

    private mutating func receive(_ event: ResponseEvent, data: Data) async throws -> Bool {
        if let response = event.response { report.update(with: response) }
        switch event.type {
        case .error:
            // The error is nested in the event's `error` member, or is the event's own members.
            throw failure(.errorEvent(try errorBody(event.error.map(\.data) ?? data)))
        case .failed:
            throw failure(.failedResponse(try event.response?.error.map { try errorBody($0.data) }))
        case .outputItemAdded:
            await startItem(event)
        case .outputItemDone:
            await endItem(event)
        case .outputTextDelta:
            await appendText(event.delta, at: event.outputIndex)
        case .annotationAdded:
            let start = textStart(of: event.outputIndex)
            if let citation = event.annotation.flatMap({ Citation($0, textStart: start) }) { output.cite(citation) }
        case .refusalDelta:
            refusal += event.delta ?? ""
        case .reasoningSummaryTextDelta:
            await appendReasoning(event.delta, part: ReasoningPart(outputIndex: event.outputIndex, index: event.summaryIndex))
        case .reasoningTextDelta:
            await appendReasoning(event.delta, part: ReasoningPart(outputIndex: event.outputIndex, index: event.contentIndex))
        case .functionCallArgumentsDelta:
            await addArguments(event.delta ?? "", callID: callID(at: event.outputIndex), index: event.outputIndex)
        case .completed:
            report.finishReason = output.hasToolCalls ? .toolCalls : .stop
            return true
        case .incomplete:
            report.finishReason = Self.finishReason(event.response?.incompleteDetails?.reason)
            return true
        default:
            break
        }
        return false
    }

    /// Starts an output item: a reasoning item starts the reasoning entry, a message its text, and a function call its
    /// call.
    private mutating func startItem(_ event: ResponseEvent) async {
        guard let item = event.item else { return }
        switch item.itemType {
        case .reasoning?:
            await output.appendReasoning("", model: report.model)
        case .message?:
            guard let index = event.outputIndex else { return }
            var message = messages[index, default: Message()]
            message.phase = item["phase"]?.stringValue
            if requiresCompleteAnswer {
                let isFinal = message.phase.map { $0 == MessagePhase.finalAnswer } ?? true
                if isFinal, answerIndex == nil { answerIndex = index }
                message.isHeldOut = answerIndex != index
            }
            messages[index] = message
        case .functionCall?:
            guard let id = item["call_id"]?.stringValue else { return }
            if let index = event.outputIndex { callIDs[index] = id }
            lastCallID = id
            let arguments = item["arguments"]?.stringValue ?? ""
            sentArguments[id] = arguments
            await output.addToolCall(index: event.outputIndex, id: id, name: item["name"]?.stringValue, arguments: arguments)
        default:
            break
        }
    }

    /// Ends an output item: keeps a reasoning item and a message's phase, and sends the rest of a function call's
    /// arguments when they arrived whole.
    private mutating func endItem(_ event: ResponseEvent) async {
        guard let item = event.item else { return }
        switch item.itemType {
        case .reasoning?:
            reasoningItems.append((event.outputIndex, ReasoningItem(json: item)))
        case .message?:
            if let index = event.outputIndex, let phase = item["phase"]?.stringValue {
                messages[index, default: Message()].phase = phase
            }
        case .functionCall?:
            guard let id = item["call_id"]?.stringValue, let arguments = item["arguments"]?.stringValue else { return }
            let sent = sentArguments[id] ?? ""
            guard arguments.count > sent.count, arguments.hasPrefix(sent) else { return }
            await addArguments(String(arguments.dropFirst(sent.count)), callID: id, index: event.outputIndex)
        default:
            break
        }
    }

    /// Sends the next part of a message's text, unless the message is held out of the answer's text, and keeps it with
    /// the message.
    private mutating func appendText(_ delta: String?, at index: Int?) async {
        guard let delta, !delta.isEmpty else { return }
        if let index {
            messages[index, default: Message()].text += delta
            if messages[index]?.isHeldOut == true { return }
        }
        await output.appendText(delta, model: report.model)
    }

    /// Where the text of the message at an output index starts in the answer's text: the length of the shown messages'
    /// text before it, or `nil` when the message is held out of the answer's text, or when the text before it isn't
    /// ASCII, since hosts don't say whether their offsets count characters, UTF-16 code units or bytes.
    private func textStart(of index: Int?) -> Int? {
        guard let index else { return 0 }
        guard messages[index]?.isHeldOut != true else { return nil }
        let before = messages.filter { $0.key < index && !$0.value.isHeldOut }.sorted { $0.key < $1.key }.map(\.value.text).joined()
        return before.allSatisfy(\.isASCII) ? before.count : nil
    }

    /// The id of the function call at an output index, or of the last call to start when the event names no index.
    private func callID(at index: Int?) -> String? {
        index.flatMap { callIDs[$0] } ?? lastCallID
    }

    private mutating func addArguments(_ text: String, callID: String?, index: Int?) async {
        guard !text.isEmpty else { return }
        if let callID { sentArguments[callID, default: ""] += text }
        await output.addToolCall(index: index, id: index == nil ? nil : callID, name: nil, arguments: text)
    }

    /// Sends reasoning text, after a blank line when it starts another part of the reasoning.
    private mutating func appendReasoning(_ delta: String?, part: ReasoningPart) async {
        guard let delta, !delta.isEmpty else { return }
        let separator = lastReasoningPart.map { $0 == part ? "" : "\n\n" } ?? ""
        lastReasoningPart = part
        await output.appendReasoning(separator + delta, model: report.model)
    }
}

extension JSONValue {
    /// The `type` of an output item.
    fileprivate var itemType: ResponsesRequest.ItemType? {
        self["type"]?.stringValue.map(ResponsesRequest.ItemType.init(rawValue:))
    }
}

extension Citation {
    /// The citation of a cited page, with its offsets moved from its message's text to the answer's, or `nil` for
    /// another kind of annotation or one without a valid URL.
    ///
    /// - Parameters:
    ///   - annotation: The annotation, with offsets in its message's text.
    ///   - textStart: Where the message's text starts in the answer's text, or `nil` when that isn't known, so the
    ///     citation has no offsets.
    fileprivate init?(_ annotation: ResponseEvent.Annotation, textStart: Int?) {
        guard annotation.type == "url_citation", let address = annotation.url, let url = URL(string: address) else { return nil }
        let start = textStart.flatMap { start in annotation.startIndex.map { $0 + start } }
        let end = textStart.flatMap { start in annotation.endIndex.map { $0 + start } }
        self.init(url: url, title: annotation.title, excerpt: nil, startOffset: start, endOffset: end)
    }
}

extension AnswerReport {
    /// Takes the facts that a lifecycle event's response reports.
    mutating func update(with response: ResponseEvent.Response) {
        responseID = response.id ?? responseID
        model = response.model ?? model
        serviceTier = response.serviceTier ?? serviceTier
        if let usage = response.usage {
            self.usage = AnswerUsage(usage)
        }
    }
}

extension AnswerUsage {
    /// The usage a response reported.
    init(_ usage: ResponseEvent.Usage) {
        self.init(
            inputTokens: usage.inputTokens ?? 0,
            cachedTokens: usage.inputTokensDetails?.cachedTokens ?? 0,
            cacheWriteTokens: usage.inputTokensDetails?.cacheWriteTokens,
            outputTokens: usage.outputTokens ?? 0,
            reasoningTokens: usage.outputTokensDetails?.reasoningTokens ?? 0
        )
    }
}

// MARK: - Finishing

extension ResponsesAnswerStream {
    /// Sends the events that end the answer: arguments for calls that had none, the reasoning signature, and the
    /// metadata and usage.
    ///
    /// An answer cut off at its token limit ends like any other, with `length` as its finish reason, since Foundation
    /// Models has no error for it. One cut off inside its tool calls throws instead, so no tool gets partial arguments,
    /// and so does a guided answer, which would decode as a wrong value.
    ///
    /// - Parameter isComplete: Whether an event ended the stream. Only `response.completed` and `response.incomplete`
    ///   end an answer, so a stream without either was cut off, even after a `[DONE]`.
    /// - Throws: `LanguageModelError.refusal` or `.guardrailViolation` when the model declined or a filter stopped it,
    ///   `GeneratedContent.ParsingError` when a guided answer reached its token limit, and the dialect's error when the
    ///   stream was cut off, reached its token limit inside a tool call, or had a call that never got its name or whose
    ///   arguments aren't a whole JSON object.
    mutating func finish(isComplete: Bool) async throws {
        guard report.finishReason != nil else {
            throw failure(.unusableResponse(.cutOff))
        }
        let ending = await output.finish(
            report: report, facts: answerFacts, refusal: refusal, requiresCompleteAnswer: requiresCompleteAnswer)
        switch ending {
        case .unusable(let problem)?: throw failure(.unusableResponse(problem))
        case .failed(let error)?: throw error
        case nil: break
        }
    }

    /// The dialect's facts, with the answer's `reasoning` items and the places of its messages and calls among them as
    /// the reasoning signature, and the phases of its messages.
    private var answerFacts: AnswerFacts {
        var providerFacts = dialect.facts(of: state)
        providerFacts.reasoningSignature = OutputItem.signature(of: outputOrder)
        let phases = messages.sorted { $0.key < $1.key }.map(\.value.kept)
        if phases.contains(where: { $0.phase != nil || $0.heldText != nil }) {
            providerFacts.metadata[Dialect.phasesMetadataKey] = phases.map(\.metadataValue)
        }
        return providerFacts
    }

    /// The answer's output items in their order: its `reasoning` items, the messages that have text and the function
    /// calls, by output index. A `reasoning` item without an index goes first, as when the order wasn't kept.
    private var outputOrder: [OutputItem] {
        let placed: [(index: Int, item: OutputItem)] =
            reasoningItems.map { ($0.index ?? -1, .reasoning($0.item)) }
            + messages.filter { !$0.value.text.isEmpty }.map { ($0.key, .message) }
            + callIDs.keys.map { ($0, .functionCall) }
        return placed.enumerated().sorted { ($0.element.index, $0.offset) < ($1.element.index, $1.offset) }.map(\.element.item)
    }

    /// The finish reason for why a response is incomplete: `length` for its token limit, the host's own word for any
    /// other reason, and `incomplete` when it gives none.
    private static func finishReason(_ reason: String?) -> FinishReason {
        switch reason {
        case "max_output_tokens"?: .length
        case let reason?: FinishReason(rawValue: reason)
        case nil: FinishReason(rawValue: "incomplete")
        }
    }

    /// An error object in the dialect's type.
    private func errorBody(_ data: Data) throws -> Dialect.ErrorBody {
        do {
            return try ProviderHTTP.decoder.decode(Dialect.ErrorBody.self, from: data)
        } catch {
            throw unreadable(error)
        }
    }

    /// The error the answer's failure becomes, with what the dialect tracked so far.
    private func failure(_ kind: ResponsesFailure<Dialect>.Kind) -> any Error {
        dialect.error(for: ResponsesFailure(kind, state: state, imageEntries: imageEntries)).error
    }

    /// The error for an event whose data can't be read, with the reason.
    private func unreadable(_ error: any Error) -> any Error {
        failure(.unusableResponse(.unreadableEvent("\(error)")))
    }
}

// MARK: - Wire

/// One streamed event of a response, with the members the format reads, in OpenAI's spelling.
///
/// Every member but `type` is optional, since each kind of event carries only some of them, and hosts that follow the
/// format add and leave out members of their own. An event of a kind the format doesn't read keeps only its `type`, so
/// its members, whatever their shape, can't make it unreadable.
struct ResponseEvent: Decodable {
    let type: EventType

    /// The index of the output item the event concerns, which tells an answer's function calls apart.
    let outputIndex: Int?

    /// The index of the reasoning summary part, or of the content part, the event's text belongs to.
    let summaryIndex: Int?
    let contentIndex: Int?

    /// The next part of a text, a refusal, a reasoning summary or a function call's arguments.
    let delta: String?

    /// The output item of `response.output_item.added` and `response.output_item.done`, as JSON, so that a reasoning
    /// item goes back as it came.
    let item: JSONValue?

    /// The response that the lifecycle events, such as `response.completed`, carry.
    let response: Response?

    /// The annotation of `response.output_text.annotation.added`, such as a cited page.
    let annotation: Annotation?

    /// The error of an `error` event that nests it, or `nil` for one that carries it in its own members.
    let error: JSONValue?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(EventType.self, forKey: .type)
        let reads = EventType.read.contains(type)
        outputIndex = reads ? try container.decodeIfPresent(Int.self, forKey: .outputIndex) : nil
        summaryIndex = reads ? try container.decodeIfPresent(Int.self, forKey: .summaryIndex) : nil
        contentIndex = reads ? try container.decodeIfPresent(Int.self, forKey: .contentIndex) : nil
        delta = reads ? try container.decodeIfPresent(String.self, forKey: .delta) : nil
        item = reads ? try container.decodeIfPresent(JSONValue.self, forKey: .item) : nil
        response = reads ? try container.decodeIfPresent(Response.self, forKey: .response) : nil
        annotation = reads ? try container.decodeIfPresent(Annotation.self, forKey: .annotation) : nil
        error = reads ? try container.decodeIfPresent(JSONValue.self, forKey: .error) : nil
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case outputIndex = "output_index"
        case summaryIndex = "summary_index"
        case contentIndex = "content_index"
        case delta
        case item
        case response
        case annotation
        case error
    }
}

extension ResponseEvent {
    /// A response, as the lifecycle events carry it.
    struct Response: Decodable {
        let id: String?
        let model: String?
        /// The processing tier that served the response, in the host's word for it.
        let serviceTier: String?
        let usage: Usage?
        let incompleteDetails: IncompleteDetails?
        /// The `error` object of a failed response.
        let error: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case id
            case model
            case serviceTier = "service_tier"
            case usage
            case incompleteDetails = "incomplete_details"
            case error
        }
    }

    /// Why a response ended before it was complete.
    struct IncompleteDetails: Decodable {
        let reason: String?
    }

    struct Usage: Decodable {
        struct InputDetails: Decodable {
            let cachedTokens: Int?
            let cacheWriteTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
                case cacheWriteTokens = "cache_write_tokens"
            }
        }

        struct OutputDetails: Decodable {
            let reasoningTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let inputTokens: Int?
        let inputTokensDetails: InputDetails?
        let outputTokens: Int?
        let outputTokensDetails: OutputDetails?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case inputTokensDetails = "input_tokens_details"
            case outputTokens = "output_tokens"
            case outputTokensDetails = "output_tokens_details"
        }
    }

    /// An annotation of an answer's text: a cited page, as `url_citation`, or a kind the format doesn't read.
    struct Annotation: Decodable {
        let type: String?
        let url: String?
        let title: String?
        let startIndex: Int?
        let endIndex: Int?

        private enum CodingKeys: String, CodingKey {
            case type
            case url
            case title
            case startIndex = "start_index"
            case endIndex = "end_index"
        }
    }

    /// The kind of an event, by its `type`. Kinds the format doesn't read, such as a server tool's progress, are
    /// passed over.
    struct EventType: ProviderVocabulary {
        static let created: Self = "response.created"
        static let inProgress: Self = "response.in_progress"
        static let completed: Self = "response.completed"
        static let incomplete: Self = "response.incomplete"
        static let failed: Self = "response.failed"
        static let outputItemAdded: Self = "response.output_item.added"
        static let outputItemDone: Self = "response.output_item.done"
        static let outputTextDelta: Self = "response.output_text.delta"
        static let annotationAdded: Self = "response.output_text.annotation.added"
        static let refusalDelta: Self = "response.refusal.delta"
        static let reasoningSummaryTextDelta: Self = "response.reasoning_summary_text.delta"
        static let reasoningTextDelta: Self = "response.reasoning_text.delta"
        static let functionCallArgumentsDelta: Self = "response.function_call_arguments.delta"
        static let error: Self = "error"

        /// The kinds the format reads.
        static let read: Set<Self> = [
            created, inProgress, completed, incomplete, failed, outputItemAdded, outputItemDone, outputTextDelta, annotationAdded,
            refusalDelta, reasoningSummaryTextDelta, reasoningTextDelta, functionCallArgumentsDelta, error,
        ]

        let rawValue: String
    }

    /// One server-sent event of a streamed response: an event and its JSON, which the dialect reads its own members
    /// from, or a `[DONE]` that a host may send after the response's last event.
    enum Streamed {
        case event(ResponseEvent, Data)
        case done

        /// The event a server-sent event carries, or `nil` for one without data.
        ///
        /// - Throws: An error that says why the data isn't an event.
        init?(_ event: ServerSentEvent) throws {
            switch event.data {
            case "": return nil
            case "[DONE]": self = .done
            default:
                let data = Data(event.data.utf8)
                self = .event(try ProviderHTTP.decoder.decode(ResponseEvent.self, from: data), data)
            }
        }
    }
}
