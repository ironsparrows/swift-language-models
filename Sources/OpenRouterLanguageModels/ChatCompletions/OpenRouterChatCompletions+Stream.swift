import Foundation
import FoundationModels
import LanguageModels
import UniformTypeIdentifiers

/// What OpenRouter's chunks report about one answer beyond the format's facts: the host that served it, its cost, the
/// router's report, the response cache's status, and the reasoning details that go back on later turns.
///
/// Chunks repeat some facts and leave out others, so a fact that a chunk reports replaces the earlier one, and one it
/// leaves out keeps its earlier value.
struct OpenRouterStreamState: Sendable {
    /// What the response cache reported in the response's headers, or `nil` when the cache is off.
    let responseCache: OpenRouterResponseCache.Report?

    /// The host that served the answer.
    fileprivate(set) var provider: OpenRouterProviderName?

    /// What OpenRouter added to the usage the last chunk with usage reported.
    fileprivate(set) var usage: OpenRouterChunkExtras.Usage?

    /// How OpenRouter routed the request, when the options include it.
    fileprivate(set) var routerReport: OpenRouterChunkExtras.RouterMetadata?

    /// The `reasoning_details` the model sent, or `nil` when it sent none. Some models send an empty list, and
    /// expect it back.
    fileprivate(set) var reasoningDetails: ReasoningDetails?
}

extension OpenRouterChatCompletions {
    func streamState(_ headers: ResponseHeaders) -> OpenRouterStreamState {
        OpenRouterStreamState(responseCache: OpenRouterResponseCache.Report(header: headers.value(for:)))
    }

    /// Takes a chunk's facts, then the reasoning and images in its delta.
    ///
    /// The reasoning to show is the readable text of the delta's details, or its plain reasoning when it has no
    /// details, since an empty list carries no text; an empty list alone starts the reasoning entry.
    func observe(_ extras: OpenRouterChunkExtras, into stream: inout OpenRouterStreamState) -> ChunkOutput {
        if let provider = extras.provider {
            stream.provider = OpenRouterProviderName(rawValue: provider)
        }
        stream.usage = extras.usage ?? stream.usage
        if model.options.includesRouterMetadata { stream.routerReport = extras.routerMetadata ?? stream.routerReport }
        guard let delta = extras.choices?.first?.delta else { return ChunkOutput() }
        if let details = delta.reasoningDetails {
            if stream.reasoningDetails == nil { stream.reasoningDetails = ReasoningDetails() }
            for detail in details { stream.reasoningDetails?.append(detail) }
        }
        var output = ChunkOutput(generatedData: (delta.images ?? []).compactMap(Self.data(of:)))
        if let details = delta.reasoningDetails, !details.isEmpty {
            output.reasoning = ReasoningDetails.readableText(in: details)
        } else if let reasoning = delta.reasoning, !reasoning.isEmpty {
            output.reasoning = reasoning
        } else if delta.reasoningDetails != nil {
            output.reasoning = ""
        }
        return output
    }

    /// The host, the response cache's report and the router's; the cost, its parts, whether the account's own key paid
    /// and the server tools' counts; and the reasoning details as the reasoning entry's signature.
    func facts(of stream: OpenRouterStreamState) -> AnswerAdditions {
        var metadata: [String: any ConvertibleToGeneratedContent] = [:]
        metadata[LanguageModelMetadataKey.provider] = stream.provider?.rawValue
        metadata.merge(stream.responseCache?.metadata ?? [:]) { $1 }
        metadata.merge(stream.routerReport?.metadata ?? [:]) { $1 }
        var usage: [String: any ConvertibleToGeneratedContent] = [:]
        usage[LanguageModelMetadataKey.cost] = stream.usage?.cost
        usage[OpenRouterMetadataKey.isBYOK] = stream.usage?.isBYOK
        let costs = stream.usage?.costDetails
        usage[OpenRouterMetadataKey.upstreamInferenceCost] = costs?.upstreamInferenceCost
        usage[OpenRouterMetadataKey.upstreamInferencePromptCost] = costs?.upstreamInferencePromptCost
        usage[OpenRouterMetadataKey.upstreamInferenceCompletionCost] = costs?.upstreamInferenceCompletionsCost
        usage[OpenRouterMetadataKey.serverToolCost] = costs?.serverToolCost
        let serverTools = stream.usage?.serverToolUseDetails
        usage[OpenRouterMetadataKey.requestedServerToolCallCount] = serverTools?.toolCallsRequested
        usage[OpenRouterMetadataKey.executedServerToolCallCount] = serverTools?.toolCallsExecuted
        usage[LanguageModelMetadataKey.webSearchCount] = serverTools?.webSearchRequests
        return AnswerAdditions(
            host: stream.provider?.rawValue, metadata: metadata, usageMetadata: usage,
            reasoningSignature: stream.reasoningDetails?.signature)
    }

    /// `LanguageModelError` for a failure Foundation Models has a case for, and `OpenRouterError` for the rest: with
    /// `invalidResponse` for a response the format couldn't use, naming the host unless an event couldn't be read, and
    /// with `server` for an answer that ended in the host's failure.
    func error(for failure: ChatCompletionsFailure<Self>) -> MappedError<OpenRouterError> {
        let host = failure.state?.provider
        switch failure.kind {
        case .rejected(let rejection):
            return OpenRouterFailure(rejection).error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .errorEvent(let body):
            let streamFailure = OpenRouterFailure(streamError: body, provider: host)
            return streamFailure.error(contextSize: details.contextSize, imageEntries: failure.imageEntries)
        case .unusableResponse(let problem):
            let named = if case .unreadableEvent = problem { nil as OpenRouterProviderName? } else { host }
            return .provider(OpenRouterError(message: failure.message, code: .invalidResponse, providerName: named))
        case .failedAnswer:
            return .provider(OpenRouterError(message: failure.message, code: .server, providerName: host))
        }
    }

