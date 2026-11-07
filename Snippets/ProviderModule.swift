// snippet.hide
// swift-format-ignore-file: AllPublicDeclarationsHaveDocumentation
import Foundation
import FoundationModels
import LanguageModelsCore
import UniformTypeIdentifiers

// snippet.show
// snippet.details
/// The id of one of Vendor's models, in a type of its own, so another provider's id can't be passed for it.
public struct VendorModelID: ProviderVocabulary {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The reasoning levels Vendor's models accept.
public enum VendorEffort: String, ModelEffort {
    case high, low
}

/// What Vendor reports about one of its models.
public struct VendorModel: ModelDetails {
    public let id: VendorModelID
    public let displayName: String
    public let capabilities: LanguageModelCapabilities
    public let reasoning: ModelReasoning
    public let contextSize: Int?
    public let reasoningEfforts: [VendorEffort]
    public let defaultReasoningEffort: VendorEffort?
    public let removalDate: Date?
    public let dataAttachmentTypes: Set<UTType>
    public let dataEntryTypes: Set<UTType>

    /// A model that reasons when a request asks it to.
    public static let small = VendorModel(
        id: "vendor-small",
        displayName: "Vendor Small",
        capabilities: LanguageModelCapabilities([.toolCalling, .guidedGeneration, .reasoning]),
        reasoning: .offByDefault,
        contextSize: 128_000,
        reasoningEfforts: [.high, .low],
        defaultReasoningEffort: .low,
        removalDate: nil,
        dataAttachmentTypes: [],
        dataEntryTypes: []
    )
}
// snippet.end

// snippet.configuration
/// How the module sends its requests, apart from what goes in them.
public struct VendorConfiguration: Sendable, Hashable {
    /// The longest time to wait for the next data, or `nil` for the URL session's own timeout.
    public var idleTimeout: Duration?

    /// How a request that fails before any data arrives is sent again.
    public var retries: RequestRetries

    public init(idleTimeout: Duration? = .seconds(300), retries: RequestRetries = .standard) {
        self.idleTimeout = idleTimeout
        self.retries = retries
    }
}
// snippet.end

// snippet.model
/// How the model's requests reach Vendor. It holds the app's secret, so it stays on the model.
public struct VendorAuthentication: Sendable {
    let baseURL: URL
    let apiKey: @Sendable () async throws -> String

    /// Sends the key the closure returns, which the app can fetch when a request needs it.
    public static func apiKey(baseURL: URL, _ apiKey: @escaping @Sendable () async throws -> String) -> Self {
        Self(baseURL: baseURL, apiKey: apiKey)
    }
}

/// One of Vendor's models, to answer in a Foundation Models session.
public struct VendorLanguageModel: DetailedLanguageModel {
    public let details: VendorModel

    /// The models Vendor tries, in order, when this one fails.
    public let fallbacks: [VendorModel]

    /// How the model sends its requests, which an app can change the same way for every provider.
    public var configuration: VendorConfiguration

    /// The URL session that sends the model's requests.
    let session: URLSession

    let auth: VendorAuthentication

    public init(
        _ details: VendorModel,
        fallbacks: [VendorModel] = [],
        session: URLSession = .shared,
        configuration: VendorConfiguration = VendorConfiguration(),
        auth: VendorAuthentication
    ) {
        self.details = details
        self.fallbacks = fallbacks
        self.session = session
        self.configuration = configuration
        self.auth = auth
    }

    public var executorConfiguration: Executor.Configuration {
        Executor.Configuration(url: auth.baseURL, settings: configuration)
    }
}
// snippet.end

// snippet.executor
extension VendorLanguageModel {
    /// Sends a model's requests to Vendor and streams each answer into Foundation Models.
    public struct Executor: LanguageModelExecutor {
        public typealias Model = VendorLanguageModel

        /// Where requests go and how they're sent. It holds no secrets.
        public struct Configuration: Sendable, Hashable {
            let url: URL
            let settings: VendorConfiguration
        }

