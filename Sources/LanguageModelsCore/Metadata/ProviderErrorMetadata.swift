public import FoundationModels

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
