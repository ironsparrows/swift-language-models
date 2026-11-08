public import Foundation
public import FoundationModels
// Re-exports `LanguageModels`, and through it the core every provider shares, so `import OpenAILanguageModels` is all an
// app needs: typed reasoning efforts, `FileAttachment`, the model details and logging come with it.
@_exported public import LanguageModels

#if canImport(FoundationModels, _version: 2.1.14)
public import UniformTypeIdentifiers
#endif

// MARK: - Model

/// One of OpenAI's models, for Foundation Models sessions, through OpenAI's Responses API.
///
/// Pass a model from the catalog, and how its requests authenticate, such as with an API key read on every request:
///
/// ```swift
/// let model = OpenAILanguageModel(.gpt6Luna, auth: .apiKey { try await keyStore.openAIKey() })
/// let session = LanguageModelSession(model: model, instructions: "Plan the week's meals.")
/// ```
///
/// Everything else is Foundation Models: prompts, tools, guided generation, profiles, reasoning levels, attachments and
/// generation options. A request sends a per-model setting, such as `temperature` or `tools`, only to a model that
/// takes it, and a debug build shows a runtime warning in Xcode for each setting left out.
///
/// What only OpenAI has is in the articles: authentication in <doc:GettingStarted> and <doc:Authentication>, then
/// <doc:ServerTools>, <doc:Reasoning>, <doc:Caching>, <doc:Attachments> and <doc:ErrorsAndMetadata>.
public struct OpenAILanguageModel<Effort: ModelEffort>: DetailedLanguageModel {
    /// What the catalog records about the model.
    public let details: OpenAIModel<Effort>

    /// The models OpenAI tries when this one fails: none, since OpenAI has no fallbacks.
    public var fallbacks: [OpenAIModel<ContextOptions.ReasoningLevel>] { [] }

    /// Tools that OpenAI runs for the model while it answers, such as a web search, listed after the session's own
    /// tools in each request.
    ///
    /// A request that disallows tool calls sends none of them. One that sends them to a model that doesn't list `tools`
    /// throws `LanguageModelError.unsupportedCapability` before it's sent.
    public var serverTools: [OpenAIServerTool]

    /// Request settings that only OpenAI has.
    public var options: OpenAIOptions

    /// The URL session that sends requests: `.shared` unless the model was created with another.
    private let session: URLSession

    /// How requests authenticate, and where they go.
    private let auth: OpenAIAuthentication

    /// How requests are sent: how long they wait, how they retry, and how their images are encoded. A change applies
    /// to the next request.
    public var configuration: OpenAIConfiguration

    /// Where requests go, with the model's ``configuration``, as Foundation Models hands them to the executor.
    public var executorConfiguration: Executor.Configuration {
        Executor.Configuration(baseURL: auth.baseURL, settings: configuration)
    }

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - details: The model, usually from the catalog, such as `.gpt6Luna`.
    ///   - serverTools: Tools that OpenAI runs for the model while it answers, such as `.webSearch()`.
    ///   - options: Request settings that only OpenAI has.
    ///   - session: The URL session that sends requests. Its configuration applies, but the package still sets each
    ///     request's headers and, when the configuration's `idleTimeout` is set, its timeout, and follows redirects
    ///     only to the same scheme, URL host and port.
    ///   - configuration: How requests are sent: how long they wait, how they retry, and how their images are encoded.
    ///   - auth: How requests authenticate, and where they go: ``OpenAIAuthentication/apiKey(organization:project:_:)``
    ///     to OpenAI, ``OpenAIAuthentication/apiKey(baseURL:organization:project:_:)`` to another server that speaks
    ///     its API, or ``OpenAIAuthentication/proxied(baseURL:headers:)`` to a server of your own.
    public init(
        _ details: OpenAIModel<Effort>,
        serverTools: [OpenAIServerTool] = [],
        options: OpenAIOptions = OpenAIOptions(),
        session: URLSession = .shared,
        configuration: OpenAIConfiguration = OpenAIConfiguration(),
        auth: OpenAIAuthentication
    ) {
        self.init(
            details: details, serverTools: serverTools, options: options, session: session, auth: auth, configuration: configuration)
    }

