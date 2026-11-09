import Foundation
import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

// MARK: - Stream

extension ChatCompletions {
    /// One answer's stream: turns the format's chunks, with the exchange's members, into the answer's output, which an
    /// ``AnswerChannel`` sends as Foundation Models channel events.
    ///
    /// Reasoning arrives in the provider's members, in the `thinking` parts of a delta's content, or in a block in
    /// reasoning tags that opens the answer's text, and tool-call fragments by index, so parallel calls form one round.
    /// Each piece of data the model generates becomes a data entry of its own. The answer ends with its metadata and
    /// usage on the entry that finishes it, and with the pages it cites on its response entry.
    struct Stream<Exchange: ChatCompletions.Exchange> {
        private var exchange: Exchange
        private let headers: ResponseHeaders
        private let provider: String
        private let imageEntries: [Transcript.Entry]
        private let requiresCompleteAnswer: Bool

        /// What the answer's chunks reported about it so far.
        private(set) var report = AnswerReport()

        private var output: AnswerChannel
        private var refusal = ""

        /// Starts the stream of an answer.
        ///
        /// - Parameters:
        ///   - channel: Where the answer's events go.
        ///   - model: The model, which names the provider and how its answers' reasoning is tagged.
        ///   - exchange: The provider's part in the exchange, which the stream owns from here.
        ///   - headers: The headers of the response whose stream carries the answer.
        ///   - imageEntries: The request's entries that carry an image, which an error for an image the host rejects names.
        ///   - requiresCompleteAnswer: Whether an answer cut off at its token limit is an error, as for guided generation,
        ///     where a partial answer would decode as a wrong value.
        init(
            channel: LanguageModelExecutorGenerationChannel, model: ChatCompletions.Model<Exchange>, exchange: Exchange,
            headers: ResponseHeaders, imageEntries: [Transcript.Entry], requiresCompleteAnswer: Bool
        ) {
            self.exchange = exchange
            self.headers = headers
            provider = model.providerName
            self.imageEntries = imageEntries
            self.requiresCompleteAnswer = requiresCompleteAnswer
            output = AnswerChannel(channel: channel, origin: ReasoningOrigin(rawValue: model.reasoningOrigin), readsTaggedReasoning: true)
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

        /// The company whose servers ran the model, when the exchange names one.
        var host: String? {
            additions.host
        }

        /// What the exchange adds to the answer.
        private var additions: AnswerAdditions {
            exchange.additions(header: headers.value(named:))
        }
    }
}

// MARK: - Receiving

extension ChatCompletions.Stream {
    /// Sends the events for one server-sent event.
    ///
    /// An event the provider named `ping` is passed over, and one it named `error` is an error event, whatever JSON or
    /// other text its data holds; an event with empty data is passed over, and a `[DONE]` ends the stream, whatever
    /// their names.
    ///
    /// - Returns: Whether the event is the `[DONE]` that ends the stream.
    /// - Throws: The exchange's error for an event that isn't a chunk, and for an error event.
    mutating func receive(_ event: ServerSentEvent) async throws -> Bool {
        guard !event.isPing else { return false }
        let streamEvent: StreamEvent<Exchange.ChunkExtras>?
        do {
            streamEvent = try StreamEvent(event)
        } catch {
            throw event.isError ? errorEvent(Data(event.data.utf8)) : unreadable(error)
        }
        switch streamEvent {
        case .chunk(let chunk, let extras, let data)?:
            try await receive(chunk, extras: extras, data: data, isNamedError: event.isError)
            return false
        case .done?:
            return true
        case nil:
            return false
        }
    }

