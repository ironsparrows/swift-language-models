public import Foundation
public import FoundationModels
// Re-exports `LanguageModels`, and through it the core every provider shares, so `import OpenRouterLanguageModels` is all an
// app needs: typed reasoning efforts, `FileAttachment`, the model details and logging come with it.
@_exported public import LanguageModels
#if canImport(FoundationModels, _version: 2.1.14)
public import UniformTypeIdentifiers
#endif

// MARK: - Model

/// A model on OpenRouter, for Foundation Models sessions.
///
/// Pass a model from the catalog, and how its requests authenticate, such as with an API key read on every request:
///
/// ```swift
/// let model = OpenRouterLanguageModel(.anthropicClaudeSonnet4_6, auth: .apiKey { try await keyStore.openRouterKey() })
/// let session = LanguageModelSession(model: model, instructions: "Plan the week's meals.")
/// ```
///
/// Everything else is Foundation Models: prompts, tools, guided generation, profiles, reasoning levels, attachments
/// and generation options. A request sends only the settings that the model and each of its ``fallbacks`` list, so a
/// host never rejects one, and a debug build shows a runtime warning in Xcode for each setting left out.
///
/// What only OpenRouter has is in the articles: authentication and the app's name in <doc:GettingStarted>, fallback
/// models and hosts in <doc:RoutingAndFallbacks>, and then <doc:ServerTools>, <doc:Caching>, <doc:Attachments> and
/// <doc:ErrorsAndMetadata>.
public struct OpenRouterLanguageModel<Effort: ModelEffort>: DetailedLanguageModel {
    /// What OpenRouter reports about the model, the first one a request tries.
    public let details: OpenRouterModel<Effort>