    init(
        details: OpenAIModel<Effort>,
        serverTools: [OpenAIServerTool],
        options: OpenAIOptions,
        session: URLSession,
        auth: OpenAIAuthentication,
        configuration: OpenAIConfiguration
    ) {
        self.details = details
        self.serverTools = serverTools
        self.options = options
        self.session = session
        self.auth = auth
        self.configuration = configuration
    }
}

// MARK: - Creating a model

extension OpenAILanguageModel where Effort == ContextOptions.ReasoningLevel {
    /// The same model with its efforts in their open form, so models with different effort types fit in one list.
    ///
    /// - Parameter typed: A model created from the catalog.
    public init(_ typed: OpenAILanguageModel<some ModelEffort>) {
        self.init(
            details: OpenAIModel(typed.details),
            serverTools: typed.serverTools,
            options: typed.options,
            session: typed.session,
            auth: typed.auth,
            configuration: typed.configuration
        )
    }
}

/// How a model's requests authenticate, and where they go: to OpenAI with an API key, with a key to another server that
/// speaks OpenAI's API, or to a server of your own that adds the key and forwards them.
///
/// ```swift
/// // An API key, for development, or a key the person brings, kept in the Keychain:
/// OpenAILanguageModel(.gpt6Luna, auth: .apiKey { try await keyStore.openAIKey() })
///
/// // Your own server, which adds the key and forwards each request to OpenAI, so the app ships no key:
/// OpenAILanguageModel(
///     .gpt6Luna,
///     auth: .proxied(baseURL: proxyURL, headers: { ["X-App-Token": try await account.appToken()] })
/// )
/// ```
///
/// A key inside an app can be extracted from it, so an app that ships uses ``proxied(baseURL:headers:)``, or a key each
/// person brings.
public struct OpenAIAuthentication: Sendable {
    /// The server that stands in for OpenAI's API, from ``apiKey(baseURL:organization:project:_:)`` or
    /// ``proxied(baseURL:headers:)``, or `nil` for OpenAI's API itself.
    public var baseURL: URL? { requestAuthentication.baseURL }

    /// The headers that authenticate a request, read for every request, and where it goes, as a request's connection
    /// holds them.
    fileprivate let requestAuthentication: Connection.Authentication

    private init(_ requestAuthentication: Connection.Authentication) {
        self.requestAuthentication = requestAuthentication
    }

    /// Authentication with these headers, sent to a base URL, such as a server of your own.
    private init(baseURL: URL?, headers: @escaping @Sendable () async throws -> [String: String]) {
        self.init(Connection.Authentication(baseURL: baseURL, headers: headers))
    }

    /// An OpenAI API key, sent to OpenAI as a bearer token.
    ///
    /// - Parameters:
    ///   - organization: The organization the requests count toward, sent as `OpenAI-Organization`, or `nil` for the
    ///     key's default.
    ///   - project: The project the requests count toward, sent as `OpenAI-Project`, or `nil` for the key's default.
    ///   - key: Returns the key. It's called for every request and never stored. An empty key sends no
    ///     `Authorization` header, and no `OpenAI-Organization` or `OpenAI-Project`.
    /// - Returns: The authentication.
    public static func apiKey(
        organization: String? = nil,
        project: String? = nil,
        _ key: @escaping @Sendable () async throws -> String
    ) -> Self {
        Self(apiKey: key, baseURL: nil, organization: organization, project: project)
    }

