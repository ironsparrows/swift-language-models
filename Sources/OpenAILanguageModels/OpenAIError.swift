public import Foundation
import FoundationModels
public import LanguageModels

// MARK: - Error

/// A failure of an OpenAI request that Foundation Models has no error for, such as a rejected API key or no quota left.
///
/// Rate limits, an oversized context, content filters, refusals, timeouts and images OpenAI rejects throw
/// `LanguageModelError` instead, so they're handled the same way as with any other model, and a connection that fails,
/// such as without a network, throws its `URLError`.
public struct OpenAIError: Error, Sendable, Equatable, LocalizedError {
    /// The HTTP status, such as 401 for a rejected key, or `nil` for a failure in the stream, which arrives after the
    /// response's HTTP 200, or when there was no usable response.
    public let status: Int?

    /// What went wrong, as OpenAI said it.
    public let message: String

    /// What kind of failure it was: OpenAI's own code, such as `invalid_api_key`, or when it gives none, its error
    /// type, such as `invalid_request_error`, or the kind its HTTP status stands for, such as `authentication`.
    public let code: Code

    /// OpenAI's error type, such as `invalid_request_error` or `insufficient_quota`, when it names one, whatever the
    /// code.
    public let errorType: Code?

    /// The request setting the failure concerns, such as `model`, when OpenAI names one.
    public let parameter: String?

    /// OpenAI's id for the request, which its support asks for.
    public let requestID: String?

    /// How long to wait before retrying, when OpenAI says.
    public let retryAfter: Duration?

    /// Whether the account, organization or project ran out of quota or credits, or reached its spending limit,
    /// whatever OpenAI's code for it, such as `insufficient_quota` or `credit_balance_exhausted`. Only adding credits
    /// or raising the limit clears it; waiting and retrying don't.
    public let isQuotaExhausted: Bool

    /// Creates an error.
    ///
    /// - Parameters:
    ///   - status: The HTTP status.
    ///   - message: What went wrong.
    ///   - code: What kind of failure it was.
    ///   - errorType: OpenAI's error type, or `nil` when it names none.
    ///   - parameter: The request setting the failure concerns.
    ///   - requestID: OpenAI's id for the request.
    ///   - retryAfter: How long to wait before retrying.
    ///   - isQuotaExhausted: Whether the account, organization or project ran out of quota or credits.
    public init(
        status: Int? = nil,
        message: String,
        code: Code = .unmapped,
        errorType: Code? = nil,
        parameter: String? = nil,
        requestID: String? = nil,
        retryAfter: Duration? = nil,
        isQuotaExhausted: Bool = false
    ) {
        self.status = status
        self.message = message
        self.code = code
        self.errorType = errorType
        self.parameter = parameter
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.isQuotaExhausted = isQuotaExhausted
    }

    /// The message.
    public var errorDescription: String? {
        message
    }
}

// MARK: - Codes

extension OpenAIError {
    /// A kind of failure: one of OpenAI's codes or error types, or one the package reports itself.
    public struct Code: ProviderVocabulary {
        /// The API key is missing, rejected or revoked.
        public static let invalidAPIKey: Self = "invalid_api_key"

        /// The account or project has no quota left. OpenAI has more codes for credits and spending limits that ran
        /// out, which ``OpenAIError/isQuotaExhausted`` covers all of.
        public static let insufficientQuota: Self = "insufficient_quota"

        /// The model doesn't exist, or the key may not use it.
        public static let modelNotFound: Self = "model_not_found"

        /// OpenAI failed while it handled the request.
        public static let serverError: Self = "server_error"

        /// The request isn't valid.
        public static let invalidRequest: Self = "invalid_request_error"

        /// The package's code for an HTTP 401 without a code of OpenAI's: the request didn't authenticate.
        public static let authentication: Self = "authentication"

        /// The package's code for an HTTP 403 without a code of OpenAI's: the key may not do this, such as from an
        /// unsupported region.
        public static let permissionDenied: Self = "permission_denied"

        /// The package's code for an HTTP 404 without a code of OpenAI's: what the request names doesn't exist.
        public static let notFound: Self = "not_found"

        /// The package's code for an HTTP 409 without a code of OpenAI's: the request conflicts with another.
        public static let conflict: Self = "conflict"

