public import Foundation
public import FoundationModels
// Re-exports `LanguageModels`, and through it the core every provider shares, so `import OpenAICompatibleLanguageModels`
// is all an app needs: reasoning levels, `FileAttachment`, the model details and logging come with it.
@_exported public import LanguageModels

// MARK: - Model

/// A model on a provider whose API speaks OpenAI's Chat Completions or Responses format, for Foundation Models
/// sessions.
///
/// Describe the model and the provider it runs on, and how its requests authenticate, such as with no key for a server
/// on the same Mac:
///
/// ```swift
/// let local = OpenAICompatibleProvider(name: "Local", url: URL(string: "http://localhost:8080/v1")!)
/// let model = OpenAICompatibleLanguageModel(OpenAICompatibleModel("local-model", on: local), auth: .unauthenticated)
/// let session = LanguageModelSession(model: model, instructions: "Plan the week's meals.")
/// ```
///
/// Everything else is Foundation Models: prompts, tools, guided generation, profiles, reasoning levels, attachments and
/// generation options. The provider's ``OpenAICompatibleProvider/format`` decides whether a request goes to
/// `chat/completions` or `responses`, and the provider has the last word on what a model takes: a setting it rejects
/// throws its error.
///
/// Getting started, with a provider described by its name and URL, is in <doc:GettingStarted>.
public struct OpenAICompatibleLanguageModel: DetailedLanguageModel {
    /// What the app says about the model, with the provider it runs on.
    public let details: OpenAICompatibleModel

    /// The models the provider tries when this one fails: none, since a request goes to one model.
    public var fallbacks: [OpenAICompatibleModel] { [] }

    /// Request settings beyond Foundation Models' generation options, such as members of the provider's own.
    public var options: OpenAICompatibleOptions

    /// The URL session that sends requests: `.shared` unless the model was created with another.
    private let session: URLSession

    /// How requests authenticate, and where they go when a server stands in for the provider.
    private let auth: OpenAICompatibleAuthentication

    /// How requests are sent: how long they wait, how they retry, and how their images are encoded. A change applies
    /// to the next request.
    public var configuration: OpenAICompatibleConfiguration

    /// Where requests go, with the provider and the model's ``configuration``, as Foundation Models hands them to the
    /// executor.
    public var executorConfiguration: Executor.Configuration {
        Executor.Configuration(baseURL: auth.baseURL ?? details.provider.url, provider: details.provider, settings: configuration)
    }

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - details: The model and the provider it runs on, such as `OpenAICompatibleModel("my-model", on: gateway)`.
    ///   - options: Request settings beyond Foundation Models' generation options.
    ///   - session: The URL session that sends requests. Its configuration applies, but the package still sets each
    ///     request's headers and, when the configuration's `idleTimeout` is set, its timeout, and follows redirects
    ///     only to the same scheme, URL host and port.
    ///   - configuration: How requests are sent: how long they wait, how they retry, and how their images are encoded.
    ///     `nil` takes the provider's defaults, which for a provider described by its name and URL wait up to 10
    ///     minutes for the next data and retry up to twice. A configuration passed here replaces all of them; to
    ///     change one setting and keep the provider's others, change it on the model's ``configuration``.
    ///   - auth: How requests authenticate: ``OpenAICompatibleAuthentication/apiKey(_:)`` with a key in the provider's
    ///     key header, ``OpenAICompatibleAuthentication/unauthenticated`` for a server that takes none,
    ///     ``OpenAICompatibleAuthentication/proxied(baseURL:headers:)`` to a server of your own, or
    ///     ``OpenAICompatibleAuthentication/proxied(headers:)`` to a gateway described as the provider.
    public init(
        _ details: OpenAICompatibleModel,
        options: OpenAICompatibleOptions = OpenAICompatibleOptions(),
        session: URLSession = .shared,
        configuration: OpenAICompatibleConfiguration? = nil,
        auth: OpenAICompatibleAuthentication
    ) {
        self.details = details
        self.options = options
        self.session = session
        self.auth = auth
        self.configuration = configuration ?? details.provider.configuration
    }
}

// MARK: - Creating a model

/// How a model's requests authenticate, and where they go: with an API key in the provider's key header, with no
/// credentials, or to a server of your own that adds the key and forwards them.
///
/// ```swift
/// // An API key, for development, or a key the person brings, kept in the Keychain:
/// OpenAICompatibleLanguageModel(details, auth: .apiKey { try await keyStore.providerKey() })
///
/// // A server on the same Mac, which takes no key:
/// OpenAICompatibleLanguageModel(localDetails, auth: .unauthenticated)
///
/// // Your own server, which adds the key and forwards each request, so the app ships no key:
/// OpenAICompatibleLanguageModel(
///     details,
///     auth: .proxied(baseURL: proxyURL, headers: { ["X-App-Token": try await account.appToken()] })
/// )
/// ```
///
/// A key inside an app can be extracted from it, so an app that ships uses ``proxied(baseURL:headers:)``, or a key each
/// person brings. Every request also carries the provider's ``OpenAICompatibleProvider/headers``, which a header of the
/// authentication's of the same name replaces. Requests go to the provider's ``OpenAICompatibleProvider/url`` unless
/// they're proxied; ``OpenAICompatibleProvider/at(_:)`` reaches the provider at another address, such as a gateway in
/// front of it.
public struct OpenAICompatibleAuthentication: Sendable {
    /// The server that stands in for the provider's API, from ``proxied(baseURL:headers:)``, or `nil` for the provider's
    /// own URL.
    public var baseURL: URL? {
        switch kind {
        case .unauthenticated, .apiKey: nil
        case .proxied(let baseURL, _): baseURL
        }
    }