    /// The models to try in order when the model fails, with their efforts in their open form.
    ///
    /// A request lists them after the model, and OpenRouter moves on to the next one on any error. Set them on the
    /// model's initializer to list catalog models of any effort type, or here for models picked at runtime.
    public var fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>]

    /// Tools that OpenRouter runs for the model while it answers, such as a web search, next to the session's own
    /// tools.
    ///
    /// A request sends them unless its generation options disallow tool calls, and throws
    /// `LanguageModelError.unsupportedCapability` before sending anything when the model or a fallback doesn't take
    /// tools.
    public var serverTools: [OpenRouterServerTool]

    /// Which of the model's hosts OpenRouter may use.
    public var routing: OpenRouterRouting

    /// Request settings that only OpenRouter has.
    public var options: OpenRouterOptions

    /// How requests mark prompts for caching: ``OpenRouterCacheControl/automatic`` unless the model was created with
    /// another, or `nil` to send no marks.
    public var cacheControl: OpenRouterCacheControl?

    /// OpenRouter's response cache, which answers a repeated request with its earlier answer at no cost, or `nil` to
    /// leave it off.
    public var responseCache: OpenRouterResponseCache?

    /// The URL session that sends requests: `.shared` unless the model was created with another.
    let session: URLSession

    /// How requests authenticate, and where they go.
    let auth: OpenRouterAuthentication

    /// How requests name the app to OpenRouter.
    public let app: OpenRouterApp

    /// How requests are sent: how long they wait, how they retry, how their images are encoded, and how long model
    /// info stays fresh. A change applies to the next request.
    public var configuration: OpenRouterConfiguration

    /// Where requests go and how they name the app, with the model's ``configuration``, as Foundation Models hands
    /// them to the executor.
    public var executorConfiguration: Executor.Configuration {
        Executor.Configuration(baseURL: auth.baseURL, app: app, settings: configuration)
    }

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - details: The model, usually from the catalog, such as `.anthropicClaudeSonnet4_6`.
    ///   - fallbacks: The models to try in order when the model fails, such as
    ///     `.openaiGpt5Nano, .googleGemini3_1FlashLite`. Each can have its own effort type.
    ///   - serverTools: Tools that OpenRouter runs for the model while it answers, such as `.webSearch()`.
    ///   - routing: Which of the model's hosts OpenRouter may use.
    ///   - options: Request settings that only OpenRouter has.
    ///   - cacheControl: How requests mark prompts for caching, or `nil` to send no marks. The default marks them only
    ///     when every model a request may reach caches only marked prompts, such as Claude.
    ///   - responseCache: OpenRouter's response cache, which answers a repeated request with its earlier answer at no
    ///     cost, or `nil` to leave it off.
    ///   - app: How requests name the app to OpenRouter, which credits the app's usage in its rankings.
    ///   - session: The URL session that sends requests. Its configuration applies, but the package still sets each
    ///     request's headers, its timeout when the configuration's `idleTimeout` is set, and redirects only to the
    ///     same host.
    ///   - configuration: How requests are sent: how long they wait, how they retry, how their images are encoded, and
    ///     how long model info stays fresh.
    ///   - auth: How requests authenticate, and where they go: ``OpenRouterAuthentication/apiKey(_:)`` to OpenRouter,
    ///     ``OpenRouterAuthentication/apiKey(baseURL:_:)`` to another server that speaks its API, or
    ///     ``OpenRouterAuthentication/proxied(baseURL:headers:)`` to a server of your own.
    public init<each FallbackEffort: ModelEffort>(
        _ details: OpenRouterModel<Effort>,
        fallbacks: repeat OpenRouterModel<each FallbackEffort>,
        serverTools: [OpenRouterServerTool] = [],
        routing: OpenRouterRouting = OpenRouterRouting(),
        options: OpenRouterOptions = OpenRouterOptions(),
        cacheControl: OpenRouterCacheControl? = .automatic,
        responseCache: OpenRouterResponseCache? = nil,
        app: OpenRouterApp = OpenRouterApp(),
        session: URLSession = .shared,
        configuration: OpenRouterConfiguration = OpenRouterConfiguration(),
        auth: OpenRouterAuthentication
    ) {
        var bridgedFallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>] = []
        for fallback in repeat each fallbacks {
            bridgedFallbacks.append(OpenRouterModel(fallback))
        }
        self.init(
            details: details,
            fallbacks: bridgedFallbacks,
            serverTools: serverTools,
            routing: routing,
            options: options,
            cacheControl: cacheControl,
            responseCache: responseCache,
            app: app,
            session: session,
            auth: auth,
            configuration: configuration
        )
    }

    init(
        details: OpenRouterModel<Effort>,
        fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>],
        serverTools: [OpenRouterServerTool],
        routing: OpenRouterRouting,
        options: OpenRouterOptions,
        cacheControl: OpenRouterCacheControl?,
        responseCache: OpenRouterResponseCache?,
        app: OpenRouterApp,
        session: URLSession,
        auth: OpenRouterAuthentication,
        configuration: OpenRouterConfiguration
    ) {
        self.details = details
        self.fallbacks = fallbacks
        self.serverTools = serverTools
        self.routing = routing
        self.options = options
        self.cacheControl = cacheControl
        self.responseCache = responseCache
        self.app = app
        self.session = session
        self.auth = auth
        self.configuration = configuration
    }
}

// MARK: - Creating a model

extension OpenRouterLanguageModel where Effort == ContextOptions.ReasoningLevel {
    /// The same model with its efforts in their open form, so models with different effort types fit in one list.
    ///
    /// - Parameter typed: A model created from the catalog.
    public init(_ typed: OpenRouterLanguageModel<some ModelEffort>) {
        self.init(
            details: OpenRouterModel(typed.details),
            fallbacks: typed.fallbacks,
            serverTools: typed.serverTools,
            routing: typed.routing,
            options: typed.options,
            cacheControl: typed.cacheControl,
            responseCache: typed.responseCache,
            app: typed.app,
            session: typed.session,
            auth: typed.auth,
            configuration: typed.configuration
        )
    }
}