        /// The package's code for an HTTP 422 without a code of OpenAI's: the request is well formed but can't be
        /// handled.
        public static let unprocessable: Self = "unprocessable"

        /// The package's code for an HTTP 5xx, or a failure in the stream, without a code of OpenAI's: OpenAI failed or
        /// is overloaded.
        public static let server: Self = "server"

        /// The package's code for a response it couldn't use, such as a stream cut off before its end.
        public static let invalidResponse: Self = "invalid_response"

        /// A failure that neither OpenAI's code nor the HTTP status classifies.
        public static let unmapped: Self = "unmapped"

        /// The code's name.
        public let rawValue: String

        /// Creates a code from its name.
        ///
        /// - Parameter rawValue: The name, such as `"invalid_api_key"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

// MARK: - What a failure becomes

/// A failure OpenAI reported, before it becomes the error a session throws.
///
/// Failures Foundation Models has a case for throw `LanguageModelError`, so apps handle them the same way for every
/// model. The rest throw `OpenAIError`.
struct OpenAIFailure: Sendable {
    /// The HTTP status, or `nil` for a failure in the stream, which arrives after the response's HTTP 200.
    let status: Int?

    /// The `error` object, or `nil` when the response had none, such as a gateway's HTML page or a failed response
    /// without one.
    let body: APIErrorBody?

    /// OpenAI's id for the request.
    let requestID: String?

    /// How long OpenAI asks to wait, from the `retry-after-ms` or `Retry-After` header.
    let retryAfter: Duration?

    /// The time until the rate limits reset, which a rate limit's reset date falls back to.
    let rateLimitReset: Duration?

    /// A failed response.
    init(_ rejected: RequestFailure<APIErrorBody>) {
        status = rejected.status
        body = rejected.body
        requestID = rejected.header(API.Header.requestID)
        retryAfter = rejected.retryAfter
        rateLimitReset = Self.rateLimitReset(rejected.header)
    }

    /// A failure in the stream: an `error` event, or a failed response with its `error` object if it has one.
    init(streamError body: APIErrorBody?, requestID: String?) {
        status = nil
        var body = body
        // An `error` event that carries the error in its own members has the event's `type`, which isn't an error type.
        if body?.type == Self.errorEventType { body?.type = nil }
        self.body = body
        self.requestID = requestID
        retryAfter = nil
        rateLimitReset = nil
    }

    /// The error to throw.
    ///
    /// - Parameters:
    ///   - contextSize: The model's context size, for an oversized prompt whose message doesn't name it.
    ///   - imageEntries: The request's entries that carry an image, which an error for an image OpenAI rejects names.
    ///   - now: The time a rate limit's reset date counts from.
    /// - Returns: `LanguageModelError` when Foundation Models has a case for the failure, otherwise `OpenAIError`.
    func error(contextSize: Int?, imageEntries: [Transcript.Entry] = [], now: Date = .now) -> any Error {
        guard let failure = providerFailure(contextSize: contextSize, imageEntries: imageEntries, now: now) else {
            return OpenAIError(
                status: status, message: message, code: code, errorType: body?.type.map(OpenAIError.Code.init(rawValue:)),
                parameter: body?.param, requestID: requestID, retryAfter: retryAfter, isQuotaExhausted: isQuotaExhausted)
        }
        let metadata = ProviderErrorMetadata(status: status, code: code.rawValue, requestID: requestID).contextMetadata
        return LanguageModelError(failure, message: message, metadata: metadata)
    }

    /// What went wrong: OpenAI's message, or the status's own text when there's none.
    private var message: String {
        body?.message ?? status.map(HTTPURLResponse.localizedString(forStatusCode:)) ?? "The model's response ended in an error."
    }

    /// OpenAI's code, as text.
    private var errorCode: String? {
        switch body?.code {
        case .string(let code)?: code
        case .integer(let code)?: String(code)
        default: nil
        }
    }

    /// The kind of failure: OpenAI's code, then its error type, then the kind the HTTP status stands for, and `server`
    /// for a failure in the stream that names none.
    private var code: OpenAIError.Code {
        if let code = errorCode ?? body?.type { return OpenAIError.Code(rawValue: code) }
        switch status {
        case 401?: return .authentication
        case 403?: return .permissionDenied
        case 404?: return .notFound
        case 409?: return .conflict
        case 422?: return .unprocessable
        case let status? where status >= 500: return .server
        case nil: return .server
        default: return .unmapped
        }
    }

