public import Foundation
import FoundationModels
public import LanguageModels

// MARK: - Error

/// A failure of an OpenRouter request that Foundation Models has no error for, such as a rejected API key or no
/// credits left.
///
/// Rate limits, an oversized context, content filters, refusals, timeouts and attachments a host rejects throw
/// `LanguageModelError` instead, so they're handled the same way as with any other model, and a connection that fails,
/// such as without a network, throws its `URLError`.
public struct OpenRouterError: Error, Sendable, Equatable, LocalizedError {
    /// The HTTP status, such as 401 for a rejected key or 402 for no credits, or for an error in the stream, the status
    /// its code names. `nil` when there was no response, the response wasn't usable, or an error in the stream has a
    /// code that isn't a number.
    public let status: Int?

    /// What went wrong: the model host's own message when it gave one, otherwise OpenRouter's.
    public let message: String

    /// What kind of failure it was, such as `authentication` or `paymentRequired`: OpenRouter's error type, or when
    /// the response doesn't name one, the type its HTTP status stands for, then the host's own code, such as
    /// `server_error`. When none of them says, `server` for an error in the stream and `unmapped` otherwise.
    public let code: Code

    /// The host that failed, such as `Anthropic`, when OpenRouter names one.
    ///
    /// OpenRouter calls the hosts that serve its models providers, and the name keeps OpenRouter's word: it names the
    /// host, never OpenRouter itself.
    public let providerName: OpenRouterProviderName?

    /// How long to wait before retrying, when OpenRouter says.
    public let retryAfter: Duration?

    /// Creates an error.
    ///
    /// - Parameters:
    ///   - status: The HTTP status.
    ///   - message: What went wrong.
    ///   - code: What kind of failure it was.
    ///   - providerName: The host that failed.
    ///   - retryAfter: How long to wait before retrying.
    public init(
        status: Int? = nil,
        message: String,
        code: Code = .unmapped,
        providerName: OpenRouterProviderName? = nil,
        retryAfter: Duration? = nil
    ) {
        self.status = status
        self.message = message
        self.code = code
        self.providerName = providerName
        self.retryAfter = retryAfter
    }

    /// The message, after the host's name when there is one.
    public var errorDescription: String? {
        providerName.map { "[\($0.rawValue)] \(message)" } ?? message
    }

    /// Whether the account ran out of credits or the key reached a spending limit that never resets, as
    /// ``Code/paymentRequired`` and ``Code/budgetExceeded`` say. Only adding credits or raising the limit clears it;
    /// waiting and retrying don't. A budget that resets throws `LanguageModelError.rateLimited` instead.
    public var isQuotaExhausted: Bool {
        code == .paymentRequired || code == .budgetExceeded
    }
}

// MARK: - Codes

extension OpenRouterError {
    /// A kind of failure: one of OpenRouter's error types, or one the package reports itself.
    public struct Code: ProviderVocabulary {
        /// The API key is missing or rejected.
        public static let authentication: Self = "authentication"

        /// The key may not do this, such as use a model it's limited from.
        public static let permissionDenied: Self = "permission_denied"

        /// The account has no credits left, or the key reached its limit.
        public static let paymentRequired: Self = "payment_required"

        /// A token budget that OpenRouter enforces ran out, such as a cap that the account's credits set.
        public static let tokenLimitExceeded: Self = "token_limit_exceeded"

        /// The request asked for more output tokens than the model allows.
        public static let maxTokensExceeded: Self = "max_tokens_exceeded"

        /// A text in the request is longer than the host allows.
        public static let stringTooLong: Self = "string_too_long"

        /// The host is overloaded.
        public static let providerOverloaded: Self = "provider_overloaded"

        /// No host can serve the model now.
        public static let providerUnavailable: Self = "provider_unavailable"

        /// The request isn't valid.
        public static let invalidRequest: Self = "invalid_request"

        /// The prompt isn't valid for the model.
        public static let invalidPrompt: Self = "invalid_prompt"

        /// The model or another resource doesn't exist.
        public static let notFound: Self = "not_found"

        /// A precondition of the request isn't met.
        public static let preconditionFailed: Self = "precondition_failed"

        /// The request is too large.
        public static let payloadTooLarge: Self = "payload_too_large"

        /// The request is well formed but can't be processed.
        public static let unprocessable: Self = "unprocessable"

        /// An image in the request isn't valid.
        public static let invalidImage: Self = "invalid_image"