    /// What authenticates a request.
    private let kind: Kind

    private enum Kind {
        case unauthenticated
        case apiKey(@Sendable () async throws -> String)
        case proxied(baseURL: URL?, headers: @Sendable () async throws -> [String: String])
    }

    private init(_ kind: Kind) {
        self.kind = kind
    }

    /// No credentials, for a server that takes none, such as one on the same Mac.
    public static let unauthenticated = Self(.unauthenticated)

    /// An API key, sent in the provider's ``OpenAICompatibleProvider/keyHeader``.
    ///
    /// - Parameter key: Returns the key. It's called for every request and never stored. An empty key sends no key
    ///   header.
    /// - Returns: The authentication.
    public static func apiKey(_ key: @escaping @Sendable () async throws -> String) -> Self {
        Self(.apiKey(key))
    }

    /// A server of your own that stands in for the provider's API: it adds the API key and forwards each request, so
    /// the app ships no key.
    ///
    /// Requests go to the same paths under `baseURL` as under the provider's URL, such as `chat/completions`, and follow
    /// redirects only to the same scheme, URL host and port.
    ///
    /// - Parameters:
    ///   - baseURL: The server's URL, which stands in for the provider's ``OpenAICompatibleProvider/url``.
    ///   - headers: Returns the headers that let the server authorize the caller, such as a token of your app's own.
    ///     It's called for every request, so a token can refresh. Return `[:]` when the server needs none.
    /// - Returns: The authentication.
    public static func proxied(
        baseURL: URL,
        headers: @escaping @Sendable () async throws -> [String: String] = { [:] }
    ) -> Self {
        Self(.proxied(baseURL: baseURL, headers: headers))
    }

    /// Headers that let the provider's own URL authorize the caller, such as a token of your app's own for a gateway
    /// you describe as the provider.
    ///
    /// - Parameter headers: Returns the headers. It's called for every request, so a token can refresh.
    /// - Returns: The authentication.
    public static func proxied(headers: @escaping @Sendable () async throws -> [String: String]) -> Self {
        Self(.proxied(baseURL: nil, headers: headers))
    }

    /// How a request to a provider authenticates: the provider's fixed headers, with the key's or the server's of the
    /// same name, whatever its case, in their place.
    func requestAuthentication(for provider: OpenAICompatibleProvider) -> Connection.Authentication {
        let fixed = provider.headers
        switch kind {
        case .unauthenticated:
            return Connection.Authentication(baseURL: nil) { fixed }
        case .apiKey(let key):
            let keyHeader = provider.keyHeader
            return Connection.Authentication(baseURL: nil) {
                let key = try await key()
                return Self.headers(fixed, replacedBy: key.isEmpty ? [:] : keyHeader.header(for: key))
            }
        case .proxied(let baseURL, let headers):
            return Connection.Authentication(baseURL: baseURL) { Self.headers(fixed, replacedBy: try await headers()) }
        }
    }

    /// Fixed headers with the authentication's in place of those of the same name, whatever its case.
    private static func headers(_ fixed: [String: String], replacedBy authentication: [String: String]) -> [String: String] {
        let names = Set(authentication.keys.map { $0.lowercased() })
        return fixed.filter { !names.contains($0.key.lowercased()) }.merging(authentication) { $1 }
    }
}

// MARK: - Settings

/// How a model's requests are sent: how long they wait, how they retry, and how their images are encoded.
///
/// Options, such as ``OpenAICompatibleOptions``, are what a request asks the provider for. The configuration is how the
/// package sends the request, so the provider never sees it. A model created without one takes the provider's
/// defaults; change one setting on the model, and it keeps the others:
///
/// ```swift
/// // Fail fast on an interactive screen.
/// var model = OpenAICompatibleLanguageModel(details, auth: .apiKey { try await keyStore.providerKey() })
/// model.configuration.idleTimeout = .seconds(60)
/// model.configuration.retries = RequestRetries(limit: 1)
/// ```
public struct OpenAICompatibleConfiguration: Sendable, Hashable {
    /// The longest time to wait for the next data, from sending the request to the end of the answer, or `nil` for
    /// the URL session's own timeout.
    public var idleTimeout: Duration?

