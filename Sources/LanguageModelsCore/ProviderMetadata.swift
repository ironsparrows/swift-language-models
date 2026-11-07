public import Foundation
public import FoundationModels

// MARK: - Response

/// What a provider reported about an answer, read from the metadata of its response entry, or about a request that
/// ended in tool calls, read from its first call.
///
/// `providerMetadata` on a `Transcript.Response` or a `Transcript.ToolCalls` reads it, whichever provider module wrote
/// the entry. The response entry that ends an answer carries the facts, and one that tool calls follow carries only
/// the ``citations``. A fact the provider didn't report is `nil`, and a list it didn't report is empty:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if case .response(let answer)? = response.transcriptEntries.last {
///     print("\(answer.providerMetadata.model ?? "A model") answered.")
///     if answer.providerMetadata.finishReason == .length {
///         print("The answer was cut short at its token limit.")
///     }
/// }
/// ```
///
/// Each provider module also reads these facts in its own words, with what only it reports, through a property named
/// for the provider, such as `openRouter` for what OpenRouter's router did.
///
/// A provider module of your own writes the facts by passing ``channelMetadata`` to the channel's `updateMetadata`
/// action, so it needs no key.
public struct ProviderResponseMetadata: Sendable, Hashable {
    /// The model that answered, in the provider's spelling of its id, which can differ from the one asked for when the
    /// provider routes the request or a fallback answers.
    public let model: String?

    /// The company whose servers ran the model, such as `Anthropic`, when the provider names one.
    public let host: String?

    /// The provider's id for the answer.
    public let responseID: String?

    /// The provider's id for the request that got the answer, which its support asks for.
    public let requestID: String?

    /// Why the answer ended, such as ``FinishReason/length`` when it reached its token limit.
    ///
    /// A text answer cut off at its token limit doesn't throw, so its reason is the way to tell. A guided answer, or
    /// tool calls, cut off there throw instead.
    public let finishReason: FinishReason?

    /// The processing tier that served the answer, which it's billed at, in the provider's own word for it.
    public let serviceTier: String?

    /// The web pages the answer cites, in the order the provider listed them.
    ///
    /// Citations point into the answer's text, so they're on the response entry even when tool calls end the answer.
    public let citations: [Citation]

    /// What the provider reported about the request's cost and counts.
    ///
    /// A response's own `usage` has only its last request's facts, so a response whose tool calls ran reads each
    /// earlier request's here, on the tool calls it asked for.
    public let usage: ProviderUsageMetadata

    /// Creates the facts of an answer, for a provider module to write or for a test.
    ///
    /// - Parameters:
    ///   - model: The model that answered, in the provider's spelling of its id.
    ///   - host: The company whose servers ran the model.
    ///   - responseID: The provider's id for the answer.
    ///   - requestID: The provider's id for the request that got the answer.
    ///   - finishReason: Why the answer ended.
    ///   - serviceTier: The processing tier that served the answer, in the provider's own word for it.
    ///   - citations: The web pages the answer cites.
    ///   - usage: What the provider reported about the request's cost and counts.
    public init(
        model: String? = nil,
        host: String? = nil,
        responseID: String? = nil,
        requestID: String? = nil,
        finishReason: FinishReason? = nil,
        serviceTier: String? = nil,
        citations: [Citation] = [],
        usage: ProviderUsageMetadata = ProviderUsageMetadata()
    ) {
        self.model = model
        self.host = host
        self.responseID = responseID
        self.requestID = requestID
        self.finishReason = finishReason
        self.serviceTier = serviceTier
        self.citations = citations
        self.usage = usage
    }

    /// The facts in a response entry's metadata.
    package init(_ metadata: [String: GeneratedContent]) {
        let values = MetadataValues(metadata)
        model = values.string(Key.model)
        host = values.string(Key.provider)
        responseID = values.string(Key.responseID)
        requestID = values.string(Key.requestID)
        finishReason = values.string(Key.finishReason).map(FinishReason.init(rawValue:))
        serviceTier = values.string(Key.serviceTier)
        citations = values.array(Key.citations).compactMap(Citation.init(metadataValue:))
        usage = ProviderUsageMetadata(metadata)
    }