/// How a model's requests authenticate, and where they go: to OpenRouter with an API key, with a key to another server
/// that speaks OpenRouter's API, or to a server of your own that adds the key and forwards them.
///
/// ```swift
/// // An API key, for development, or a key the person brings, kept in the Keychain:
/// OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey { try await keyStore.openRouterKey() })
///
/// // Your own server, which adds the key and forwards each request to OpenRouter, so the app ships no key:
/// OpenRouterLanguageModel(
///     .anthropicClaudeHaiku5_5,
///     auth: .proxied(baseURL: proxyURL, headers: { ["X-App-Token": try await account.appToken()] })
/// )
/// ```
///
/// A key inside an app can be extracted from it, so an app that ships uses ``proxied(baseURL:headers:)``, or a key
/// each person brings.
public struct OpenRouterAuthentication: Sendable {
    /// The server that stands in for OpenRouter's API, from ``apiKey(baseURL:_:)`` or ``proxied(baseURL:headers:)``, or
    /// `nil` for OpenRouter's API itself.
    public var baseURL: URL? { requestAuthentication.baseURL }

    /// The headers that authenticate a request, read for every request, and where it goes, as a request's connection
    /// holds them.
    fileprivate let requestAuthentication: Connection.Authentication

    private init(_ requestAuthentication: Connection.Authentication) {
        self.requestAuthentication = requestAuthentication
    }

    /// Authentication with these headers, sent to a base URL, such as a test server's.
    private init(baseURL: URL?, headers: @escaping @Sendable () async throws -> [String: String]) {
        self.init(Connection.Authentication(baseURL: baseURL, headers: headers))
    }

    /// An OpenRouter API key, sent to OpenRouter as a bearer token.
    ///
    /// - Parameter key: Returns the key. It's called for every request and never stored. An empty key sends no
    ///   `Authorization` header.
    /// - Returns: The authentication.
    public static func apiKey(_ key: @escaping @Sendable () async throws -> String) -> Self {
        Self(apiKey: key, baseURL: nil)
    }

    /// An OpenRouter API key, sent as a bearer token to another server that speaks OpenRouter's API, such as a gateway
    /// of your company's or a test server.
    ///
    /// Requests go to the same paths under `baseURL` as under OpenRouter's API, such as `chat/completions`, and follow
    /// redirects only to the same host. Model info calls, such as `endpoints()`, go there too. To keep the key out of
    /// the app, use ``proxied(baseURL:headers:)`` instead.
    ///
    /// - Parameters:
    ///   - baseURL: The server's URL, which stands in for `https://openrouter.ai/api/v1/`.
    ///   - key: Returns the key. It's called for every request and never stored. An empty key sends no
    ///     `Authorization` header.
    /// - Returns: The authentication.
    public static func apiKey(baseURL: URL, _ key: @escaping @Sendable () async throws -> String) -> Self {
        Self(apiKey: key, baseURL: baseURL)
    }

    /// A server of your own that stands in for OpenRouter's API: it adds the API key and forwards each request, so the
    /// app ships no key.
    ///
    /// Requests go to the same paths under `baseURL` as under OpenRouter's API, such as `chat/completions`, and follow
    /// redirects only to the same host. Model info calls, such as `endpoints()`, go there too.
    ///
    /// - Parameters:
    ///   - baseURL: The server's URL, which stands in for `https://openrouter.ai/api/v1/`.
    ///   - headers: Returns the headers that let the server authorize the caller, such as a token of your app's own.
    ///     It's called for every request, so a token can refresh. Return `[:]` when the server needs none.
    /// - Returns: The authentication.
    public static func proxied(
        baseURL: URL,
        headers: @escaping @Sendable () async throws -> [String: String] = { [:] }
    ) -> Self {
        Self(baseURL: baseURL, headers: headers)
    }

    /// An API key sent as a bearer token to OpenRouter's API, or to the base URL that stands in for it.
    private init(apiKey key: @escaping @Sendable () async throws -> String, baseURL: URL?) {
        self.init(.apiKey(key, baseURL: baseURL, header: Connection.Authentication.bearerHeader))
    }
}