    /// Takes one chunk's facts, then sends its reasoning, text, tool calls and generated data, in that order.
    ///
    /// - Parameters:
    ///   - chunk: The chunk's members of the format.
    ///   - extras: The exchange's members of the chunk.
    ///   - data: The chunk's JSON, which an error event's error object is read from.
    ///   - isNamedError: Whether the provider named the chunk's event `error`, which makes it an error event.
    /// - Throws: The exchange's error when the chunk is an error event, which sends nothing.
    private mutating func receive(_ chunk: Chunk, extras: Exchange.ChunkExtras, data: Data, isNamedError: Bool) async throws {
        report.update(with: chunk)
        let chunkAdditions = exchange.read(extras)
        if chunk.isError || isNamedError {
            throw errorEvent(data)
        }
        guard let delta = chunk.choices?.first?.delta else { return }

        if let reasoning = chunkAdditions.reasoning { await output.appendReasoning(reasoning, model: report.model) }
        for piece in delta.content?.pieces ?? [] {
            switch piece {
            case .reasoning(let text): await output.appendReasoning(text, model: report.model)
            case .text(let text): await output.appendText(text, model: report.model)
            }
        }
        if let text = delta.refusal?.stringValue { refusal += text }
        for annotation in delta.annotations ?? [] {
            guard let found = annotation.urlCitation, let citation = Citation(found) else { continue }
            output.cite(citation)
        }
        for fragment in delta.toolCalls ?? [] {
            await output.addToolCall(
                index: fragment.index, id: fragment.id, name: fragment.function?.name, arguments: fragment.function?.arguments)
        }
        for url in chunkAdditions.imageURLs {
            guard let image = DataURL(url) else { continue }
            let type = UTType(mimeType: image.mediaType, conformingTo: .image) ?? .image
            await output.sendData(GeneratedData(contentType: type, content: image.data))
        }
    }
}

extension Citation {
    /// The citation of a streamed annotation, or `nil` when it has no valid URL.
    fileprivate init?(_ citation: Chunk.Annotation.URLCitation) {
        guard let address = citation.url, let url = URL(string: address) else { return nil }
        self.init(
            url: url, title: citation.title, excerpt: citation.content, startOffset: citation.startIndex, endOffset: citation.endIndex)
    }
}

extension AnswerReport {
    /// Takes the facts that a chunk reports.
    fileprivate mutating func update(with chunk: Chunk) {
        responseID = chunk.id ?? responseID
        model = chunk.model ?? model
        serviceTier = chunk.serviceTier ?? serviceTier
        if let usage = chunk.usage {
            self.usage = AnswerUsage(usage)
        }
        finishReason = chunk.choices?.first?.finishReason ?? finishReason
    }
}

extension AnswerUsage {
    /// The usage a chunk reported.
    fileprivate init(_ usage: Chunk.Usage) {
        self.init(
            inputTokens: usage.promptTokens ?? 0,
            cachedTokens: usage.promptTokensDetails?.cachedTokens ?? 0,
            cacheWriteTokens: usage.promptTokensDetails?.cacheWriteTokens,
            outputTokens: usage.completionTokens ?? 0,
            reasoningTokens: usage.completionTokensDetails?.reasoningTokens ?? 0
        )
    }
}

// MARK: - Finishing

extension ChatCompletions.Stream {
    /// Sends the events that end the answer: the text held back, arguments for calls that had none, the reasoning
    /// signature, and the metadata and usage.
    ///
    /// An answer cut off at its token limit ends like any other, with `length` as its finish reason, since Foundation
    /// Models has no error for it. One cut off inside its tool calls throws instead, so no tool gets partial arguments,
    /// and so does a guided answer, which would decode as a wrong value.
    ///
    /// - Parameter isComplete: Whether the stream ended with `[DONE]`. A stream that ends without it or a finish reason
    ///   was cut off.
    /// - Throws: `LanguageModelError.refusal` or `.guardrailViolation` when the model declined or a filter stopped it,
    ///   `GeneratedContent.ParsingError` when a guided answer reached its token limit, and the exchange's error when the
    ///   stream was cut off, ended in an error, reached its token limit inside a tool call, or had a call that never
    ///   got its name or whose arguments aren't a whole JSON object.
    mutating func finish(isComplete: Bool) async throws {
        guard isComplete || report.finishReason != nil else {
            throw failure(.cutOff)
        }
        // A finish reason of `error` says the host failed while it generated.
        let failedAnswer =
            report.finishReason == .error
            ? exchange.error(for: RequestFailure(failedAnswer: nil, headers: headers, imageEntries: imageEntries)) : nil
        do {
            try await output.finish(
                report: report, facts: additions, refusal: refusal, requiresCompleteAnswer: requiresCompleteAnswer,
                failedAnswer: failedAnswer)
        } catch let problem as StreamProblem {
            throw failure(problem)
        }
    }

