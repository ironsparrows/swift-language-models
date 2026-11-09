public import Foundation
import FoundationModels
import LanguageModels

// MARK: - Provider

/// A provider whose API speaks OpenAI's Chat Completions or Responses format: its name, where its API lives, the format
/// it speaks, the header its API key goes in, and the headers every request carries.
///
/// For a provider the module knows, use its preset, which also carries what that provider does differently, such as the
/// members it refuses and how its reasoning goes back on later turns:
///
/// ```swift
/// let model = OpenAICompatibleLanguageModel(
///     OpenAICompatibleModel("openai/gpt-oss-20b", on: .groq, reasoning: .mandatory, efforts: [.high, .medium, .low]),
///     auth: .apiKey { try await keyStore.groqKey() }
/// )
/// ```
///
/// Describe any other provider by its name and the base URL of its API, such as a server of your own:
///
/// ```swift
/// let gateway = OpenAICompatibleProvider(name: "Gateway", url: URL(string: "https://llm.example.com/v1")!)
/// let model = OpenAICompatibleLanguageModel(
///     OpenAICompatibleModel("my-model", on: gateway),
///     auth: .apiKey { try await keyStore.gatewayKey() }
/// )
/// ```
///
/// Requests go to the format's path under ``url``: `chat/completions` for Chat Completions and `responses` for
/// Responses. To a provider described this way, a Chat Completions request asks for a usage chunk and sends the token
/// limit as `max_tokens` and the reasoning effort as `reasoning_effort`, and a Responses request sends the token limit as
/// `max_output_tokens` and the effort in `reasoning`. <doc:Providers> says what each preset does differently.
public struct OpenAICompatibleProvider: Sendable, Hashable {
    /// The provider's name, such as `Gateway`, which the log's category and the errors name.
    ///
    /// The reasoning entries of the provider's answers carry it, in lowercase, so their reasoning goes back only to the
    /// same provider. Saved transcripts keep it, so keep a provider's name the same from one version of the app to the
    /// next.
    public let name: String

    /// The base URL of the provider's API, such as `https://api.example.com/v1`, which `chat/completions` or `responses`
    /// goes under.
    public private(set) var url: URL

    /// The format the provider's requests and answers use.
    public let format: Format

    /// The header an API key goes in, from ``OpenAICompatibleAuthentication/apiKey(_:)``.
    public let keyHeader: KeyHeader

    /// Headers that every request carries, such as a gateway's routing header. A header of the authentication's, such
    /// as the API key's, replaces one of the same name here, and so do `User-Agent`, `Content-Type` and `Accept`, which
    /// the package sets on every request.
    ///
    /// They go to the provider with every request, so an API key goes in ``OpenAICompatibleAuthentication`` instead,
    /// which reads it for each request and never stores it.
    public var headers: [String: String]

    // MARK: What the provider does differently

    /// How requests are sent when a model is created without a configuration of its own.
    var configuration = OpenAICompatibleConfiguration()

    /// The statuses of a failed response that are sent again, as the configuration's retries allow: a 408, 409 or 429,
    /// and any status from 500 up.
    var retriedStatuses = RetriedStatuses.transient

    /// What a model on the provider can do when its details don't say: tool calling, guided generation and vision.
    /// Whether it reasons is ``defaultReasoning``.
    var defaultCapabilities: Set<LanguageModelCapabilities.Capability> = [.toolCalling, .guidedGeneration, .vision]

    /// Whether a model on the provider reasons when its details don't say: only when a request asks it to.
    var defaultReasoning = ModelReasoning.offByDefault

    /// The effort words a model on the provider accepts when its details don't say, highest first.
    var defaultEffortWords = ["xhigh", "high", "medium", "low", "minimal", "none"]

    /// The Chat Completions members the provider refuses, or doesn't document, which a request leaves out and logs,
    /// unless the app's members carry them.
    var unsupportedMembers: Set<ChatCompletions.Member> = []

    /// The member a Chat Completions request's token limit goes in.
    var tokenLimitMember = ChatCompletions.Member.maxTokens

    /// Whether a Chat Completions request asks for a usage chunk, which a provider that reports usage only when asked
    /// needs.
    var asksForUsage = true

    /// Whether a Chat Completions request that sends a reasoning effort also sends `thinking`, disabled for the effort
    /// `none` and enabled for any other, for a provider whose `thinking` decides whether the model reasons.
    var sendsThinking = false

    /// How the provider's own reasoning goes back on later turns of Chat Completions.
    var reasoningReplay = ReasoningReplay.notSent