    /// How a request that fails before any data arrives is sent again: after a failed connection, a failed response
    /// whose status the provider retries, which for a provider described by its name and URL is a 408, 409 or 429 or
    /// any status from 500 up, or any status whose `x-should-retry` is `true`, but never when it's `false`. xAI's
    /// preset sends a request again only after a 429 or an `x-should-retry` of `true`.
    public var retries: RequestRetries

    /// How image attachments are encoded before they're sent.
    public var images: ImageEncoding

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - idleTimeout: The longest time to wait for the next data, or `nil` for the URL session's own timeout. The
    ///     default is 10 minutes, since a server loading a model, or a model that reasons hard, may send nothing for a
    ///     while.
    ///   - retries: How a failed request is sent again. The default retries up to twice.
    ///   - images: How image attachments are encoded.
    public init(idleTimeout: Duration? = .seconds(600), retries: RequestRetries = .standard, images: ImageEncoding = .standard) {
        self.idleTimeout = idleTimeout
        self.retries = retries
        self.images = images
    }
}

// MARK: - Executor

extension OpenAICompatibleLanguageModel {
    /// Sends a model's requests to its provider and streams each answer into Foundation Models.
    ///
    /// Foundation Models creates it from the model's `executorConfiguration` and calls it for each answer. It keeps no
    /// state between answers.
    public struct Executor: LanguageModelExecutor {
        /// The model the executor sends requests for.
        public typealias Model = OpenAICompatibleLanguageModel

        /// Where the executor sends requests, with the provider and the model's ``OpenAICompatibleConfiguration``. It
        /// holds none of the authentication's credentials, only the provider's fixed ``OpenAICompatibleProvider/headers``,
        /// which are no place for a key.
        ///
        /// The model makes it from its provider, its authentication's base URL and its configuration, so an app sets
        /// ``OpenAICompatibleLanguageModel/configuration`` rather than this.
        public struct Configuration: Sendable, Hashable {
            /// Where requests go: the provider's URL, or the server that stands in for it.
            let baseURL: URL

            /// The provider, whose format the requests use.
            let provider: OpenAICompatibleProvider

            /// How the model's requests are sent.
            let settings: OpenAICompatibleConfiguration
        }

        /// Where requests go and how they're sent, which the model reads as the shared model of the provider's format.
        private let configuration: Configuration

        /// Creates an executor.
        ///
        /// - Parameter configuration: Where to send requests.
        public init(configuration: Configuration) {
            self.configuration = configuration
        }

        /// Sends one request and streams its answer, in the provider's format.
        ///
        /// A failed request is sent again as ``OpenAICompatibleConfiguration/retries`` says, only before any data
        /// arrives: after a failed connection, a failed response whose status the provider retries, which for a
        /// provider described by its name and URL is a 408, 409 or 429 or any status from 500 up, or any status whose
        /// `x-should-retry` is `true`, and to xAI only after a 429 or an `x-should-retry` of `true`, unless its
        /// `x-should-retry` is `false` or its `retry-after-ms` or `Retry-After` asks for a longer wait than
        /// ``RequestRetries/longestServerWait``. A request whose schema has a constraint the provider rejects is sent
        /// once more with the portable schema, which carries its constraints in descriptions.
        ///
        /// The answer is checked against the schema's guides last, as ``DetailedLanguageModel/checkGuides(ofResponseText:for:)``
        /// does, since a provider may ignore a guide.
        ///
        /// - Parameters:
        ///   - request: The transcript, tools, schema and options to send.
        ///   - model: The model to answer with.
        ///   - channel: Where the answer's events go.
        /// - Throws: `LanguageModelError` for failures Foundation Models has a case for, and for a request the provider
        ///   is known to refuse, before it's sent; `OpenAICompatibleError` for the rest; `GeneratedContent.ParsingError`
        ///   when a value of the answer breaks a guide of the request's schema, an object or array answer isn't complete
        ///   JSON, a guided answer reaches its token limit or the provider says it broke its schema; the `URLError` of a
        ///   failed connection; and `CancellationError` when the task is cancelled. An error that the model's
        ///   authentication throws passes through as it is, unless it's a `URLError`, which maps as a failed
        ///   connection's does.
        public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: OpenAICompatibleLanguageModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            switch configuration.provider.format {
            case .chatCompletions: try await model.chatCompletions(configuration).respond(to: request, streamingInto: channel)
            case .responses: try await model.responses(configuration).respond(to: request, streamingInto: channel)
            }
        }
    }
}

extension OpenAICompatibleLanguageModel {
    /// How the model's requests reach the provider: its session and authentication, with the timeout and retries of its
    /// configuration, retrying the statuses the provider retries.
    func connection(_ configuration: Executor.Configuration) -> Connection {
        Connection(
            session: session, authentication: auth.requestAuthentication(for: configuration.provider),
            idleTimeout: configuration.settings.idleTimeout, retries: configuration.settings.retries,
            retrying: configuration.provider.retriedStatuses)
    }
}