    /// An OpenAI API key, sent as a bearer token to another server that speaks OpenAI's API, such as a gateway of your
    /// company's or a test server.
    ///
    /// Requests go to the same paths under `baseURL` as under OpenAI's API, such as `responses`, and follow redirects
    /// only to the same scheme, URL host and port. To keep the key out of the app, use ``proxied(baseURL:headers:)``
    /// instead.
    ///
    /// - Parameters:
    ///   - baseURL: The server's URL, which stands in for `https://api.openai.com/v1/`.
    ///   - organization: The organization the requests count toward, sent as `OpenAI-Organization`, or `nil` for the
    ///     key's default.
    ///   - project: The project the requests count toward, sent as `OpenAI-Project`, or `nil` for the key's default.
    ///   - key: Returns the key. It's called for every request and never stored. An empty key sends no
    ///     `Authorization` header, and no `OpenAI-Organization` or `OpenAI-Project`.
    /// - Returns: The authentication.
    public static func apiKey(
        baseURL: URL,
        organization: String? = nil,
        project: String? = nil,
        _ key: @escaping @Sendable () async throws -> String
    ) -> Self {
        Self(apiKey: key, baseURL: baseURL, organization: organization, project: project)
    }

    /// A server of your own that stands in for OpenAI's API: it adds the API key and forwards each request, so the app
    /// ships no key.
    ///
    /// Requests go to the same paths under `baseURL` as under OpenAI's API, such as `responses`, and follow redirects
    /// only to the same scheme, URL host and port.
    ///
    /// - Parameters:
    ///   - baseURL: The server's URL, which stands in for `https://api.openai.com/v1/`.
    ///   - headers: Returns the headers that let the server authorize the caller, such as a token of your app's own.
    ///     It's called for every request, so a token can refresh. Return `[:]` when the server needs none.
    /// - Returns: The authentication.
    public static func proxied(
        baseURL: URL,
        headers: @escaping @Sendable () async throws -> [String: String] = { [:] }
    ) -> Self {
        Self(baseURL: baseURL, headers: headers)
    }

    /// An API key sent as a bearer token to OpenAI's API, or to the base URL that stands in for it, with the
    /// organization and project when set.
    private init(apiKey key: @escaping @Sendable () async throws -> String, baseURL: URL?, organization: String?, project: String?) {
        self.init(
            .apiKey(key, baseURL: baseURL) { key in
                var headers = Connection.Authentication.bearerHeader(key)
                headers[API.Header.organization] = organization
                headers[API.Header.project] = project
                return headers
            })
    }
}

// MARK: - Details and capabilities

// FoundationModels 2.1.14 comes with Xcode 27.2, the first SDK with data attachments and data entries.
#if canImport(FoundationModels, _version: 2.1.14)
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
extension OpenAILanguageModel {
    /// Whether the model accepts the kind of data as a prompt attachment.
    ///
    /// - Parameter type: The kind of data, such as `UTType.pdf`.
    /// - Returns: Whether the kind conforms to an attachment kind the model accepts.
    /// - Throws: Nothing; the method throws only because Foundation Models declares it so.
    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        details.supportsDataAttachmentType(type)
    }

    /// Whether the model generates the kind of data: an image in the format of its image generation tool, PNG unless
    /// the tool asks for another, and nothing else, since the catalog lists only models that answer in text.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the model generates the kind.
    /// - Throws: Nothing; the method throws only because Foundation Models declares it so.
    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        details.supportsDataEntryType(type)
            || serverTools.contains { tool in tool.entry.generatedFormat.map { type.conforms(to: $0.contentType) } ?? false }
    }
}
#endif

// MARK: - Settings

/// How an OpenAI model's requests are sent: how long they wait, how they retry, and how their images are encoded.
///
/// Options, such as ``OpenAIOptions``, are what a request asks OpenAI for. The configuration is how the package sends
/// the request, so OpenAI never sees it. Set it when creating the model, or change it later:
///
/// ```swift
/// // Fail fast on an interactive screen.
/// let model = OpenAILanguageModel(
///     .gpt6Luna,
///     configuration: OpenAIConfiguration(idleTimeout: .seconds(60), retries: RequestRetries(limit: 1)),
///     auth: .apiKey { try await keyStore.openAIKey() }
/// )
///
/// // Smaller images, for fewer input tokens.
/// var batch = model
/// batch.configuration.images.maximumSide = 1_024
/// ```
public struct OpenAIConfiguration: Sendable, Hashable {
    /// The longest time to wait for the next data, from sending the request to the end of the answer, or `nil` for
    /// the URL session's own timeout.
    public var idleTimeout: Duration?