    /// Whether a request that sends both tools and a schema is refused before it's sent, for a provider that refuses
    /// the two together.
    var refusesSchemaWithTools = false

    /// Whether a request that requires a tool call is refused before it's sent while the model reasons, for a provider
    /// that takes a required call only with reasoning off.
    var refusesRequiredCallWhileReasoning = false

    /// The provider's finish reasons that stand for one of the format's, such as its word for an answer its servers cut
    /// short, which fails the answer as `error` does.
    var finishReasons: [FinishReason: FinishReason] = [:]

    /// The headers the provider's id for a request comes in, in the order they're read.
    var requestIDHeaders = [API.Header.requestID]

    /// The company whose servers run the provider's models, which answers and `LanguageModelError`s name as their host,
    /// or `nil` when the module can't know it.
    var host: String?

    /// What the provider's own words say a failure is, beyond what its status and code say.
    var failureWords = FailureWords()

    /// Creates a provider.
    ///
    /// - Parameters:
    ///   - name: The provider's name, which the log's category and the errors name, and the reasoning of its answers
    ///     carries.
    ///   - url: The base URL of the provider's API, which `chat/completions` or `responses` goes under.
    ///   - format: The format the provider's requests and answers use.
    ///   - keyHeader: The header an API key goes in.
    ///   - headers: Headers that every request carries.
    public init(
        name: String,
        url: URL,
        format: Format = .chatCompletions,
        keyHeader: KeyHeader = .bearer,
        headers: [String: String] = [:]
    ) {
        self.name = name
        self.url = url
        self.format = format
        self.keyHeader = keyHeader
        self.headers = headers
    }

    /// The same provider at another address, such as a gateway in front of it or a server on another port, with
    /// everything else it does kept.
    ///
    /// - Parameter url: The base URL that stands in for the provider's, which `chat/completions` or `responses` goes
    ///   under.
    /// - Returns: The provider at `url`.
    public func at(_ url: URL) -> Self {
        var provider = self
        provider.url = url
        return provider
    }
}

// MARK: - Presets

extension OpenAICompatibleProvider {
    /// Google's Gemini API, at `https://generativelanguage.googleapis.com/v1beta/openai/`, with the key as a bearer
    /// token.
    ///
    /// ```swift
    /// let model = OpenAICompatibleLanguageModel(
    ///     OpenAICompatibleModel("gemini-3.1-flash-lite", on: .gemini),
    ///     auth: .apiKey { try await keyStore.geminiKey() }
    /// )
    /// ```
    ///
    /// By default, a model on it reasons unless a request turns reasoning off, and accepts the efforts `high`,
    /// `medium`, `low`, `minimal` and `none`. Requests leave out `seed` and request metadata, which Gemini refuses, and
    /// a failed request isn't sent again. Each answer's thought signature goes back with it on later turns, to the
    /// model that wrote it: on its first tool call, or on its message when it has no call. A first tool call that
    /// another provider or model made goes back with a placeholder that Gemini takes in place of a signature. A 400 for
    /// a missing or invalid key has the code `authentication`, as a 401 has, a rate limit's reset date comes from the
    /// wait Gemini names in its body, and a prompt over the model's context throws
    /// `LanguageModelError.contextSizeExceeded` with the sizes Gemini names.
    public static let gemini: Self = {
        var gemini = Self(name: "Gemini", url: url("https://generativelanguage.googleapis.com/v1beta/openai/"))
        gemini.configuration.retries = .disabled
        gemini.defaultReasoning = .onByDefault
        gemini.defaultEffortWords = ["high", "medium", "low", "minimal", "none"]
        gemini.unsupportedMembers = [.seed, .metadata]
        gemini.reasoningReplay = .thoughtSignatures
        gemini.host = "Google AI Studio"
        gemini.failureWords.refusedKey = ["Missing or invalid Authorization header", "API key not valid"]
        gemini.failureWords.oversizedContext = ["exceeds the maximum number of tokens allowed"]
        return gemini
    }()