    /// Whether the failure is a quota, credit or spending limit that ran out, by OpenAI's error type or code.
    private var isQuotaExhausted: Bool {
        body?.type == Self.insufficientQuota || errorCode.map(Self.quotaCodes.contains) == true
    }

    /// The `LanguageModelError` case the failure becomes, or `nil` when it becomes an `OpenAIError`. A quota that ran out
    /// stays OpenAI's, since waiting doesn't clear it, although it arrives as a 429.
    private func providerFailure(contextSize: Int?, imageEntries: [Transcript.Entry], now: Date) -> LanguageModelError.ProviderFailure? {
        let code = errorCode
        if isQuotaExhausted { return nil }
        if code == "context_length_exceeded" || (status == 400 && LanguageModelError.ProviderFailure.namesContext(message)) {
            return .contextSizeExceeded(message: message, contextSize: contextSize)
        }
        if status == 429 || code == "rate_limit_exceeded" {
            return .rateLimited(resetDate: LanguageModelError.ProviderFailure.resetDate(after: retryAfter ?? rateLimitReset, from: now))
        }
        if code.map(Self.guardrailCodes.contains) == true || (code == "invalid_prompt" && message.contains(Self.policyMessage)) {
            return .guardrailViolation
        }
        if code.map(Self.unsupportedImageCodes.contains) == true { return .unsupportedContent(imageEntries) }
        if status == 408 || status == 504 || code == "vector_store_timeout" { return .timeout }
        return nil
    }

    /// The time until the rate limits reset that a 429's headers name, the later of the requests' and the tokens'.
    private static func rateLimitReset(_ header: (String) -> String?) -> Duration? {
        [API.Header.rateLimitResetRequests, API.Header.rateLimitResetTokens]
            .compactMap { header($0).flatMap(Duration.init(resetInterval:)) }.max()
    }

    /// The `type` of an `error` event.
    private static let errorEventType = "error"

    /// The error type of a quota or credit that ran out.
    private static let insufficientQuota = OpenAIError.Code.insufficientQuota.rawValue

    /// The codes of a quota, credit or spending limit that ran out.
    private static let quotaCodes: Set<String> = [
        insufficientQuota, "credit_balance_exhausted", "organization_spend_limit_exceeded", "project_spend_limit_exceeded",
        "organization_usage_limit_exceeded",
    ]

    /// The codes of a request or answer a safety system stopped.
    private static let guardrailCodes: Set<String> = [
        "content_policy_violation", "bio_policy", "misalignment_policy_violation", "image_content_policy_violation",
    ]

    /// The codes of an image OpenAI can't use. One it couldn't download stays OpenAI's error.
    private static let unsupportedImageCodes: Set<String> = [
        "invalid_image", "invalid_image_format", "invalid_base64_image", "invalid_image_url", "image_too_large", "image_too_small",
        "image_parse_error", "invalid_image_mode", "image_file_too_large", "unsupported_image_media_type", "empty_image_file",
    ]

    /// The message of a prompt flagged for the usage policies.
    private static var policyMessage: Regex<Substring> { /(?i)usage polic|flagged/ }
}

extension Duration {
    /// The time in a rate limit's reset header, such as `1s`, `6m0s` or `20ms`.
    fileprivate init?(resetInterval text: String) {
        let parts = text.matches(of: /(\d+(?:\.\d+)?)(ms|s|m|h)/)
        guard !parts.isEmpty, parts.map({ String($0.0) }).joined() == text else { return nil }
        let seconds = parts.reduce(0.0) { total, part in
            let value = Double(part.1) ?? 0
            return total + value * (part.2 == "ms" ? 0.001 : part.2 == "m" ? 60 : part.2 == "h" ? 3_600 : 1)
        }
        self = .milliseconds(Int64((seconds * 1_000).rounded()))
    }
}

// MARK: - Logging

extension OpenAIError: LoggableError {
    package var logFields: (kind: String, status: Int?, code: String?, host: String?) {
        ("OpenAIError", status, code.rawValue, nil)
    }
}