/// How requests name the app to OpenRouter, which credits the app's usage in its rankings and app marketplace.
///
/// Each setting goes in a header of every request, and one left unset sends nothing:
///
/// ```swift
/// let model = OpenRouterLanguageModel(
///     .openaiGpt5Mini,
///     app: OpenRouterApp(name: "Trip Planner", url: URL(string: "https://example.com"), categories: [.personalAgent]),
///     auth: .apiKey { try await keyStore.openRouterKey() }
/// )
/// ```
public struct OpenRouterApp: Sendable, Hashable {
    /// The most categories OpenRouter takes on one request.
    static let categoryLimit = 2

    /// The app's name, shown in OpenRouter's rankings.
    public var name: String?

    /// The app's website, which OpenRouter's rankings link to, and which names the app OpenRouter creates for it.
    public var url: URL?

    /// Up to two of OpenRouter's marketplace categories for the app, such as `.cliAgent`. Any after the second are left
    /// out.
    public var categories: [OpenRouterApp.Category]

    /// Whether the app OpenRouter creates for ``url`` stays out of its public rankings and marketplace, while its usage
    /// still shows in the account's analytics.
    ///
    /// It applies only to the request that creates the app, so it can't hide or show an app that already exists.
    public var isHidden: Bool

    /// Creates the settings that name the app.
    ///
    /// - Parameters:
    ///   - name: The app's name, shown in OpenRouter's rankings.
    ///   - url: The app's website, which OpenRouter's rankings link to.
    ///   - categories: Up to two of OpenRouter's marketplace categories for the app, such as `.cliAgent`.
    ///   - isHidden: Whether the app OpenRouter creates for `url` stays out of its public rankings and marketplace.
    public init(name: String? = nil, url: URL? = nil, categories: [OpenRouterApp.Category] = [], isHidden: Bool = false) {
        self.name = name
        self.url = url
        self.categories = categories
        self.isHidden = isHidden
    }
}

extension OpenRouterApp {
    /// A category of OpenRouter's app marketplace, such as `cli-agent` or `general-chat`.
    ///
    /// OpenRouter takes only the categories it lists, and drops any other without an error.
    public struct Category: ProviderVocabulary {
        /// A coding assistant that runs in the terminal.
        public static let cliAgent: Self = "cli-agent"

        /// An editor or IDE integration.
        public static let ideExtension: Self = "ide-extension"

        /// A coding agent that runs in the cloud.
        public static let cloudAgent: Self = "cloud-agent"

        /// A programming app.
        public static let programmingApp: Self = "programming-app"

        /// A builder of mobile and desktop apps.
        public static let nativeAppBuilder: Self = "native-app-builder"

        /// A creative writing tool.
        public static let creativeWriting: Self = "creative-writing"

        /// An app that generates video.
        public static let videoGeneration: Self = "video-gen"

        /// An app that generates images.
        public static let imageGeneration: Self = "image-gen"

        /// An app that generates audio.
        public static let audioGeneration: Self = "audio-gen"

        /// A writing assistant.
        public static let writingAssistant: Self = "writing-assistant"

        /// A general chat app.
        public static let generalChat: Self = "general-chat"

        /// A personal agent.
        public static let personalAgent: Self = "personal-agent"

        /// A legal tool or assistant.
        public static let legal: Self = "legal"

        /// A roleplay app, or another app for chatting with characters.
        public static let roleplay: Self = "roleplay"

        /// A game or other interactive entertainment.
        public static let game: Self = "game"

        /// The category's name in OpenRouter's API.
        public let rawValue: String

        /// Creates a category from its name in OpenRouter's API.
        ///
        /// - Parameter rawValue: The name, such as `"cli-agent"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

// MARK: - Details and capabilities

extension OpenRouterLanguageModel {
    /// What every model a request may reach supports: the model's capabilities, narrowed by its fallbacks'.
    ///
    /// Tool calling, guided generation, reasoning and vision are listed only when the model and each fallback support
    /// them, so whichever model answers can handle the request.
    public var capabilities: LanguageModelCapabilities {
        sharedDetails.capabilities
    }

    /// The model's details, narrowed to what each fallback also supports, for building a request that any of them can
    /// answer. The id and name stay the model's own.
    var sharedDetails: OpenRouterModel<ContextOptions.ReasoningLevel> {
        fallbacks.reduce(OpenRouterModel<ContextOptions.ReasoningLevel>(details)) { $0.sharing($1) }
    }