        private let configuration: Configuration

        public init(configuration: Configuration) {
            self.configuration = configuration
        }

        public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: VendorLanguageModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            model.reportRemovedModels(for: request)

            let lines = try await send(request, model: model).lines
            let answer = Answer()
            var responseText = ""
            var toolCalls: [Event.ToolCall] = []

            for try await line in lines {
                try Task.checkCancellation()
                let event = try JSONDecoder().decode(Event.self, from: Data(line.utf8))
                if let reasoning = event.reasoning {
                    await channel.send(.reasoning(entryID: answer.reasoningID, action: .appendText(reasoning, tokenCount: 1)))
                }
                if let text = event.text {
                    responseText += text
                    await channel.send(.response(entryID: answer.responseID, action: .appendText(text, tokenCount: 1)))
                }
                if let call = event.toolCall {
                    toolCalls.append(call)
                    let arguments = LanguageModelExecutorGenerationChannel.ToolCalls.ToolCall.Action.appendArguments(
                        call.arguments,
                        tokenCount: 1
                    )
                    await channel.send(
                        .toolCalls(entryID: answer.toolCallsID, action: .toolCall(id: call.id, name: call.name, action: arguments))
                    )
                }
                if let end = event.end {
                    await report(end, of: answer, endingIn: toolCalls.first, into: channel)
                }
            }

            try model.checkGuides(ofResponseText: toolCalls.isEmpty ? responseText : "", for: request)
        }

        /// Sends a request, retrying a server error as the configuration says, and returns the bytes of its answer.
        private func send(
            _ request: LanguageModelExecutorGenerationRequest,
            model: VendorLanguageModel
        ) async throws -> URLSession.AsyncBytes {
            var urlRequest = URLRequest(url: configuration.url)
            urlRequest.httpMethod = "POST"
            urlRequest.httpBody = try JSONEncoder().encode(Body(request, model: model.details.id))
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(try await model.auth.apiKey())", forHTTPHeaderField: "Authorization")
            if let idleTimeout = configuration.settings.idleTimeout {
                urlRequest.timeoutInterval = idleTimeout / .seconds(1)
            }

            let retries = configuration.settings.retries
            var attempt = 0
            while true {
                let (bytes, response) = try await model.session.bytes(for: urlRequest)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return bytes }
                if status >= 500, attempt < retries.limit {
                    try await Task.sleep(for: retries.initialDelay * (1 << attempt))
                    attempt += 1
                    continue
                }
                throw try await failure(status: status, body: bytes)
            }
        }
    }
}
// snippet.end

// snippet.body
/// What a request sends.
private struct Body: Encodable {
    struct Message: Encodable {
        let role: String
        let text: String
    }

    struct Tool: Encodable {
        let name: String
        let description: String
        let parameters: GenerationSchema
    }

    let model: VendorModelID
    let messages: [Message]
    let tools: [Tool]
    let schema: GenerationSchema?

    init(_ request: LanguageModelExecutorGenerationRequest, model: VendorModelID) {
        self.model = model
        messages = request.transcript.compactMap(Message.init(entry:))
        tools = request.enabledToolDefinitions.map {
            Tool(name: $0.name, description: $0.description, parameters: $0.parameters)
        }
        schema = request.schema
    }
}

extension Body.Message {
    /// The message for a transcript entry's text. A real module sends every kind of entry and attachment it takes.
    fileprivate init?(entry: Transcript.Entry) {
        switch entry {
        case .instructions(let instructions): self.init(role: "system", text: Self.text(of: instructions.segments))
        case .prompt(let prompt): self.init(role: "user", text: Self.text(of: prompt.segments))
        case .response(let response): self.init(role: "assistant", text: Self.text(of: response.segments))
        case .toolOutput(let output): self.init(role: "tool", text: Self.text(of: output.segments))
        default: return nil
        }
    }

    private static func text(of segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            if case .text(let text) = segment { text.content } else { nil }
        }
        .joined()
    }
}
// snippet.end

