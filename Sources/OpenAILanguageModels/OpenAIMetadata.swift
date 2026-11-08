public import Foundation
public import FoundationModels
public import LanguageModels

// MARK: - Response

/// What OpenAI reported about an answer, read from the metadata of its response entry, or about a request that ended
/// in tool calls, read from its first call.
///
/// `Transcript.Response.openAI` and `Transcript.ToolCalls.openAI` read it. The response entry that ends an answer
/// carries the facts, and one that tool calls follow carries only the ``citations``. A fact OpenAI didn't report is
/// `nil`, and a list it didn't report is empty:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if case .response(let answer)? = response.transcriptEntries.last {
///     print("Request id, for OpenAI's support:", answer.openAI.requestID ?? "none")
///     if answer.openAI.finishReason == .length {
///         print("The answer was cut short at its token limit.")
///     }
/// }
/// ```
///
/// The facts ``model``, ``responseID``, ``requestID``, ``finishReason``, ``serviceTier`` and ``citations`` are the shared
/// ones that `providerMetadata` also reads, as OpenAI's types. What the ``OpenAIServerTool``s did is in ``sources``,
/// ``serverToolCalls`` and ``fileCitations``.
public struct OpenAIResponseMetadata: Sendable, Hashable {
    /// The model that answered, as OpenAI names it, such as the dated snapshot `gpt-5-nano-2025-08-07` for
    /// `gpt-5-nano`.
    public let model: OpenAIModelID?

    /// OpenAI's id for the response, such as `resp_…`.
    public let responseID: String?

    /// OpenAI's id for the request, which its support asks for.
    public let requestID: String?

    /// Why the answer ended, such as ``FinishReason/length`` when it reached its token limit.
    ///
    /// A text answer cut off at its token limit doesn't throw, so its reason is the way to tell. A guided answer, or
    /// tool calls, cut off there throw instead.
    public let finishReason: FinishReason?

    /// The processing tier that served the answer, which it's billed at. It can differ from
    /// ``OpenAIOptions/serviceTier``, such as ``OpenAIServiceTier/default`` for a request that asked for
    /// ``OpenAIServiceTier/auto``.
    public let serviceTier: OpenAIServiceTier?

    /// The web pages the answer cites, in the order OpenAI listed them.
    ///
    /// Citations point into the answer's text, so they're on the response entry even when tool calls end the answer.
    public let citations: [Citation]

    /// Every page the answer's web searches consulted, each once, in the order they came, when the web search lists its
    /// sources; empty otherwise. They're usually more pages than the answer cites.
    public let sources: [URL]

    /// The answer's calls to ``OpenAILanguageModel/serverTools``, in their order, such as each web search.
    public let serverToolCalls: [OpenAIServerToolCall]

    /// The files the answer cites, from a file search, in the order OpenAI listed them.
    ///
    /// Unlike ``citations``, they're on the entry that ends the answer: the first tool call when tool calls end it.
    public let fileCitations: [OpenAIFileCitation]

    /// The answer's messages, in their order, each with its phase, such as a ``Phase/commentary`` preamble before the
    /// ``Phase/finalAnswer``, or empty when the model names no phases and the answer holds no message out of its text.
    public let messages: [Message]

    /// What OpenAI reported about the request's counts, such as the prompt tokens written to its cache.
    ///
    /// A response's own `usage` has only its last request's facts, so a response whose tool calls ran reads each
    /// earlier request's here, on the tool calls it asked for.
    public let usage: OpenAIUsageMetadata

    /// The facts in a response entry's metadata.
    init(_ metadata: [String: GeneratedContent]) {
        let shared = ProviderResponseMetadata(metadata)
        model = shared.model.map(OpenAIModelID.init(rawValue:))
        responseID = shared.responseID
        requestID = shared.requestID
        finishReason = shared.finishReason
        serviceTier = shared.serviceTier.map(OpenAIServiceTier.init(rawValue:))
        citations = shared.citations
        let serverTools = Responses.ServerToolOutput(MetadataValues(metadata), key: Self.serverToolsKey)
        serverToolCalls = serverTools.calls.compactMap(OpenAIServerToolCall.init)
        var seen: Set<URL> = []
        sources = serverToolCalls.flatMap(\.sources).filter { seen.insert($0).inserted }
        fileCitations = serverTools.fileCitations.map(OpenAIFileCitation.init)
        messages = MetadataValues(metadata).structures(Self.phasesKey).compactMap(Message.init)
        usage = OpenAIUsageMetadata(metadata)
    }
}