    /// The ids of the model and its fallbacks, in the order OpenRouter tries them.
    var modelIDs: [OpenRouterModelID] {
        [details.id] + fallbacks.map(\.id)
    }

    /// The input kinds that every model a request may reach takes as attachments, with the model's PDF engine.
    var attachmentInputs: Set<OpenRouterInputModality> {
        sharedDetails.attachmentInputs(pdfEngine: options.pdfEngine)
    }
}

// FoundationModels 2.1.14 comes with Xcode 27.2, the first SDK with data attachments and data entries.
#if canImport(FoundationModels, _version: 2.1.14)
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
extension OpenRouterLanguageModel {
    /// Whether the model and each of its fallbacks accept the kind of data as a prompt attachment.
    ///
    /// A PDF is accepted by every model, since OpenRouter reads it for a model that can't, unless
    /// ``OpenRouterOptions/pdfEngine`` is ``OpenRouterOptions/PDFEngine/native``.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the kind conforms to an attachment kind that every model of the request accepts.
    /// - Throws: Nothing; the method throws only because Foundation Models declares it so.
    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        OpenRouterInputModality(carrying: type).map(attachmentInputs.contains) ?? false
    }

    /// Whether the model and each of its fallbacks generate the kind of data.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the kind conforms to a data kind that every model of the request generates.
    /// - Throws: Nothing; the method throws only because Foundation Models declares it so.
    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        sharedDetails.supportsDataEntryType(type)
    }
}
#endif

// MARK: - Settings

/// How an OpenRouter model's requests are sent: how long they wait, how they retry, how their images are encoded,
/// and how long model info stays fresh.
///
/// Options, such as ``OpenRouterOptions``, are what a request asks OpenRouter for. The configuration is how the
/// package sends the request, so OpenRouter never sees it. Set it when creating the model, or change it later:
///
/// ```swift
/// // Fail fast on an interactive screen.
/// let model = OpenRouterLanguageModel(
///     .anthropicClaudeHaiku5_5,
///     configuration: OpenRouterConfiguration(idleTimeout: .seconds(60), retries: RequestRetries(limit: 1)),
///     auth: .apiKey { try await keyStore.openRouterKey() }
/// )
///
/// // Prices that are never more than 10 seconds old.
/// var pricing = model
/// pricing.configuration.infoCacheLifetime = .seconds(10)
/// ```
public struct OpenRouterConfiguration: Sendable, Hashable {
    /// The longest time to wait for the next data, from sending the request to the end of the answer, or `nil` for
    /// the URL session's own timeout. OpenRouter sends keep-alive comments while a model thinks, so this doesn't limit
    /// a long answer.
    public var idleTimeout: Duration?

    /// How a request that fails before any data arrives is sent again: after a failed connection or any status from
    /// 500 up, or whatever status when `x-should-retry` is `true`, but never when it's `false`. Model info calls retry
    /// the same way.
    public var retries: RequestRetries

    /// How image attachments are encoded before they're sent.
    public var images: ImageEncoding

    /// How long an answer of a model info call, such as ``OpenRouterLanguageModel/endpoints()``, is reused before it's
    /// fetched again. Answers are shared by every model that calls with the same authentication. Zero or less fetches
    /// every time.
    public var infoCacheLifetime: Duration

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - idleTimeout: The longest time to wait for the next data, or `nil` for the URL session's own timeout.
    ///   - retries: How a failed request is sent again. The default retries up to twice.
    ///   - images: How image attachments are encoded.
    ///   - infoCacheLifetime: How long an answer of a model info call is reused. The default is a minute.
    public init(
        idleTimeout: Duration? = nil,
        retries: RequestRetries = .standard,
        images: ImageEncoding = .standard,
        infoCacheLifetime: Duration = .seconds(60)
    ) {
        self.idleTimeout = idleTimeout
        self.retries = retries
        self.images = images
        self.infoCacheLifetime = infoCacheLifetime
    }
}