    /// The error a stream the format couldn't use becomes, with what the exchange read so far.
    private func failure(_ problem: StreamProblem) -> any Error {
        exchange.error(for: RequestFailure(problem, provider: provider, headers: headers, imageEntries: imageEntries))
    }

    /// The error for an event whose data can't be read, with the reason.
    private func unreadable(_ error: any Error) -> any Error {
        failure(.unreadableEvent("\(error)"))
    }

    /// The error for an error event.
    ///
    /// - Parameter data: The event's data.
    /// - Returns: The exchange's error for the provider's error, or for an event that can't be read when the exchange's
    ///   type can't read the error even with the data's text as its message.
    private func errorEvent(_ data: Data) -> any Error {
        do {
            return exchange.error(
                for: try RequestFailure(errorEventData: data, provider: provider, headers: headers, imageEntries: imageEntries))
        } catch {
            return unreadable(error)
        }
    }
}

extension FinishReason {
    /// The reason for an answer that ended in the host's failure, which throws instead of ending an entry.
    fileprivate static let error: Self = "error"
}

// MARK: - Wire

/// One event of a streamed chat completion, reduced to the members of OpenAI's format that the answer stream reads.
///
/// Keys are listed one by one instead of converted from snake case, because a conversion would also rename the keys
/// of a provider's own members, such as reasoning that goes back unchanged on later turns.
private struct Chunk: Decodable {
    struct Choice: Decodable {
        let delta: Delta?
        let finishReason: FinishReason?

        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: Content?
        /// The next part of a refusal's text. Some providers send a value that isn't text, such as `false`, for no
        /// refusal.
        let refusal: JSONValue?
        let toolCalls: [ToolCall]?
        let annotations: [Annotation]?

        private enum CodingKeys: String, CodingKey {
            case content
            case refusal
            case toolCalls = "tool_calls"
            case annotations
        }
    }

    /// A delta's content, text or a list of parts, as the pieces of the answer's text and reasoning in their order.
    ///
    /// A `text` part is the answer's text, and the `text` parts inside a `thinking` part are its reasoning. Any other
    /// part, of a known type such as a reference or of one the format doesn't know, is passed over.
    struct Content: Decodable {
        /// A piece of the answer's text or reasoning, never empty.
        enum Piece {
            case text(String)
            case reasoning(String)
        }

        let pieces: [Piece]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                pieces = text.isEmpty ? [] : [.text(text)]
            } else {
                pieces = try container.decode([Part].self).compactMap(\.piece)
            }
        }

        /// One part of a list, read as a piece when it's a `text` part with text or a `thinking` part with text.
        private struct Part: Decodable {
            let piece: Piece?

            init(from decoder: any Decoder) throws {
                // Read leniently, so a part of another shape is passed over rather than making the chunk unreadable.
                guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                    piece = nil
                    return
                }
                switch try? container.decode(String.self, forKey: .type) {
                case "text"?:
                    let text = (try? container.decode(String.self, forKey: .text)) ?? ""
                    piece = text.isEmpty ? nil : .text(text)
                case "thinking"?:
                    let parts = (try? container.decode([Part].self, forKey: .thinking)) ?? []
                    let text = parts.compactMap { part in if case .text(let text)? = part.piece { text } else { nil } }.joined()
                    piece = text.isEmpty ? nil : .reasoning(text)
                default:
                    piece = nil
                }
            }

