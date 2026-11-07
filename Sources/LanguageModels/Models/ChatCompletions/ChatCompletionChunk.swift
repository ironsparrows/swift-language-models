import Foundation
import LanguageModelsCore

/// One event of a streamed chat completion, reduced to the members of OpenAI's format that the answer stream reads.
///
/// Keys are listed one by one instead of converted from snake case, because a conversion would also rename the keys
/// of a provider's own members, such as reasoning that goes back to the host unchanged.
struct ChatCompletionChunk: Decodable {
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

extension ChatCompletionChunk {
    /// One server-sent event of a streamed completion: a chunk with the dialect's own members, decoded together from
    /// its JSON, which an error event is read from too, or the `[DONE]` that ends the stream.
    enum StreamEvent<Extras: Decodable> {
        case chunk(ChatCompletionChunk, Extras, Data)
        case done

        /// The event a server-sent event carries, or `nil` for one without data.
        ///
        /// - Throws: An error that says why the data isn't a chunk with the dialect's members.
        init?(_ event: ServerSentEvent) throws {
            switch event.data {
            case "": return nil
            case "[DONE]": self = .done
            default:
                let data = Data(event.data.utf8)
                let decoded = try ProviderHTTP.decoder.decode(Decoded.self, from: data)
                self = .chunk(decoded.chunk, decoded.extras, data)
            }
        }

        /// A chunk and the dialect's members, read in one pass over the JSON.
        private struct Decoded: Decodable {
            let chunk: ChatCompletionChunk
            let extras: Extras

            init(from decoder: any Decoder) throws {
                chunk = try ChatCompletionChunk(from: decoder)
                extras = try Extras(from: decoder)
            }
        }
    }
}