    /// Groq, at `https://api.groq.com/openai/v1`, with the key as a bearer token.
    ///
    /// ```swift
    /// let model = OpenAICompatibleLanguageModel(
    ///     OpenAICompatibleModel("openai/gpt-oss-20b", on: .groq, reasoning: .mandatory, efforts: [.high, .medium, .low]),
    ///     auth: .apiKey { try await keyStore.groqKey() }
    /// )
    /// ```
    ///
    /// By default, a model on it reasons only when a request asks it to, and accepts the efforts `high`, `medium`,
    /// `low` and `none`. Groq's models take different efforts, so name a model's own, as above. Requests send the token
    /// limit as `max_completion_tokens`, leave out request metadata, which Groq refuses, and don't ask for a usage
    /// chunk, since Groq reports usage on an answer's last chunk. A model's reasoning goes back on later turns as
    /// `reasoning`, to that model only. A request that sends both tools and a schema is refused before it's sent, since
    /// Groq refuses the two together, and a guided answer that Groq finds breaks its schema throws
    /// `GeneratedContent.ParsingError`. Requests wait up to 60 seconds for the next data, and a failed one is sent
    /// again up to twice.
    public static let groq: Self = {
        var groq = Self(name: "Groq", url: url("https://api.groq.com/openai/v1"))
        groq.configuration.idleTimeout = .seconds(60)
        groq.defaultEffortWords = ["high", "medium", "low", "none"]
        groq.unsupportedMembers = [.metadata]
        groq.tokenLimitMember = .maxCompletionTokens
        groq.asksForUsage = false
        groq.reasoningReplay = .reasoning
        groq.refusesSchemaWithTools = true
        groq.host = "Groq"
        groq.failureWords.schemaMisses = ["json_validate_failed"]
        return groq
    }()

    /// DeepSeek, at `https://api.deepseek.com`, with the key as a bearer token.
    ///
    /// ```swift
    /// let model = OpenAICompatibleLanguageModel(
    ///     OpenAICompatibleModel("deepseek-flash", on: .deepSeek),
    ///     auth: .apiKey { try await keyStore.deepSeekKey() }
    /// )
    /// ```
    ///
    /// By default, a model on it reasons unless a request turns reasoning off, takes tools and images but no schema,
    /// since DeepSeek takes no JSON Schema for an answer, and accepts the efforts `max`, `high`, `medium`, `low` and
    /// `none`, where DeepSeek takes `medium` as `high`. A request that sets a reasoning level also sends `thinking`:
    /// disabled for ``FoundationModels/ContextOptions/ReasoningLevel/off`` and enabled for any other level, and a model
    /// that doesn't reason sends it disabled with every request. Requests leave out `seed` and request metadata, which
    /// DeepSeek's documentation doesn't list. The model's reasoning goes back on later turns as `reasoning_content`,
    /// which DeepSeek needs on the earlier answers of a request with tools. A request that requires a tool call is
    /// refused before it's sent while the model reasons, since DeepSeek takes a required call only with reasoning off.
    /// An answer DeepSeek's servers cut short, which ends with `insufficient_system_resource` or `aborted`, throws
    /// ``OpenAICompatibleError``, and a request DeepSeek's content filter refuses throws
    /// `LanguageModelError.guardrailViolation`. The preset follows DeepSeek's documentation and hasn't been run against
    /// its API; <doc:Providers> says what was checked.
    public static let deepSeek: Self = {
        var deepSeek = Self(name: "DeepSeek", url: url("https://api.deepseek.com"))
        deepSeek.defaultCapabilities = [.toolCalling, .vision]
        deepSeek.defaultReasoning = .onByDefault
        deepSeek.defaultEffortWords = ["max", "high", "medium", "low", "none"]
        deepSeek.unsupportedMembers = [.seed, .metadata]
        deepSeek.sendsThinking = true
        deepSeek.reasoningReplay = .reasoningContent
        deepSeek.refusesRequiredCallWhileReasoning = true
        deepSeek.finishReasons = ["insufficient_system_resource": .failed, "aborted": .failed]
        deepSeek.requestIDHeaders = ["request-id", API.Header.requestID, "x-deepseek-request-id"]
        deepSeek.host = "DeepSeek"
        deepSeek.failureWords.refusedContent = ["Content Exists Risk"]
        return deepSeek
    }()