            private enum CodingKeys: String, CodingKey {
                case type
                case text
                case thinking
            }
        }
    }

    /// A note on the answer's text, of which only URL citations are read. Other kinds, such as file annotations, have no
    /// `url_citation`.
    struct Annotation: Decodable {
        /// A web page the text cites. Hosts may leave out any member, so each is optional, and some add the cited
        /// excerpt as `content`.
        struct URLCitation: Decodable {
            let url: String?
            let title: String?
            let content: String?
            let startIndex: Int?
            let endIndex: Int?

            private enum CodingKeys: String, CodingKey {
                case url
                case title
                case content
                case startIndex = "start_index"
                case endIndex = "end_index"
            }
        }

        let urlCitation: URLCitation?

        private enum CodingKeys: String, CodingKey {
            case urlCitation = "url_citation"
        }
    }

    /// A fragment of one tool call. The first fragment of a call carries its id and name, later ones only argument
    /// text.
    struct ToolCall: Decodable {
        struct Function: Decodable {
            let name: String?

            /// The next part of the call's argument text, or the JSON text of arguments a provider sent whole as a JSON
            /// value, such as an object.
            let arguments: String?

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decodeIfPresent(String.self, forKey: .name)
                if let text = try? container.decodeIfPresent(String.self, forKey: .arguments) {
                    arguments = text
                } else {
                    arguments = try container.decodeIfPresent(JSONValue.self, forKey: .arguments)?.text
                }
            }

            private enum CodingKeys: String, CodingKey {
                case name
                case arguments
            }
        }

        let index: Int?
        let id: String?
        let function: Function?
    }

    struct Usage: Decodable {
        struct PromptDetails: Decodable {
            let cachedTokens: Int?
            let cacheWriteTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
                case cacheWriteTokens = "cache_write_tokens"
            }
        }

        struct CompletionDetails: Decodable {
            let reasoningTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let promptTokens: Int?
        let completionTokens: Int?
        let promptTokensDetails: PromptDetails?
        let completionTokensDetails: CompletionDetails?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case promptTokensDetails = "prompt_tokens_details"
            case completionTokensDetails = "completion_tokens_details"
        }
    }

    let id: String?
    let model: String?
    /// The processing tier that served the answer, in the host's word for it.
    let serviceTier: String?
    let choices: [Choice]?
    let usage: Usage?
    /// The `error` object of an error event, which a provider sends after the response's HTTP 200.
    let error: JSONValue?
    /// The `type` that a provider gives an error event that carries the error in its own members, `error`. The
    /// format's chunks have none.
    let type: JSONValue?

    /// Whether the chunk is an error event: one with an `error` object, or one whose `type` is `error`.
    var isError: Bool {
        (error != nil && error != .null) || type == "error"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case serviceTier = "service_tier"
        case choices
        case usage
        case error
        case type
    }
}

/// One server-sent event of a streamed completion: a chunk with the exchange's own members, decoded together from its
/// JSON, which an error event is read from too, or the `[DONE]` that ends the stream.
private enum StreamEvent<Extras: Decodable> {
    case chunk(Chunk, Extras, Data)
    case done

    /// The event a server-sent event carries, or `nil` for one without data.
    ///
    /// - Throws: An error that says why the data isn't a chunk with the exchange's members.
    init?(_ event: ServerSentEvent) throws {
        switch event.data {
        case "": return nil
        case "[DONE]": self = .done
        default:
            let data = Data(event.data.utf8)
            let decoded = try HTTPClient.decoder.decode(Decoded.self, from: data)
            self = .chunk(decoded.chunk, decoded.extras, data)
        }
    }

    /// A chunk and the exchange's members, read in one pass over the JSON.
    private struct Decoded: Decodable {
        let chunk: Chunk
        let extras: Extras

        init(from decoder: any Decoder) throws {
            chunk = try Chunk(from: decoder)
            extras = try Extras(from: decoder)
        }
    }
}