    /// How a request that fails before any data arrives is sent again: after a failed connection, a 408, 409 or 429,
    /// any status from 500 up, or any status whose `x-should-retry` is `true`, but never when it's `false`.
    public var retries: RequestRetries

    /// How image attachments are encoded before they're sent.
    public var images: ImageEncoding

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - idleTimeout: The longest time to wait for the next data, or `nil` for the URL session's own timeout. The
    ///     default is 10 minutes, since a model that reasons hard may send nothing for a while.
    ///   - retries: How a failed request is sent again. The default retries up to twice.
    ///   - images: How image attachments are encoded.
    public init(idleTimeout: Duration? = .seconds(600), retries: RequestRetries = .standard, images: ImageEncoding = .standard) {
        self.idleTimeout = idleTimeout
        self.retries = retries
        self.images = images
    }
}

// MARK: - Executor

extension OpenAILanguageModel {
    /// Sends a model's requests to OpenAI and streams each answer into Foundation Models.
    ///
    /// Foundation Models creates it from the model's `executorConfiguration` and calls it for each answer. It keeps no
    /// state between answers.
    public struct Executor: LanguageModelExecutor {
        /// The model the executor sends requests for.
        public typealias Model = OpenAILanguageModel

        /// Where the executor sends requests, with the model's ``OpenAIConfiguration``. It holds no secrets.
        ///
        /// The model makes it from its authentication's base URL and its configuration, so an app sets
        /// ``OpenAILanguageModel/configuration`` rather than this.
        public struct Configuration: Sendable, Hashable {
            /// The server that stands in for OpenAI's API, or `nil` for OpenAI's API itself.
            let baseURL: URL?

            /// How the model's requests are sent.
            let settings: OpenAIConfiguration
        }

        /// Where requests go and how they're sent, which the model reads as a Responses model.
        private let configuration: Configuration

        /// Creates an executor.
        ///
        /// - Parameter configuration: Where to send requests.
        public init(configuration: Configuration) {
            self.configuration = configuration
        }

        /// Sends one request and streams its answer.
        ///
        /// A failed request is sent again as ``OpenAIConfiguration/retries`` says, only before any data arrives: after
        /// a failed connection, a 408, 409 or 429, any status from 500 up, or any status whose `x-should-retry` is
        /// `true`, unless its `x-should-retry` is `false` or its `retry-after-ms` or `Retry-After` asks for a longer
        /// wait than ``RequestRetries/longestServerWait``. A request whose schema has a constraint OpenAI rejects is
        /// sent once more with the portable schema, which carries its constraints in descriptions.
        ///
        /// A model the request may reach that OpenAI stopped listing is reported first, and the answer is checked against
        /// the schema's guides last, as ``DetailedLanguageModel/reportRemovedModels(for:)`` and
        /// ``DetailedLanguageModel/checkGuides(ofResponseText:for:)`` do.
        ///
        /// - Parameters:
        ///   - request: The transcript, tools, schema and options to send.
        ///   - model: The model to answer with.
        ///   - channel: Where the answer's events go.
        /// - Throws: `LanguageModelError` for failures Foundation Models has a case for, `OpenAIError` for the rest,
        ///   `GeneratedContent.ParsingError` when a value of the answer breaks a guide of the request's schema, an object
        ///   or array answer isn't complete JSON or a guided answer reaches its token limit, the `URLError` of a failed
        ///   connection, and `CancellationError` when the task is cancelled. An error that the model's authentication
        ///   throws passes through as it is, unless it's a `URLError`, which maps as a failed connection's does.
        public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: OpenAILanguageModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            try await model.responses(configuration).respond(to: request, streamingInto: channel)
        }
    }
}

extension OpenAILanguageModel {
    /// How the model's requests reach OpenAI: its session and authentication, with the timeout and retries of its
    /// configuration, retrying a 408, 409 or 429 and any status from 500 up.
    func connection(_ configuration: OpenAIConfiguration) -> Connection {
        Connection(
            session: session, authentication: auth.requestAuthentication, idleTimeout: configuration.idleTimeout,
            retries: configuration.retries, retrying: .transient)
    }
}