        /// An image is larger than the host allows.
        public static let imageTooLarge: Self = "image_too_large"

        /// An image is smaller than the host allows.
        public static let imageTooSmall: Self = "image_too_small"

        /// An image's format isn't supported.
        public static let unsupportedImageFormat: Self = "unsupported_image_format"

        /// An image URL leads nowhere.
        public static let imageNotFound: Self = "image_not_found"

        /// An image URL couldn't be downloaded.
        public static let imageDownloadFailed: Self = "image_download_failed"

        /// OpenRouter or the host failed.
        public static let server: Self = "server"

        /// A failure that neither OpenRouter's error type nor the HTTP status classifies.
        public static let unmapped: Self = "unmapped"

        /// The package's own code for a request that ran into a spending budget that never resets, such as a key's
        /// lifetime limit. A budget that resets throws `LanguageModelError.rateLimited` instead, with its reset date.
        public static let budgetExceeded: Self = "budget_exceeded"

        /// The package's own code for a response it couldn't use, such as a stream cut off before its end.
        public static let invalidResponse: Self = "invalid_response"

        /// The code's name, as OpenRouter's `error_type` spells it.
        public let rawValue: String

        /// Creates a code from its name.
        ///
        /// - Parameter rawValue: The name, such as `"authentication"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

// MARK: - Response body

/// The `error` object OpenRouter sends in a failed response's body, or in a stream event with HTTP 200.
struct OpenRouterErrorResponse: Decodable, Sendable {
    /// The HTTP status as a number, or a provider's code as text.
    var code: JSONValue? = nil
    let message: String
    var metadata: JSONValue? = nil

    /// OpenRouter's kind of error, such as `context_length_exceeded`, or `nil` when the body doesn't name one.
    fileprivate var errorType: OpenRouterError.Code? { metadata?["error_type"]?.stringValue.map(OpenRouterError.Code.init(rawValue:)) }

    /// The host that failed, such as `Anthropic`.
    fileprivate var providerName: OpenRouterProviderName? {
        metadata?["provider_name"]?.stringValue.map(OpenRouterProviderName.init(rawValue:))
    }

    /// Whether a 402 means too many requests are in flight at once, rather than no credits.
    fileprivate var isInFlightBudget: Bool { limitSource == .inFlightBudget }

    /// The budget or limit the request ran into, such as a key's spending budget, when the body names one.
    fileprivate var limitSource: OpenRouterErrorMetadata.LimitSource? {
        metadata?["limit_source"]?.stringValue.map(OpenRouterErrorMetadata.LimitSource.init(rawValue:))
    }

    /// When a spending budget's window rolls over and its spend returns to zero, or `nil` for a lifetime budget.
    fileprivate var budgetResetDate: Date? {
        guard let text = metadata?["resets_at"]?.stringValue else { return nil }
        return (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: .iso8601))
    }

    /// Whether a 403 comes from OpenRouter's moderation or a guardrail, which name what they flagged, rather than from
    /// the key's permissions.
    fileprivate var isModeration: Bool { ["reasons", "flagged_input", "patterns"].contains { metadata?[$0] != nil } }

    /// The status the code names, when it's a number.
    fileprivate var status: Int? {
        switch code {
        case .integer(let status)?: status
        case .string(let text)?: Int(text)
        default: nil
        }
    }

    /// The code, when it's text rather than a number, such as a host's `server_error`.
    fileprivate var textCode: String? {
        guard case .string(let text)? = code, Int(text) == nil, !text.isEmpty else { return nil }
        return text
    }

    /// The host's own message when it gave one, since OpenRouter's is often only "Provider returned error".
    fileprivate var bestMessage: String {
        Self.message(in: metadata?["raw"]) ?? message
    }

    /// A message in a host's raw error: a string, a string of JSON, or an object with a message field.
    private static func message(in raw: JSONValue?) -> String? {
        switch raw {
        case .string(let text)?:
            guard let json = try? JSONValue(json: Data(text.utf8)), case .object = json else { return text.isEmpty ? nil : text }
            return message(in: json)
        case .object?:
            for field in ["message", "error", "detail", "details", "msg"] {
                if let found = message(in: raw?[field]) { return found }
            }
            return nil
        default:
            return nil
        }
    }
}

extension OpenRouterFailure {
    /// What a failed response reports beside its `error` object.
    private struct ResponseExtras: Decodable {
        let routerMetadata: OpenRouterChunkExtras.RouterMetadata?

