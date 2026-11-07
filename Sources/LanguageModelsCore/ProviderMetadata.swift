public import Foundation
public import FoundationModels

// MARK: - Response

/// A web page that an answer cites.
///
/// The response entry of an answer that cites pages lists them in its metadata, under
/// ``LanguageModelMetadataKey/citations``, and a provider module's reader of that metadata reads them as citations.
public struct Citation: Sendable, Hashable {
    /// The page's address.
    public let url: URL

    /// The page's title, when the search reported one.
    public let title: String?

    /// Text from the page that the search returned to the model, which `[...]` separates when it comes from different
    /// parts of the page.
    public let excerpt: String?

    /// Where the text that cites the page starts in the answer's text, as an offset, when the service reported it.
    ///
    /// Services pass on their host's offset without saying what it counts, characters, UTF-16 code units or bytes, so
    /// check that it falls within the text before using it.
    public let startOffset: Int?

    /// Where the text that cites the page ends in the answer's text, as an offset in the same unit as
    /// ``startOffset``, when the service reported it.
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
    package var metadataValue: GeneratedContent {
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
    /// - Parameter content: One element of the list under ``LanguageModelMetadataKey/citations``.
    package init?(metadataValue content: GeneratedContent) {
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
/// The entry that ends an answer carries it under ``LanguageModelMetadataKey/finishReason``. Each provider module maps
/// its service's reasons onto these words, and passes on any other reason in its service's spelling, which is valid
/// too. An answer that a content filter stopped or that ended in an error throws instead, so no entry carries such a
/// reason.
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
///     print("HTTP \(error.providerMetadata.status ?? 0), code \(error.providerMetadata.errorCode ?? "none")")
///     print("Request id, for the provider's support:", error.providerMetadata.requestID ?? "none")
/// }
/// ```
///
/// Each fact comes from a ``LanguageModelMetadataKey`` key, such as ``status`` from
/// ``LanguageModelMetadataKey/status``. An error that Foundation Models threw itself, such as for a capability the
/// model lacks, has none of them. Each provider module also reads its own facts, in its own words, through a property
/// named for the provider, such as `openRouter` for the budget a request ran into.
public struct ProviderErrorMetadata: Sendable, Hashable {
    /// The HTTP status of the response that failed, such as 429 for a rate limit, or `nil` for a failure in the stream,
    /// which arrives after the response's HTTP 200.
    public let status: Int?

    /// The provider module's code for the failure, in the provider's own words, such as `rate_limit_exceeded`.
    public let errorCode: String?

    /// The company whose servers failed, when the provider names one, such as the host OpenRouter sent the request to.
    public let provider: String?

    /// The provider's id for the request that failed, which its support asks for.
    public let requestID: String?

    /// The facts in an error's metadata.
    init(_ metadata: [String: any Sendable]) {
        status = metadata[LanguageModelMetadataKey.status] as? Int
        errorCode = metadata[LanguageModelMetadataKey.errorCode] as? String
        provider = metadata[LanguageModelMetadataKey.provider] as? String
        requestID = metadata[LanguageModelMetadataKey.requestID] as? String
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

    /// A failure's shared metadata: its HTTP status, the provider's code for it and the company that failed, each
    /// when known.
    package static func failureMetadata(status: Int?, code: String?, provider: String?) -> [String: any Sendable] {
        var metadata: [String: any Sendable] = [:]
        metadata[LanguageModelMetadataKey.status] = status
        metadata[LanguageModelMetadataKey.errorCode] = code
        metadata[LanguageModelMetadataKey.provider] = provider
        return metadata
    }
}

// MARK: - Reading

/// Typed reads of an entry's or usage's metadata, or of a structure in it. A read is `nil`, or a list empty, when the
/// key is missing or its value is of another kind.
package struct MetadataValues {
    private let values: [String: GeneratedContent]

    package init(_ values: [String: GeneratedContent]) {
        self.values = values
    }

    /// The properties of a structure, or `nil` when the content isn't one.
    package init?(_ content: GeneratedContent) {
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

    /// An amount as the decimal number its shortest spelling names, so `0.000012345` reads as exactly that rather than
    /// the binary fraction nearest to it, `0.000012344999999999997952`.
    package func decimal(_ key: String) -> Decimal? {
        // A nil locale always reads `.` as the decimal separator; Double's description is never localized.
        number(key).flatMap { $0.isFinite ? Decimal(string: String($0), locale: nil) : nil }
    }

    /// A number of seconds as a duration, rounded to the nanosecond, so `2.016` is exactly 2,016 milliseconds.
    package func duration(_ key: String) -> Duration? {
        number(key).flatMap { Int64(exactly: ($0 * 1e9).rounded()) }.map { .nanoseconds($0) }
    }

    /// The elements of a list.
    package func array(_ key: String) -> [GeneratedContent] {
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

// MARK: - Keys

/// The keys of the metadata facts that every provider module reports the same way, on the entries of an answer and on
/// the errors it ends in.
///
/// The response or tool-calls entry that ends an answer carries facts about it, such as the model that answered and
/// why it ended, and the answer's usage carries what it cost. A `LanguageModelError` a provider's failure becomes
/// carries the HTTP status and the provider's code for it. Each provider module writes these keys with the meaning
/// given here and leaves out a key its service doesn't report, so code that reads them works with any provider's
/// model. A provider module's own facts use keys of its own, with a prefix that names the module, such as `vendor.`.
///
/// Saved transcripts keep the keys, so their spellings never change.
public enum LanguageModelMetadataKey {
    /// The model that answered, in the provider's spelling of its id, which can differ from the one asked for when
    /// the service routes the request or a fallback answers. The answer's reasoning entry carries it too.
    public static let model = "model"

    /// The company whose servers ran the model, such as `Anthropic`, when the service names one. On the metadata of a
    /// `LanguageModelError`, the company that failed.
    public static let provider = "provider"

    /// The service's id for the answer.
    public static let responseID = "responseID"

    /// The service's id for the request that got the answer, which its support asks for. On the metadata of a
    /// `LanguageModelError`, the id of the request that failed.
    public static let requestID = "requestID"

    /// Why the answer ended, as a ``FinishReason`` raw value such as `length` when it reached its token limit.
    public static let finishReason = "finishReason"

    /// The processing tier that served the answer, which it's billed at, in the provider's own word for it.
    public static let serviceTier = "serviceTier"

    /// The web pages the answer cites, on its response entry, each a structure with the page's `url`, and its `title`,
    /// `excerpt`, `startOffset` and `endOffset` when known, which a provider module reads as ``Citation`` values.
    public static let citations = "citations"

    /// What the answer cost, in US dollars, when the service reports it.
    public static let cost = "cost"

    /// The prompt tokens written to the host's prompt cache.
    public static let cacheWriteTokenCount = "cacheWriteTokenCount"

    /// The web searches the service ran for the answer.
    public static let webSearchCount = "webSearchCount"

    /// The HTTP status of the failed request, on the metadata of a `LanguageModelError`, such as 429 for a rate limit.
    public static let status = "status"

    /// The provider's own code for the failure, in its own vocabulary, on the metadata of a `LanguageModelError`.
    public static let errorCode = "errorCode"
}
