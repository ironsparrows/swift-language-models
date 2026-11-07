import Foundation
import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

// MARK: - Stream

extension ChatCompletions {
    /// One answer's stream: turns the format's chunks, with the exchange's members, into the answer's output, which an
    /// ``AnswerChannel`` sends as Foundation Models channel events.
    ///
    /// Reasoning arrives in the provider's members, and tool-call fragments by index, so parallel calls form one round.
    /// Each piece of data the model generates becomes a data entry of its own. The answer ends with its metadata and usage
    /// on the entry that finishes it, and with the pages it cites on its response entry.
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
    /// - Returns: Whether the event is the `[DONE]` that ends the stream.
    /// - Throws: The exchange's error for an event that isn't a chunk, and for an error event.
    mutating func receive(_ event: ServerSentEvent) async throws -> Bool {
        let streamEvent: StreamEvent<Exchange.ChunkExtras>?
        do {
            streamEvent = try StreamEvent(event)
        } catch {
            throw unreadable(error)
        }
        switch streamEvent {
        case .chunk(let chunk, let extras, let data)?:
            try await receive(chunk, extras: extras, data: data)
            return false
        case .done?:
            return true
        case nil:
            return false
        }
    }

    private mutating func receive(_ chunk: Chunk, extras: Exchange.ChunkExtras, data: Data) async throws {
        report.update(with: chunk)
        let chunkAdditions = exchange.read(extras)
        if let error = chunk.error, error != .null {
            let body: Exchange.ErrorBody
            do {
                body = try HTTPClient.decoder.decode(ErrorEvent.self, from: data).error
            } catch {
                throw unreadable(error)
            }
            throw exchange.error(for: RequestFailure(errorEvent: body, provider: provider, headers: headers, imageEntries: imageEntries))
        }
        guard let delta = chunk.choices?.first?.delta else { return }

        if let reasoning = chunkAdditions.reasoning { await output.appendReasoning(reasoning, model: report.model) }
        if let content = delta.content, !content.isEmpty {
            await output.appendText(content, model: report.model)
        }
        if let text = delta.refusal { refusal += text }
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
    /// Sends the events that end the answer: arguments for calls that had none, the reasoning signature, and the
    /// metadata and usage.
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
    ///   got its name.
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
}

extension FinishReason {
    /// The reason for an answer that ended in the host's failure, which throws instead of ending an entry.
    fileprivate static let error: Self = "error"
}

// MARK: - Wire

/// One event of a streamed chat completion, reduced to the members of OpenAI's format that the answer stream reads.
///
/// Keys are listed one by one instead of converted from snake case, because a conversion would also rename the keys
/// of a provider's own members, such as reasoning that goes back to the host unchanged.
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
        let content: String?
        let refusal: String?
        let toolCalls: [ToolCall]?
        let annotations: [Annotation]?

        private enum CodingKeys: String, CodingKey {
            case content
            case refusal
            case toolCalls = "tool_calls"
            case annotations
        }
    }

    /// A note on the answer's text, of which only URL citations are read. Other kinds, such as file annotations, have
    /// none.
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
            let arguments: String?
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
    /// The `error` object of an error event, which a host sends after the response's HTTP 200.
    let error: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case serviceTier = "service_tier"
        case choices
        case usage
        case error
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

extension ChatCompletions.Stream {
    /// The event of a chunk whose `error` member is set, with the error in the exchange's type.
    private struct ErrorEvent: Decodable {
        let error: Exchange.ErrorBody
    }
}
