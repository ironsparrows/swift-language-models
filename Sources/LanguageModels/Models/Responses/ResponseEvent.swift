import Foundation
import LanguageModelsCore

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