        private enum CodingKeys: String, CodingKey {
            case routerMetadata = "openrouter_metadata"
        }
    }
}

// MARK: - What a failure becomes

/// A failure OpenRouter reported, before it becomes the error a session throws.
///
/// Failures Foundation Models has a case for throw `LanguageModelError`, so apps handle them the same way for every
/// model. The rest throw `OpenRouterError`.
struct OpenRouterFailure: Sendable {
    /// The HTTP status, or for an error in a stream, which arrives with HTTP 200, the status its code names, if the
    /// code is a number.
    let status: Int?
    /// The `error` object, or one with the status's own text when the response had none, such as a gateway's HTML
    /// page.
    let body: OpenRouterErrorResponse
    /// How long OpenRouter asks to wait, from the `Retry-After` or `X-RateLimit-Reset` header.
    let retryAfter: Duration?
    /// The kind of failure.
    let code: OpenRouterError.Code
    /// The host that failed: the one the body names, or for an error in a stream, the one its chunk names.
    let providerName: OpenRouterProviderName?
    /// Whether the router's report says a guardrail blocked the request.
    let isGuardrailBlock: Bool

    /// A failed response.
    ///
    /// - Parameters:
    ///   - status: The response's HTTP status.
    ///   - body: Its error, or `nil` when the body wasn't OpenRouter's JSON, such as a gateway's HTML page; the
    ///     status's own text stands in for it.
    ///   - retryAfter: How long the response asks to wait.
    ///   - routerReport: The router's report beside the error.
    init(
        status: Int, body: OpenRouterErrorResponse?, retryAfter: Duration?, routerReport: OpenRouterChunkExtras.RouterMetadata? = nil
    ) {
        let body = body ?? OpenRouterErrorResponse(message: HTTPURLResponse.localizedString(forStatusCode: status))
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
        code = Self.code(of: body, status: status) ?? .unmapped
        providerName = body.providerName
        isGuardrailBlock = routerReport?.isGuardrailBlock == true
    }

    /// A failed response, with the delay its `Retry-After` or `X-RateLimit-Reset` header asks for.
    init(_ rejected: RequestFailure<OpenRouterErrorResponse>) {
        self.init(
            status: rejected.status ?? 0,
            body: rejected.body,
            retryAfter: rejected.retryAfter ?? Duration(rateLimitReset: rejected.header(API.Header.rateLimitReset)),
            routerReport: (try? JSONDecoder().decode(ResponseExtras.self, from: rejected.rawBody))?.routerMetadata
        )
    }

    /// An error event in a stream, which arrives after the response's HTTP 200.
    ///
    /// An error that names neither an error type nor a code is the host failing while it generates, so its code is
    /// `server`.
    ///
    /// - Parameters:
    ///   - body: The event's error.
    ///   - provider: The host the event's chunk names.
    init(streamError body: OpenRouterErrorResponse, provider: OpenRouterProviderName?) {
        status = body.status
        self.body = body
        retryAfter = nil
        code = Self.code(of: body, status: body.status) ?? .server
        providerName = body.providerName ?? provider
        isGuardrailBlock = false
    }

    /// The error to throw.
    ///
    /// - Parameters:
    ///   - contextSize: The model's context size, for an oversized prompt.
    ///   - imageEntries: The request's entries that carry an image, which an error for an image the host rejects names.
    ///   - now: The time a rate limit's reset date counts from.
    /// - Returns: `LanguageModelError` when Foundation Models has a case for the failure, otherwise `OpenRouterError`.
    func error(contextSize: Int?, imageEntries: [Transcript.Entry] = [], now: Date = .now) -> any Error {
        let message = body.bestMessage
        let metadata = self.metadata
        let failure: LanguageModelError.ProviderFailure
        switch kind {
        case .contextSizeExceeded:
            let sizes = LanguageModelError.ProviderFailure.contextSizes(in: message)
            failure = .contextSizeExceeded(contextSize: sizes.limit ?? contextSize ?? 0, tokenCount: sizes.requested ?? 0)
        case .rateLimited:
            failure = .rateLimited(resetDate: body.budgetResetDate ?? retryAfter.map { now.addingTimeInterval($0 / .seconds(1)) })
        case .guardrailViolation:
            failure = .guardrailViolation
        case .refusal:
            failure = .refusal
        case .timeout:
            failure = .timeout
        case .unsupportedImage:
            failure = .unsupportedContent(imageEntries)
        case .openRouterError:
            return OpenRouterError(status: status, message: message, code: code, providerName: providerName, retryAfter: retryAfter)
        }
        return LanguageModelError(failure, message: message, metadata: metadata)
    }