    /// The facts as the metadata of the entry that ends the answer, to pass to the channel's `updateMetadata` action.
    /// A fact that's `nil` and an empty list are left out.
    public var channelMetadata: [String: any ConvertibleToGeneratedContent] {
        var metadata = usage.channelMetadata
        metadata[Key.model] = model
        metadata[Key.provider] = host
        metadata[Key.responseID] = responseID
        metadata[Key.requestID] = requestID
        metadata[Key.finishReason] = finishReason?.rawValue
        metadata[Key.serviceTier] = serviceTier
        metadata[Key.citations] = citations.isEmpty ? nil : citations.map(\.metadataValue)
        return metadata
    }
}

/// A web page that an answer cites.
///
/// ``ProviderResponseMetadata/citations`` lists the pages an answer cites, and so does each provider module's reader of
/// the answer's metadata.
public struct Citation: Sendable, Hashable {
    /// The page's address.
    public let url: URL

    /// The page's title, when the search reported one.
    public let title: String?

    /// Text from the page that the search returned to the model, which `[...]` separates when it comes from different
    /// parts of the page.
    public let excerpt: String?

    /// Where the text that cites the page starts in the answer's text, as an offset, when the provider reported it.
    ///
    /// Providers pass on their host's offset without saying what it counts, characters, UTF-16 code units or bytes, so
    /// check that it falls within the text before using it.
    public let startOffset: Int?

    /// Where the text that cites the page ends in the answer's text, as an offset in the same unit as
    /// ``startOffset``, when the provider reported it.
    ///
    /// Whether it's the offset of the last cited character or of the one after it isn't documented either.
    public let endOffset: Int?

