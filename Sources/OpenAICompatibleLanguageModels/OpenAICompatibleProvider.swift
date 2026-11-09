public import Foundation
import FoundationModels
import LanguageModels

// MARK: - Provider

/// A provider whose API speaks OpenAI's Chat Completions or Responses format: its name, where its API lives, the format
/// it speaks, the header its API key goes in, and the headers every request carries.
///
/// Describe a provider by its name and the base URL of its API, such as a server of your own:
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
/// `max_output_tokens` and the effort in `reasoning`.
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