    /// Mistral AI, at `https://api.mistral.ai/v1`, with the key as a bearer token.
    ///
    /// ```swift
    /// let model = OpenAICompatibleLanguageModel(
    ///     OpenAICompatibleModel("mistral-small-latest", on: .mistral),
    ///     auth: .apiKey { try await keyStore.mistralKey() }
    /// )
    /// ```
    ///
    /// By default, a model on it reasons only when a request asks it to, and accepts the efforts `max`, `xhigh`,
    /// `high`, `medium`, `low`, `minimal` and `none`. Requests leave out `seed`, for which Mistral has `random_seed`,
    /// and don't ask for a usage chunk, since Mistral reports usage on an answer's last chunk. Reasoning arrives in the
    /// answer's thinking parts and doesn't go back on later turns. An answer that ends with `model_length` counts as
    /// one that reached its token limit. Mistral is reported to take tool call ids of nine letters and digits only, so
    /// a transcript whose calls another provider made may fail there. Requests wait up to 300 seconds for the next
    /// data, and a failed one isn't sent again. Mistral's servers in the EU and the US are `.mistral.at(_:)` with
    /// `https://api.eu.mistral.ai/v1` or `https://api.us.mistral.ai/v1`. The preset follows Mistral's documentation and
    /// SDKs and hasn't been run against its API; <doc:Providers> says what was checked.
    public static let mistral: Self = {
        var mistral = Self(name: "Mistral", url: url("https://api.mistral.ai/v1"))
        mistral.configuration.idleTimeout = .seconds(300)
        mistral.configuration.retries = .disabled
        mistral.defaultEffortWords = ["max", "xhigh", "high", "medium", "low", "minimal", "none"]
        mistral.unsupportedMembers = [.seed]
        mistral.asksForUsage = false
        mistral.finishReasons = ["model_length": .length]
        mistral.host = "Mistral"
        return mistral
    }()

    /// The URL of a preset's API.
    private static func url(_ string: StaticString) -> URL {
        guard let url = URL(string: "\(string)") else { preconditionFailure("\(string) isn't a valid URL.") }
        return url
    }
}

// MARK: - Format and key header

extension OpenAICompatibleProvider {
    /// A format a provider's requests and answers use.
    @nonexhaustive
    public enum Format: Sendable, Hashable {
        /// Chat Completions: a `POST` to `chat/completions`, which nearly every provider takes.
        case chatCompletions

        /// Responses: a `POST` to `responses`.
        case responses
    }

    /// The header an API key goes in.
    public struct KeyHeader: Sendable, Hashable {
        /// `Authorization: Bearer` and the key, as most providers read it.
        public static let bearer = Self(name: nil)

        /// A header of this name with the key as its whole value, such as `api-key`.
        ///
        /// - Parameter name: The header's name.
        /// - Returns: The key header.
        public static func named(_ name: String) -> Self {
            Self(name: name)
        }

        /// The header's name, or `nil` for a bearer token in `Authorization`.
        private let name: String?

        /// The header that carries a key.
        func header(for key: String) -> [String: String] {
            name.map { [$0: key] } ?? Connection.Authentication.bearerHeader(key)
        }
    }
}

// MARK: - Reasoning back and failure words

extension FinishReason {
    /// The format's word for an answer that ended in the provider's failure, which a provider's own word for one stands
    /// for.
    fileprivate static let failed: Self = "error"
}

extension OpenAICompatibleProvider {
    /// How a provider's own reasoning goes back on later turns of Chat Completions. Reasoning that another provider
    /// wrote never does.
    enum ReasoningReplay: Sendable, Hashable {
        /// It doesn't go back.
        case notSent

        /// As each answer's `reasoning_content`, whichever model on the provider wrote it.
        case reasoningContent

        /// As each answer's `reasoning`, only to the model that wrote it, or one it's a dated version of, since a model
        /// that doesn't reason may refuse the member.
        case reasoning

        /// As each answer's thought signature, only to the model that wrote it, or one it's a dated version of: on the
        /// answer's first tool call, or on its message when it has no call. A first tool call whose answer has no
        /// signature that goes back, such as one another provider or model made, goes with a placeholder that skips the
        /// provider's check.
        case thoughtSignatures
    }

    /// What a provider's own words say a failure is, beyond what its status and code say.
    struct FailureWords: Sendable, Hashable {
        /// Words in the message of a 400 that say the request's API key is missing or refused, as a 401 says.
        var refusedKey: [String] = []

        /// Words in the message of a 400 that say the prompt is longer than the model's context.
        var oversizedContext: [String] = []

        /// Words in a failure's message that say the provider's content filter refused the request.
        var refusedContent: [String] = []

        /// The codes of an error that say a guided answer broke its schema.
        var schemaMisses: Set<String> = []
    }
}

// MARK: - What requests and model details read

extension OpenAICompatibleProvider {
    /// The provider's name as the reasoning entries of its answers carry it in their origin, in lowercase.
    var reasoningName: String {
        name.lowercased()
    }

    /// The effort levels a model on the provider accepts when its details don't say, highest first.
    var defaultEfforts: [ContextOptions.ReasoningLevel] {
        defaultEffortWords.map(ContextOptions.ReasoningLevel.custom)
    }
}