// MARK: - Executor

extension OpenRouterLanguageModel {
    /// Sends a model's requests to OpenRouter and streams each answer into Foundation Models.
    ///
    /// Foundation Models creates it from the model's `executorConfiguration` and calls it for each answer. It keeps no
    /// state between answers.
    public struct Executor: LanguageModelExecutor {
        /// The model the executor sends requests for.
        public typealias Model = OpenRouterLanguageModel

        /// Where the executor sends requests and how it names the app, with the model's ``OpenRouterConfiguration``. It
        /// holds no secrets.
        ///
        /// The model makes it from its authentication's base URL, its app and its configuration, so an app sets
        /// ``OpenRouterLanguageModel/configuration`` rather than this.
        public struct Configuration: Sendable, Hashable {
            let baseURL: URL?
            let app: OpenRouterApp
            let settings: OpenRouterConfiguration

            fileprivate init(baseURL: URL?, app: OpenRouterApp = OpenRouterApp(), settings: OpenRouterConfiguration) {
                self.baseURL = baseURL
                self.app = app
                self.settings = settings
            }
        }

        /// Where requests go, how they name the app and how long they wait, which the model reads as a Chat Completions
        /// model.
        private let configuration: Configuration

        /// Creates an executor.
        ///
        /// - Parameter configuration: Where to send requests and how to name the app.
        public init(configuration: Configuration) {
            self.configuration = configuration
        }

        /// Sends one request and streams its answer.
        ///
        /// A failed request is retried up to twice, only before any data arrives: after a failed connection, any status
        /// from 500 up, or any status whose `x-should-retry` is `true`, unless its `x-should-retry` is `false` or its
        /// `retry-after-ms` or `Retry-After` asks for more than 2 minutes. A request whose schema has a constraint the host
        /// rejects is sent once more with the portable schema, which carries its constraints in descriptions.
        ///
        /// A model the request may reach that OpenRouter stopped listing is reported first, and the answer is checked
        /// against the schema's guides last, as ``DetailedLanguageModel/reportRemovedModels(for:)`` and
        /// ``DetailedLanguageModel/checkGuides(ofResponseText:for:)`` do.
        ///
        /// - Parameters:
        ///   - request: The transcript, tools, schema and options to send.
        ///   - model: The model to answer with.
        ///   - channel: Where the answer's events go.
        /// - Throws: `LanguageModelError` for failures Foundation Models has a case for, `OpenRouterError` for the rest,
        ///   `GeneratedContent.ParsingError` when a value of the answer breaks a guide of the request's schema or an object or
        ///   array answer isn't complete JSON, and `CancellationError` when the task is cancelled. An error that the model's authentication throws passes through
        ///   as it is, unless it's a `URLError`, which maps as a failed connection's does.
        public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: OpenRouterLanguageModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            try await model.chatCompletions(configuration).respond(to: request, streamingInto: channel)
        }
    }
}

extension OpenRouterLanguageModel {
    /// How the model's requests reach OpenRouter: its session and authentication, with the timeout and retries of its
    /// configuration. Chat requests and info calls both go through it.
    func connection(_ configuration: OpenRouterConfiguration) -> Connection {
        Connection(auth: auth, session: session, configuration: configuration)
    }
}

extension Connection {
    /// A connection to OpenRouter, which a model's requests and a catalog model's calls, which aren't tied to a language
    /// model, both go through. It retries any status from 500 to 599, which OpenRouter or a host returns while it's
    /// failing or overloaded.
    ///
    /// - Parameters:
    ///   - auth: How requests authenticate, and where they go, or `nil` to call OpenRouter without a key.
    ///   - session: The URL session that sends the requests.
    ///   - configuration: How long requests wait, and how they retry.
    init(auth: OpenRouterAuthentication?, session: URLSession, configuration: OpenRouterConfiguration) {
        self.init(
            session: session, authentication: auth?.requestAuthentication ?? .unauthenticated, idleTimeout: configuration.idleTimeout,
            retries: configuration.retries, retrying: .serverErrors)
    }
}