    /// Creates a citation, such as for a preview or a test.
    ///
    /// - Parameters:
    ///   - url: The page's address.
    ///   - title: The page's title.
    ///   - excerpt: Text from the page that the search returned to the model.
    ///   - startOffset: Where the text that cites the page starts in the answer's text.
    ///   - endOffset: Where the text that cites the page ends in the answer's text.
    public init(url: URL, title: String? = nil, excerpt: String? = nil, startOffset: Int? = nil, endOffset: Int? = nil) {
        self.url = url
        self.title = title
        self.excerpt = excerpt
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

extension Citation {
    /// The citation as a value of an entry's metadata.
    fileprivate var metadataValue: GeneratedContent {
        GeneratedContent(properties: [
            Field.url: url.absoluteString,
            Field.title: title,
            Field.excerpt: excerpt,
            Field.startOffset: startOffset,
            Field.endOffset: endOffset,
        ])
    }

    /// A citation read back from an entry's metadata, or `nil` when the value has no valid URL.
    ///
    /// - Parameter content: One element of an entry's list of citations.
    fileprivate init?(metadataValue content: GeneratedContent) {
        guard let address = try? content.value(String.self, forProperty: Field.url), let url = URL(string: address) else {
            return nil
        }
        self.init(
            url: url,
            title: try? content.value(String?.self, forProperty: Field.title),
            excerpt: try? content.value(String?.self, forProperty: Field.excerpt),
            startOffset: try? content.value(Int?.self, forProperty: Field.startOffset),
            endOffset: try? content.value(Int?.self, forProperty: Field.endOffset)
        )
    }

    /// The names of a citation's fields in an entry's metadata.
    private enum Field {
        static let url = "url"
        static let title = "title"
        static let excerpt = "excerpt"
        static let startOffset = "startOffset"
        static let endOffset = "endOffset"
    }
}

/// Why an answer ended, such as ``length`` when it reached its token limit.
///
/// ``ProviderResponseMetadata/finishReason`` reads it from the entry that ends an answer. Each provider module maps its
/// provider's reasons onto these words, and passes on any other reason in the provider's spelling, which is valid too.
/// An answer that a content filter stopped or that ended in an error throws instead, so no entry carries such a reason.
public struct FinishReason: ProviderVocabulary {
    /// The model finished.
    public static let stop: Self = "stop"

    /// The answer reached its token limit, so its text is cut short.
    public static let length: Self = "length"

    /// The model asked for tool calls.
    public static let toolCalls: Self = "tool_calls"

    /// The reason's spelling.
    public let rawValue: String

    /// Creates a reason from its spelling.
    ///
    /// - Parameter rawValue: The reason, such as `"length"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Usage

/// What a provider reported about an answer's cost and counts beyond Foundation Models' own, read from its usage's
/// metadata.
///
/// `LanguageModelSession.Usage.providerMetadata` reads it, whichever provider module wrote the usage. The usage's own
/// input, cached, output and reasoning token counts hold the rest. A fact the provider didn't report is `nil`:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if let cost = response.usage.providerMetadata.cost {
///     print("The answer cost \(cost) US dollars.")
/// }
/// ```
///
/// The facts are those of one request. A response whose tool calls ran has the last request's, and a session's own
/// `usage` keeps no metadata, so its facts are all `nil`. Each request's facts are also on the transcript entry that
/// ends it, which ``ProviderResponseMetadata/usage`` reads.
///
/// A provider module of your own writes the facts by passing ``channelMetadata`` to the channel's `updateUsage` action.
public struct ProviderUsageMetadata: Sendable, Hashable {
    /// What the answer cost, in US dollars, when the provider reports it.
    public let cost: Decimal?

    /// The prompt tokens written to the host's prompt cache.
    public let cacheWriteTokenCount: Int?

    /// The web searches the provider ran for the answer.
    public let webSearchCount: Int?

    /// Creates the facts of an answer's usage, for a provider module to write or for a test.
    ///
    /// - Parameters:
    ///   - cost: What the answer cost, in US dollars.
    ///   - cacheWriteTokenCount: The prompt tokens written to the host's prompt cache.
    ///   - webSearchCount: The web searches the provider ran for the answer.
    public init(cost: Decimal? = nil, cacheWriteTokenCount: Int? = nil, webSearchCount: Int? = nil) {
        self.cost = cost
        self.cacheWriteTokenCount = cacheWriteTokenCount
        self.webSearchCount = webSearchCount
    }

    /// The facts in a usage's metadata.
    package init(_ metadata: [String: GeneratedContent]) {
        let values = MetadataValues(metadata)
        cost = values.decimal(Key.cost)
        cacheWriteTokenCount = values.integer(Key.cacheWriteTokenCount)
        webSearchCount = values.integer(Key.webSearchCount)
    }

    /// The facts as the metadata of an answer's usage, to pass to the channel's `updateUsage` action. A fact that's `nil`
    /// is left out.
    public var channelMetadata: [String: any ConvertibleToGeneratedContent] {
        var metadata: [String: any ConvertibleToGeneratedContent] = [:]
        metadata[Key.cost] = cost?.metadataNumber
        metadata[Key.cacheWriteTokenCount] = cacheWriteTokenCount
        metadata[Key.webSearchCount] = webSearchCount
        return metadata
    }
}

// MARK: - Error

/// What a provider reported about a failure that throws Foundation Models' `LanguageModelError`, read from the error's
/// metadata.
///
/// `providerMetadata` on a `LanguageModelError` reads it, whichever provider module threw the error. A fact the
/// provider didn't report is `nil`:
///
/// ```swift
/// do {
///     let response = try await session.respond(to: "Plan dinner.")
///     print(response.content)
/// } catch let error as LanguageModelError {
///     print("HTTP \(error.providerMetadata.status ?? 0), code \(error.providerMetadata.code ?? "none")")
///     print("Request id, for the provider's support:", error.providerMetadata.requestID ?? "none")
/// }
/// ```
///
/// An error that Foundation Models threw itself, such as for a capability the model lacks, has none of them. Each
/// provider module also reads its own facts, in its own words, through a property named for the provider, such as
/// `openRouter` for the budget a request ran into.
///
/// A provider module of your own writes the facts by passing ``contextMetadata`` as the `metadata` of the
/// `LanguageModelError` it throws. Foundation Models 2.1.14, in Xcode 27.2, drops the `metadata` argument of
/// `LanguageModelError.ContextSizeExceeded`'s initializer, so set `metadata` after creating it.
public struct ProviderErrorMetadata: Sendable, Hashable {
    /// The HTTP status of the response that failed, such as 429 for a rate limit, or `nil` for a failure in the stream,
    /// which arrives after the response's HTTP 200.
    public let status: Int?

    /// The provider module's code for the failure, in the provider's own words, such as `rate_limit_exceeded`.
    public let code: String?

    /// The company whose servers failed, when the provider names one, such as the host OpenRouter sent the request to.
    public let host: String?

    /// The provider's id for the request that failed, which its support asks for.
    public let requestID: String?

    /// Creates the facts of a failure, for a provider module to write or for a test.
    ///
    /// - Parameters:
    ///   - status: The HTTP status of the response that failed.
    ///   - code: The provider module's code for the failure, in the provider's own words.
    ///   - host: The company whose servers failed.
    ///   - requestID: The provider's id for the request that failed.
    public init(status: Int? = nil, code: String? = nil, host: String? = nil, requestID: String? = nil) {
        self.status = status
        self.code = code
        self.host = host
        self.requestID = requestID
    }

    /// The facts in an error's metadata.
    package init(_ metadata: [String: any Sendable]) {
        self.init(
            status: metadata[Key.status] as? Int, code: metadata[Key.errorCode] as? String, host: metadata[Key.provider] as? String,
            requestID: metadata[Key.requestID] as? String)
    }

    /// The facts as the metadata of a `LanguageModelError`, under the keys every provider module's errors share, to add
    /// a module's own keys to. A fact that's `nil` has no key.
    public var contextMetadata: [String: any Sendable] {
        var metadata: [String: any Sendable] = [:]
        metadata[Key.status] = status
        metadata[Key.errorCode] = code
        metadata[Key.provider] = host
        metadata[Key.requestID] = requestID
        return metadata
    }
}

// MARK: - Reading

extension Transcript.Response {
    /// What the provider reported about the answer, such as the model that answered and why the answer ended.
    public var providerMetadata: ProviderResponseMetadata {
        ProviderResponseMetadata(metadata)
    }
}

extension Transcript.ToolCalls {
    /// What the provider reported about the request that asked for these tool calls, such as the model that answered.
    ///
    /// Foundation Models keeps no readable metadata on the tool-calls entry itself, so the request's facts sit on its
    /// first call, and this reads them from there. A request that asked for several calls has one set of facts.
    public var providerMetadata: ProviderResponseMetadata {
        ProviderResponseMetadata(first?.metadata ?? [:])
    }
}

extension LanguageModelSession.Usage {
    /// What the provider reported about the answer's cost and counts, such as its cost in US dollars.
    public var providerMetadata: ProviderUsageMetadata {
        ProviderUsageMetadata(metadata)
    }
}

extension LanguageModelError {
    /// What the provider reported about the failure, such as its HTTP status, its code and its id for the request.
    public var providerMetadata: ProviderErrorMetadata {
        ProviderErrorMetadata(contextMetadata)
    }

    /// The error's metadata, whichever kind of failure it is, which a provider module's own reader reads too.
    package var contextMetadata: [String: any Sendable] {
        switch self {
        case .contextSizeExceeded(let context): context.metadata
        case .rateLimited(let context): context.metadata
        case .guardrailViolation(let context): context.metadata
        case .refusal(let context): context.metadata
        case .unsupportedCapability(let context): context.metadata
        case .unsupportedTranscriptContent(let context): context.metadata
        case .unsupportedGenerationGuide(let context): context.metadata
        case .unsupportedLanguageOrLocale(let context): context.metadata
        case .timeout(let context): context.metadata
        @unknown default: [:]
        }
    }
}

/// Typed reads of an entry's or usage's metadata, or of a structure in it. A read is `nil`, or a list empty, when the
/// key is missing or its value is of another kind.
package struct MetadataValues {
    private let values: [String: GeneratedContent]

    package init(_ values: [String: GeneratedContent]) {
        self.values = values
    }

    /// The properties of a structure, or `nil` when the content isn't one.
    private init?(_ content: GeneratedContent) {
        guard case .structure(let properties, _) = content.kind else { return nil }
        self.init(properties)
    }

    package func string(_ key: String) -> String? {
        if case .string(let value)? = values[key]?.kind { value } else { nil }
    }

    package func bool(_ key: String) -> Bool? {
        if case .bool(let value)? = values[key]?.kind { value } else { nil }
    }

    /// A whole number, or `nil` for a fraction.
    package func integer(_ key: String) -> Int? {
        number(key).flatMap { Int(exactly: $0) }
    }

    /// An amount as a decimal number.
    package func decimal(_ key: String) -> Decimal? {
        number(key).flatMap(Decimal.init(metadataNumber:))
    }

    /// A number of seconds as a duration, rounded to the nanosecond, so `2.016` is exactly 2,016 milliseconds.
    package func duration(_ key: String) -> Duration? {
        number(key).flatMap { Int64(exactly: ($0 * 1e9).rounded()) }.map { .nanoseconds($0) }
    }

    /// The elements of a list.
    fileprivate func array(_ key: String) -> [GeneratedContent] {
        if case .array(let elements)? = values[key]?.kind { elements } else { [] }
    }

    /// The structures in a list, skipping any element that isn't one.
    package func structures(_ key: String) -> [MetadataValues] {
        array(key).compactMap(MetadataValues.init)
    }

    private func number(_ key: String) -> Double? {
        if case .number(let value)? = values[key]?.kind { value } else { nil }
    }
}

extension Decimal {
    /// An amount as the decimal number its shortest spelling names, so `0.000012345` reads as exactly that rather than
    /// the binary fraction nearest to it, `0.000012344999999999997952`.
    ///
    /// - Parameter number: The amount as metadata keeps it, or as a provider's response reports it.
    package init?(metadataNumber number: Double) {
        guard number.isFinite else { return nil }
        // A nil locale always reads `.` as the decimal separator; Double's description is never localized.
        self.init(string: String(number), locale: nil)
    }

    /// The amount as metadata keeps it, the number nearest to its spelling, so an amount read from a number goes back as
    /// that number.
    fileprivate var metadataNumber: Double? {
        isFinite ? Double(description) : nil
    }
}

// MARK: - Keys

/// The keys of the facts that every provider module reports the same way, on the entries of an answer and on the errors
/// it ends in. A provider module's own facts use keys of its own, with a prefix that names the module, such as `vendor.`.
///
/// Saved transcripts keep the keys, so their spellings never change.
private enum Key {
    static let model = "model"

    /// The host of an answer, and on an error's metadata the company that failed.
    static let provider = "provider"

    static let responseID = "responseID"
    static let requestID = "requestID"

    /// A ``FinishReason`` raw value.
    static let finishReason = "finishReason"

    static let serviceTier = "serviceTier"

    /// A list of structures, each with the page's `url`, and its `title`, `excerpt`, `startOffset` and `endOffset` when
    /// known.
    static let citations = "citations"

    /// In US dollars, as a number.
    static let cost = "cost"

    static let cacheWriteTokenCount = "cacheWriteTokenCount"
    static let webSearchCount = "webSearchCount"
    static let status = "status"
    static let errorCode = "errorCode"
}