    /// What the failure becomes: the `LanguageModelError` case for its code, or for a 402 or 403 that the response shows
    /// to be a rate limit, a moderation flag or a guardrail's block, otherwise an `OpenRouterError`. A status that stands
    /// for one of these cases already gave the failure its code.
    private var kind: Kind {
        switch (code, status) {
        case (.contextLengthExceeded, _): .contextSizeExceeded
        case (.rateLimitExceeded, _): .rateLimited
        case (.contentPolicyViolation, _): .guardrailViolation
        case (.refusal, _): .refusal
        case (.timeout, _): .timeout
        // The host can't use an image, as for one the package can't send; one it can't download stays OpenRouter's.
        case (.unsupportedImageFormat, _), (.invalidImage, _), (.imageTooLarge, _), (.imageTooSmall, _): .unsupportedImage
        // Too much is in flight at once; it clears as requests finish, like a rate limit.
        case (_, 402?) where body.isInFlightBudget: .rateLimited
        // A spending budget that resets clears at its reset date, like a rate limit.
        case (.budgetExceeded, _) where body.budgetResetDate != nil: .rateLimited
        case (_, 403?) where body.isModeration || isGuardrailBlock: .guardrailViolation
        default: .openRouterError
        }
    }

    /// The metadata of a `LanguageModelError`: the status, the code, the host that failed and the budget it ran into.
    private var metadata: [String: any Sendable] {
        OpenRouterErrorMetadata.metadata(status: status, code: code, provider: providerName, limitSource: body.limitSource)
    }

    /// The kind of failure: the error type the body names, then the type its status stands for, then the code the body
    /// names as text, such as a host's `server_error`. A 400 whose message names the context's length or window is an
    /// oversized prompt, which OpenRouter rejects itself before any host sees it.
    ///
    /// - Returns: The code, or `nil` when neither the body nor the status names one.
    private static func code(of body: OpenRouterErrorResponse, status: Int?) -> OpenRouterError.Code? {
        if let type = body.errorType { return type }
        if status == 400, body.bestMessage.contains(/(?i)context (length|window)/) { return .contextLengthExceeded }
        if status == 403, body.limitSource != nil { return .budgetExceeded }
        if let status, let code = codesByStatus[status] { return code }
        return body.textCode.map(OpenRouterError.Code.init(rawValue:))
    }

    /// The error type each status stands for, for a body that doesn't name one. OpenRouter's own 502 and 503 mean no
    /// host could serve the request, a 504 or 524 is a gateway that timed out, and a 529 is an overloaded host.
    private static let codesByStatus: [Int: OpenRouterError.Code] = [
        400: .invalidRequest,
        401: .authentication,
        402: .paymentRequired,
        403: .permissionDenied,
        404: .notFound,
        408: .timeout,
        412: .preconditionFailed,
        413: .payloadTooLarge,
        422: .unprocessable,
        429: .rateLimitExceeded,
        500: .server,
        502: .providerUnavailable,
        503: .providerUnavailable,
        504: .timeout,
        524: .timeout,
        529: .providerOverloaded,
    ]
}

extension OpenRouterError.Code {
    // OpenRouter's error types that become `LanguageModelError`, so they never reach an `OpenRouterError`.
    fileprivate static let contextLengthExceeded: Self = "context_length_exceeded"
    fileprivate static let rateLimitExceeded: Self = "rate_limit_exceeded"
    fileprivate static let contentPolicyViolation: Self = "content_policy_violation"
    fileprivate static let refusal: Self = "refusal"
    fileprivate static let timeout: Self = "timeout"
}

extension OpenRouterFailure {
    /// What a failure becomes: the `LanguageModelError` case of the same name, or an `OpenRouterError`.
    private enum Kind {
        case contextSizeExceeded
        case rateLimited
        case guardrailViolation
        case refusal
        case timeout
        case unsupportedImage
        case openRouterError
    }
}

// MARK: - Logging

extension OpenRouterError: LoggableError {
    package var logFields: (kind: String, status: Int?, code: String?, host: String?) {
        ("OpenRouterError", status, code.rawValue, providerName?.rawValue)
    }
}