extension OpenAIResponseMetadata {
    /// One of an answer's messages: its phase, and where its text is.
    ///
    /// The answer's text joins the text of its messages in their order, so a message's ``length`` tells where its own
    /// text ends. A guided answer decodes only its first message with no phase or the ``Phase/finalAnswer`` phase, so
    /// the text of its other messages, such as a ``Phase/commentary`` preamble, stays out of the answer's text and is
    /// in ``heldText`` instead.
    public struct Message: Sendable, Hashable {
        /// The message's phase, or `nil` when OpenAI named none.
        public let phase: Phase?

        /// The length of the message's text in the answer's text, in characters, or 0 when ``heldText`` holds it.
        public let length: Int

        /// The message's text when it's held out of the answer's text, or `nil` when the answer's text holds it.
        public let heldText: String?

        /// A message read from an element of the metadata's list of phases, or `nil` for an element that isn't one.
        fileprivate init?(_ values: MetadataValues) {
            guard let message = Responses.MessagePhase(values) else { return nil }
            phase = message.phase.map(Phase.init(rawValue:))
            length = message.length
            heldText = message.heldText
        }
    }

    /// The phase of one of an answer's messages, such as ``commentary`` or ``finalAnswer``.
    public struct Phase: ProviderVocabulary {
        /// A preamble the model writes before it calls a tool or answers, such as what it's about to do.
        public static let commentary: Self = "commentary"

        /// The message that holds the answer.
        public static let finalAnswer: Self = "final_answer"

        /// The phase as OpenAI's API spells it.
        public let rawValue: String

        /// Creates a phase from OpenAI's spelling of it.
        ///
        /// - Parameter rawValue: The phase, such as `"commentary"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

/// One call the model made to a server tool while it answered, as OpenAI reported it.
///
/// Each kind fills its own facts: a web search its ``action``, ``queries``, ``url`` and ``pattern``, a file search its
/// ``queries``, and an image generation its ``revisedPrompt``. The rest stay empty or `nil`.
public struct OpenAIServerToolCall: Sendable, Hashable {
    /// OpenAI's id for the call, such as `ws_…`.
    public let id: String

    /// The kind of call, such as ``Kind/webSearch``.
    public let kind: Kind

    /// How the call ended, such as ``Status/completed``, or `nil` when OpenAI didn't say.
    public let status: Status?

    /// What a web search did: searched, opened a page, or looked for text in one.
    public let action: Action?

    /// What a web search or a file search searched for, in order.
    public let queries: [String]

    /// The page a web search opened or looked in.
    public let url: URL?

    /// The text a web search looked for in a page.
    public let pattern: String?

    /// The prompt an image was drawn from, as the model revised it.
    public let revisedPrompt: String?

    /// The pages a web search consulted, when it lists its sources.
    fileprivate let sources: [URL]

    /// A call read from its output item, or `nil` for an item without an id or a type.
    fileprivate init?(_ item: JSONValue) {
        guard let id = item["id"]?.stringValue, let type = item["type"]?.stringValue else { return nil }
        self.id = id
        kind = Kind(rawValue: type)
        status = item["status"]?.stringValue.map(Status.init(rawValue:))
        let action = item["action"]
        self.action = action?["type"]?.stringValue.map(Action.init(rawValue:))
        let queries = Self.elements(of: action?["queries"] ?? item["queries"]).compactMap(\.stringValue)
        self.queries = queries.isEmpty ? (action?["query"]?.stringValue).map { [$0] } ?? [] : queries
        url = action?["url"]?.stringValue.flatMap(URL.init(string:))
        pattern = action?["pattern"]?.stringValue
        revisedPrompt = item["revised_prompt"]?.stringValue
        sources = Self.elements(of: action?["sources"]).compactMap { $0["url"]?.stringValue.flatMap(URL.init(string:)) }
    }

    /// The elements of a list, or none for another value.
    private static func elements(of value: JSONValue?) -> [JSONValue] {
        if case .array(let elements)? = value { elements } else { [] }
    }
}

extension OpenAIServerToolCall {
    /// A kind of server tool call, by the type of its output item.
    ///
    /// Kinds are an open vocabulary: a kind OpenAI adds reads too, with or without a static member.
    public struct Kind: ProviderVocabulary {
        /// A web search's call.
        public static let webSearch: Self = "web_search_call"

        /// An image generation's call.
        public static let imageGeneration: Self = "image_generation_call"

        /// A file search's call.
        public static let fileSearch: Self = "file_search_call"

        /// The type of the call's output item in OpenAI's API.
        public let rawValue: String