    /// An image as data of the kind its data URL names, or `nil` for one that isn't inline data, such as one at a web
    /// address.
    private static func data(of image: OpenRouterChunkExtras.GeneratedImage) -> GeneratedData? {
        guard let url = image.imageURL?.url, let inline = DataURL(url) else { return nil }
        let type = UTType(mimeType: inline.mediaType, conformingTo: .image) ?? .image
        return GeneratedData(contentType: type, content: inline.data)
    }
}

/// The members of a streamed chunk that only OpenRouter sends, read from the same JSON as the format's own: the host,
/// the reasoning and images in the delta, the cost in the usage and the router's report. An error's members are read
/// as an `OpenRouterErrorResponse`.
///
/// Keys are listed one by one instead of converted from snake case, because a conversion would also rename the keys
/// inside `reasoning_details`, which go back to OpenRouter unchanged.
struct OpenRouterChunkExtras: Decodable {
    struct Choice: Decodable {
        let delta: Delta?
    }

    struct Delta: Decodable {
        let reasoning: String?
        let reasoningDetails: [JSONValue]?
        let images: [GeneratedImage]?

        private enum CodingKeys: String, CodingKey {
            case reasoning
            case reasoningDetails = "reasoning_details"
            case images
        }
    }

    /// An image the model generated, whole in one delta, usually as a data URL such as `data:image/png;base64,…`.
    struct GeneratedImage: Decodable {
        struct ImageURL: Decodable {
            let url: String?
        }

        let imageURL: ImageURL?

        private enum CodingKeys: String, CodingKey {
            case imageURL = "image_url"
        }
    }

    /// What OpenRouter adds to the usage: the cost, its parts, whether the account's own key paid, and how often
    /// the server tools ran.
    struct Usage: Decodable {
        /// The parts of the cost, in US dollars.
        struct CostDetails: Decodable {
            let upstreamInferenceCost: Double?
            let upstreamInferencePromptCost: Double?
            let upstreamInferenceCompletionsCost: Double?
            let serverToolCost: Double?

            private enum CodingKeys: String, CodingKey {
                case upstreamInferenceCost = "upstream_inference_cost"
                case upstreamInferencePromptCost = "upstream_inference_prompt_cost"
                case upstreamInferenceCompletionsCost = "upstream_inference_completions_cost"
                case serverToolCost = "server_tool_cost"
            }
        }

        /// How often the server tools ran.
        struct ServerToolUseDetails: Decodable {
            let toolCallsRequested: Int?
            let toolCallsExecuted: Int?
            let webSearchRequests: Int?

            private enum CodingKeys: String, CodingKey {
                case toolCallsRequested = "tool_calls_requested"
                case toolCallsExecuted = "tool_calls_executed"
                case webSearchRequests = "web_search_requests"
            }
        }

        let cost: Double?
        let costDetails: CostDetails?
        let isBYOK: Bool?
        let serverToolUseDetails: ServerToolUseDetails?

        private enum CodingKeys: String, CodingKey {
            case cost
            case costDetails = "cost_details"
            case isBYOK = "is_byok"
            case serverToolUseDetails = "server_tool_use_details"
        }
    }

    /// What OpenRouter's router did for the request, on the last chunk or beside the error of a failed response. Every
    /// field is optional, since OpenRouter adds fields over time and leaves some out.
    struct RouterMetadata: Decodable {
        struct Endpoints: Decodable {
            struct Endpoint: Decodable {
                let provider: String?
                let model: String?
                let selected: Bool?
            }

            let available: [Endpoint]?
        }

        struct Attempt: Decodable {
            let provider: String?
            let model: String?
            let status: Int?
        }

        /// A plugin that changed the request or the answer.
        struct Stage: Decodable {
            let type: String?
            let name: String?
            let summary: String?
            /// The plugin's own details, which are free-form.
            let data: JSONValue?

            /// Whether the stage is a guardrail that blocked the request.
            var isGuardrailBlock: Bool { type == "guardrail" && data?["action"]?.stringValue == "blocked" }
        }

        let strategy: String?
        let attempt: Int?
        let attempts: [Attempt]?
        let endpoints: Endpoints?
        /// The milliseconds from sending the request to the host until its answer ended.
        let generationTime: Double?
        let region: String?
        let pipeline: [Stage]?

        /// Whether a guardrail blocked the request.
        var isGuardrailBlock: Bool { pipeline?.contains(where: \.isGuardrailBlock) == true }

        private enum CodingKeys: String, CodingKey {
            case strategy
            case attempt
            case attempts
            case endpoints
            case generationTime = "generation_time"
            case region
            case pipeline
        }
    }

    let provider: String?
    let choices: [Choice]?
    let usage: Usage?
    let routerMetadata: RouterMetadata?

    private enum CodingKeys: String, CodingKey {
        case provider
        case choices
        case usage
        case routerMetadata = "openrouter_metadata"
    }
}