// snippet.report
extension VendorLanguageModel.Executor {
    /// Puts what Vendor reported on the entry that ends the answer, and on its usage.
    private func report(
        _ end: Event.End,
        of answer: Answer,
        endingIn firstCall: Event.ToolCall?,
        into channel: LanguageModelExecutorGenerationChannel
    ) async {
        let cost = ProviderUsageMetadata(cost: end.cost)
        let metadata = ProviderResponseMetadata(
            model: end.model,
            host: "Vendor",
            finishReason: end.finishReason.map(FinishReason.init(rawValue:)),
            usage: cost
        )
        let input = LanguageModelExecutorGenerationChannel.Usage.Input(totalTokenCount: end.inputTokens, cachedTokenCount: 0)
        let output = LanguageModelExecutorGenerationChannel.Usage.Output(totalTokenCount: end.outputTokens, reasoningTokenCount: 0)

        if let firstCall {
            // Foundation Models keeps no readable metadata on a tool-calls entry, so the facts go on its first call.
            let facts = LanguageModelExecutorGenerationChannel.ToolCalls.ToolCall.Action.updateMetadata(metadata.channelMetadata)
            await channel.send(
                .toolCalls(entryID: answer.toolCallsID, action: .toolCall(id: firstCall.id, name: firstCall.name, action: facts))
            )
            await channel.send(
                .toolCalls(entryID: answer.toolCallsID, action: .updateUsage(input: input, output: output, metadata: cost.channelMetadata))
            )
        } else {
            await channel.send(.response(entryID: answer.responseID, action: .updateMetadata(metadata.channelMetadata)))
            await channel.send(
                .response(entryID: answer.responseID, action: .updateUsage(input: input, output: output, metadata: cost.channelMetadata))
            )
        }
    }
}
// snippet.end

// snippet.failure
/// A failure Foundation Models has no case for, such as a rejected key.
public struct VendorError: Error {
    public let status: Int
    public let message: String
}

extension VendorLanguageModel.Executor {
    /// What a rejected request throws: Foundation Models' own error when it has a case, so the same `catch` works for
    /// every model, and the module's for the rest.
    private func failure(status: Int, body: URLSession.AsyncBytes) async throws -> any Error {
        var data = Data()
        for try await byte in body { data.append(byte) }
        let rejection = try JSONDecoder().decode(Rejection.self, from: data)

        let metadata = ProviderErrorMetadata(status: status, code: rejection.code, host: "Vendor").contextMetadata
        switch rejection.code {
        case "rate_limited":
            return LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: rejection.message, metadata: metadata))
        case "context_too_long":
            var exceeded = LanguageModelError.ContextSizeExceeded(
                contextSize: rejection.contextSize ?? 0,
                tokenCount: rejection.tokenCount ?? 0,
                debugDescription: rejection.message
            )
            // Foundation Models 2.1.14, in Xcode 27.2, drops the initializer's `metadata` argument.
            exceeded.metadata = metadata
            return LanguageModelError.contextSizeExceeded(exceeded)
        default:
            return VendorError(status: status, message: rejection.message)
        }
    }
}
// snippet.end

// snippet.hide
/// The ids of one answer's entries, so that each event adds to the entry it belongs to.
private struct Answer {
    let reasoningID = UUID().uuidString
    let responseID = UUID().uuidString
    let toolCallsID = UUID().uuidString
}

/// One line of Vendor's stream.
private struct Event: Decodable {
    struct ToolCall: Decodable {
        let id: String
        let name: String
        let arguments: String
    }

    struct End: Decodable {
        let model: String?
        let finishReason: String?
        let inputTokens: Int
        let outputTokens: Int
        let cost: Decimal?
    }

    let reasoning: String?
    let text: String?
    let toolCall: ToolCall?
    let end: End?
}

/// The body of a rejected request.
private struct Rejection: Decodable {
    let code: String
    let message: String
    let contextSize: Int?
    let tokenCount: Int?
}