        /// Creates a kind from the type of the call's output item.
        ///
        /// - Parameter rawValue: The type, such as `"web_search_call"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// How a server tool call ended.
    ///
    /// Statuses are an open vocabulary: any status OpenAI reports reads, with or without a static member.
    public struct Status: ProviderVocabulary {
        /// The call finished.
        public static let completed: Self = "completed"

        /// The call failed, such as an image that a moderation check stopped.
        public static let failed: Self = "failed"

        /// The call stopped before it finished.
        public static let incomplete: Self = "incomplete"

        /// The status's name in OpenAI's API.
        public let rawValue: String

        /// Creates a status from its name in OpenAI's API.
        ///
        /// - Parameter rawValue: The name, such as `"completed"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// What a web search did.
    ///
    /// Actions are an open vocabulary: any action OpenAI reports reads, with or without a static member.
    public struct Action: ProviderVocabulary {
        /// It searched the web for its ``OpenAIServerToolCall/queries``.
        public static let search: Self = "search"

        /// It opened the page at its ``OpenAIServerToolCall/url``.
        public static let openPage: Self = "open_page"

        /// It looked for its ``OpenAIServerToolCall/pattern`` in the page at its ``OpenAIServerToolCall/url``.
        public static let findInPage: Self = "find_in_page"

        /// The action's name in OpenAI's API.
        public let rawValue: String

        /// Creates an action from its name in OpenAI's API.
        ///
        /// - Parameter rawValue: The name, such as `"search"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

/// A file that an answer cites, from a file search.
public struct OpenAIFileCitation: Sendable, Hashable {
    /// OpenAI's id for the file, such as `file-…`.
    public let fileID: String

    /// The file's name.
    public let filename: String?

    /// Where the citation goes in the answer's text, in characters from its start, or `nil` when that isn't known, as
    /// in a guided answer's held-out text, or after text that isn't ASCII, since OpenAI doesn't say what its offsets
    /// count.
    public let offset: Int?

    /// A citation as the answer keeps it.
    fileprivate init(_ citation: Responses.FileCitation) {
        fileID = citation.fileID
        filename = citation.filename
        offset = citation.offset
    }
}

// MARK: - Usage

/// What OpenAI reported about an answer's counts beyond Foundation Models' own, read from its usage's metadata.
///
/// `LanguageModelSession.Usage.openAI` reads it. The usage's own input, cached, output and reasoning token counts hold
/// the rest, and the package keeps no prices, so it reports no cost. A fact OpenAI didn't report is `nil`:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if let written = response.usage.openAI.cacheWriteTokenCount {
///     print("\(written) prompt tokens went into OpenAI's cache.")
/// }
/// ```
///
/// The facts are those of one request. A response whose tool calls ran has the last request's, and a session's own
/// `usage` keeps no metadata, so its facts are all `nil`. Each request's facts are also on the transcript entry that
/// ends it, which ``OpenAIResponseMetadata/usage`` reads.
public struct OpenAIUsageMetadata: Sendable, Hashable {
    /// The prompt tokens written to OpenAI's prompt cache.
    public let cacheWriteTokenCount: Int?

    /// The billable searches of the answer's ``OpenAIServerTool`` web search, or `nil` when none ran. Opening a page
    /// isn't a search.
    public let webSearchCount: Int?

    /// The facts in a usage's metadata.
    fileprivate init(_ metadata: [String: GeneratedContent]) {
        let shared = ProviderUsageMetadata(metadata)
        cacheWriteTokenCount = shared.cacheWriteTokenCount
        webSearchCount = shared.webSearchCount
    }
}

// MARK: - Generated data

#if canImport(FoundationModels, _version: 2.1.14)
/// What OpenAI reported about data the model generated, such as an image, read from its data entry's metadata.
///
/// `Transcript.DataEntry.openAI` reads it. A fact OpenAI didn't report is `nil`:
///
/// ```swift
/// for case .data(let image) in session.transcript {
///     print(image.openAI.revisedPrompt ?? "No revised prompt.")
/// }
/// ```
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
public struct OpenAIDataMetadata: Sendable, Hashable {
    /// OpenAI's id for the call that generated the data, such as `ig_…`, as ``OpenAIServerToolCall/id`` names it.
    public let callID: String?

    /// The prompt the image was drawn from, as the model revised it.
    public let revisedPrompt: String?

    /// The facts in a data entry's metadata.
    fileprivate init(_ metadata: GeneratedContent) {
        let call = MetadataValues(metadata).flatMap { values in
            Responses.ServerToolOutput(values, key: OpenAIResponseMetadata.serverToolsKey).calls.first
        }
        callID = call?["id"]?.stringValue
        revisedPrompt = call?["revised_prompt"]?.stringValue
    }
}
#endif

// MARK: - Error

/// What OpenAI reported about a failure that throws Foundation Models' `LanguageModelError`, in OpenAI's own words,
/// read from the error's metadata.
///
/// `LanguageModelError.openAI` reads it. A fact OpenAI didn't report is `nil`:
///
/// ```swift
/// do {
///     let response = try await session.respond(to: "Plan dinner.")
///     print(response.content)
/// } catch let error as LanguageModelError {
///     print("Code \(error.openAI.code?.rawValue ?? "none"), request id \(error.openAI.requestID ?? "none")")
/// }
/// ```
///
/// Its facts are the shared ones that `providerMetadata` also reads, with the code as an ``OpenAIError/Code``.
public struct OpenAIErrorMetadata: Sendable, Hashable {
    /// The HTTP status of the response that failed, such as 429 for a rate limit, or `nil` for a failure in the stream,
    /// which arrives after the response's HTTP 200.
    public let status: Int?

    /// The code the failure would have as an ``OpenAIError``: OpenAI's code or error type, or the package's code for
    /// the HTTP status, such as ``OpenAIError/Code/unmapped`` for a 429 without one.
    public let code: OpenAIError.Code?

    /// OpenAI's id for the request that failed, which its support asks for.
    public let requestID: String?

    /// The facts in an error's metadata.
    fileprivate init(_ metadata: [String: any Sendable]) {
        let shared = ProviderErrorMetadata(metadata)
        status = shared.status
        code = shared.code.map(OpenAIError.Code.init(rawValue:))
        requestID = shared.requestID
    }
}

// MARK: - Reading

extension Transcript.Response {
    /// What OpenAI reported about the answer, such as the model that answered, OpenAI's id for the request and why
    /// the answer ended.
    public var openAI: OpenAIResponseMetadata {
        OpenAIResponseMetadata(metadata)
    }
}

extension Transcript.ToolCalls {
    /// What OpenAI reported about the request that asked for these tool calls, such as the model that answered and the
    /// phases of the messages before them.
    ///
    /// Foundation Models keeps no readable metadata on the tool-calls entry itself, so the request's facts sit on its
    /// first call, and this reads them from there. A request that asked for several calls has one set of facts.
    public var openAI: OpenAIResponseMetadata {
        OpenAIResponseMetadata(first?.metadata ?? [:])
    }
}

#if canImport(FoundationModels, _version: 2.1.14)
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
extension Transcript.DataEntry {
    /// What OpenAI reported about the data, such as the revised prompt of a generated image.
    public var openAI: OpenAIDataMetadata {
        OpenAIDataMetadata(metadata)
    }
}
#endif

extension LanguageModelSession.Usage {
    /// What OpenAI reported about the answer's counts, such as the prompt tokens written to its cache.
    public var openAI: OpenAIUsageMetadata {
        OpenAIUsageMetadata(metadata)
    }
}

extension LanguageModelError {
    /// What OpenAI reported about the failure, such as its code and OpenAI's id for the request.
    public var openAI: OpenAIErrorMetadata {
        OpenAIErrorMetadata(contextMetadata)
    }
}

// MARK: - Keys

extension OpenAIResponseMetadata {
    /// The key of the `phase` of each of an answer's messages, such as `commentary` or `final_answer`, on the entry that
    /// ends the answer: a list of structures with a `phase` and the `length` of the message's text, in characters. A
    /// guided answer's message that doesn't decode, such as a `commentary` preamble, stays out of the answer's text, so
    /// its structure keeps the text itself under `heldText`, with a `length` of 0. Each message goes back with its phase
    /// on later turns.
    ///
    /// It starts with `openAI.`, so it never collides with another provider's keys. Saved transcripts keep it, so its
    /// spelling never changes.
    static let phasesKey = "openAI.phases"

    /// The key of what an answer's server tools left, on the entry that ends the answer: their calls, in their order,
    /// each as the JSON text of its item, without an image, and the files the answer cites. A generated image's data
    /// entry keeps the image's call under it too. A call that completed goes back on later turns while the request still
    /// sends its tool, and an image's call only while OpenAI keeps the responses.
    ///
    /// It starts with `openAI.`, so it never collides with another provider's keys. Saved transcripts keep it, so its
    /// spelling never changes.
    static let serverToolsKey = "openAI.serverTools"
}
