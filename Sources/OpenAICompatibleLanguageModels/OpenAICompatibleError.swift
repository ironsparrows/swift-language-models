public import Foundation
import FoundationModels
public import LanguageModels

// MARK: - Error

/// A failure of a request to a provider that speaks OpenAI's formats that Foundation Models has no error for, such as a
/// rejected API key, a model the provider doesn't have, or a setting it rejects.
///
/// Rate limits, an oversized context, content filters, timeouts and images the provider can't use throw
/// `LanguageModelError` instead, so they're handled the same way as with any other model, and a connection that fails,
/// such as to a local server that isn't running, throws its `URLError`.
public struct OpenAICompatibleError: Error, Sendable, Equatable, LocalizedError {
    /// The name of the provider that failed, as ``OpenAICompatibleProvider/name`` gives it.
    public let providerName: String

    /// The HTTP status, such as 401 for a rejected key, or for an error in the stream, which arrives after the
    /// response's HTTP 200, the status its error names. `nil` when there was no usable response, or an error in the
    /// stream names none.
    public let status: Int?

    /// What went wrong: the message of the provider's error, or its error's own text when it carries no message, or
    /// when the response holds no error the module reads, up to 1,000 characters of the response's text, or its status,
    /// content type and size when it's empty or HTML. For a response the format couldn't use, such as a stream cut off
    /// before its end, it's the format's own sentence.
    public let message: String

    /// What kind of failure it was: the provider's code, such as `invalid_api_key`, or when it gives none, the kind its
    /// HTTP status stands for, such as `authentication`, or for a status with no kind of its own, such as a 400, the
    /// provider's error type, such as `invalid_request_error`. A 400 whose message says, in a preset's provider's words,
    /// that the API key is missing or refused is `authentication`, as a 401 is.
    public let code: Code

    /// The provider's error type, such as `invalid_request_error`, or its status word, such as `INVALID_ARGUMENT`,
    /// when it names one, whatever the code.
    public let errorType: Code?

    /// The request member the failure concerns, such as `stream_options`, when the provider's error names one or its
    /// message quotes one, as in `Unknown name "top_k"`.
    public let parameter: String?

    /// The provider's id for the request, from the header it sends one in, such as `x-request-id`, which its support
    /// asks for.
    public let requestID: String?

    /// How long to wait before retrying, when the provider says.
    public let retryAfter: Duration?

    /// Whether the account ran out of quota, credits or balance, as an HTTP 402 or the code `insufficient_quota` says.
    /// Only adding credits or raising the limit clears it; waiting and retrying don't.
    public let isQuotaExhausted: Bool

    /// Creates an error.
    ///
    /// - Parameters:
    ///   - providerName: The name of the provider that failed.
    ///   - status: The HTTP status.
    ///   - message: What went wrong.
    ///   - code: What kind of failure it was.
    ///   - errorType: The provider's error type, or `nil` when it names none.
    ///   - parameter: The request member the failure concerns.
    ///   - requestID: The provider's id for the request.
    ///   - retryAfter: How long to wait before retrying.
    ///   - isQuotaExhausted: Whether the account ran out of quota, credits or balance.
    public init(
        providerName: String,
        status: Int? = nil,
        message: String,
        code: Code = .unmapped,
        errorType: Code? = nil,
        parameter: String? = nil,
        requestID: String? = nil,
        retryAfter: Duration? = nil,
        isQuotaExhausted: Bool = false
    ) {
        self.providerName = providerName
        self.status = status
        self.message = message
        self.code = code
        self.errorType = errorType
        self.parameter = parameter
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.isQuotaExhausted = isQuotaExhausted
    }

    /// The message, after the provider's name.
    public var errorDescription: String? {
        "[\(providerName)] \(message)"
    }
}

// MARK: - Codes

extension OpenAICompatibleError {
    /// A kind of failure: one of the provider's codes or error types, or one the package reports itself.
    ///
    /// Codes are an open vocabulary: whatever a provider sends reads, with or without a static member.
    public struct Code: ProviderVocabulary {
        /// The API key is missing, rejected or revoked, as OpenAI's API and many that follow it say.
        public static let invalidAPIKey: Self = "invalid_api_key"

        /// The account has no quota left, as OpenAI's API and many that follow it say.
        public static let insufficientQuota: Self = "insufficient_quota"

        /// The model doesn't exist, or the key may not use it, as OpenAI's API and many that follow it say.
        public static let modelNotFound: Self = "model_not_found"

        /// The request isn't valid, as OpenAI's API and many that follow it say.
        public static let invalidRequest: Self = "invalid_request_error"

        /// The provider failed while it handled the request, as OpenAI's API and many that follow it say.
        public static let serverError: Self = "server_error"

        /// The package's code for an HTTP 401 without a code of the provider's: the request didn't authenticate.
        public static let authentication: Self = "authentication"

        /// The package's code for an HTTP 402 without a code of the provider's: the account has no credits or balance
        /// left.
        public static let paymentRequired: Self = "payment_required"

        /// The package's code for an HTTP 403 without a code of the provider's: the key may not do this.
        public static let permissionDenied: Self = "permission_denied"

        /// The package's code for an HTTP 404 without a code of the provider's: what the request names doesn't exist,
        /// such as the model, or the format's path under the provider's URL.
        public static let notFound: Self = "not_found"

        /// The package's code for an HTTP 409 without a code of the provider's: the request conflicts with another.
        public static let conflict: Self = "conflict"

        /// The package's code for an HTTP 422 without a code of the provider's: the request is well formed but can't
        /// be handled, such as a member the provider doesn't take.
        public static let unprocessable: Self = "unprocessable"

        /// The package's code for an HTTP 5xx, or a failure in the stream, without a code of the provider's: the
        /// provider failed or is overloaded.
        public static let server: Self = "server"

        /// The package's code for a response it couldn't use, such as a stream cut off before its end.
        public static let invalidResponse: Self = "invalid_response"

        /// A failure that neither the provider's code nor the HTTP status classifies.
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

// MARK: - Response body

/// A provider's error, read from whichever of the shapes providers send it in: OpenAI's `{"error": {"message", "type",
/// "code", "param"}}`, the same inside a JSON array, the error's members at the top of the body, `{"error": "text"}`,
/// `{"code", "error": "text"}`, a `message` that holds an error itself, or a `detail` list of what the request's
/// validation found, each with its `msg` and the `loc` of the member it concerns. An error that names a code, a type
/// or a member without a message has its own text, up to 1,000 characters, as its message.
///
/// An error that names no member takes the one its message quotes, in the forms providers quote one in, such as
/// `Unknown name "top_k"` or `property 'top_k' is unsupported`. The wait a `google.rpc.RetryInfo` in its `details`
/// names, and the `failed_generation` of a guided answer that broke its schema, are read too.
///
/// Reading one fails when it holds neither a message nor a code, a type or a member, so an error event's own text
/// becomes its message instead.
struct OpenAICompatibleErrorBody: Decodable, Sendable {
    /// What went wrong.
    let message: String

    /// The provider's error type, such as `invalid_request_error`, or its status word, such as `INVALID_ARGUMENT`.
    let type: String?

    /// The provider's code when it's a word, such as `invalid_api_key`.
    let code: String?

    /// The HTTP status the error names, from 400 to 599: its `code`, or else its `status_code` or `status`, when that's
    /// a number.
    let status: Int?

    /// The request member the error concerns, such as `top_k`.
    let parameter: String?

    /// How long to wait before retrying, as the error's `details` say in a `google.rpc.RetryInfo`.
    let retryDelay: Duration?

    /// What the model generated before its guided answer broke the schema, when the error says.
    let failedGeneration: String?

    init(from decoder: any Decoder) throws {
        guard let body = Self(try JSONValue(from: decoder)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No member holds an error."))
        }
        self = body
    }

    /// The error in a JSON value, or `nil` when it holds neither a message nor a code, a type or a member.
    init?(_ json: JSONValue) {
        switch json {
        case .string(let text):
            guard !text.isEmpty else { return nil }
            self.init(message: text, type: nil, code: nil, status: nil, parameter: Self.quotedMember(in: text))
        case .array(let elements):
            guard let body = elements.lazy.compactMap(Self.init).first else { return nil }
            self = body
        case .object(let members):
            self.init(members)
        default:
            return nil
        }
    }

    private init(
        message: String, type: String?, code: String?, status: Int?, parameter: String?, retryDelay: Duration? = nil,
        failedGeneration: String? = nil
    ) {
        self.message = message
        self.type = type
        self.code = code
        self.status = status
        self.parameter = parameter
        self.retryDelay = retryDelay
        self.failedGeneration = failedGeneration
    }

    /// The error in an object: the object its `error` member holds, or its own members, with its message in an `error`
    /// text, in a `message`, which can be an error object itself, or in a `detail`.
    private init?(_ members: JSONObject) {
        if case .object(let nested)? = members["error"], let body = Self(nested) {
            self = body
            return
        }
        // A `type` or `status` of `error` names an error event, not a kind of error.
        let type = members["type"]?.stringValue.flatMap { $0 == "error" || $0.isEmpty ? nil : $0 }
        let statusWord = members["status"]?.stringValue.flatMap { Int($0) == nil && $0 != "error" && !$0.isEmpty ? $0 : nil }
        let parameter = members["param"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        let codes = Self.codes(members)
        let found: (message: String, type: String?, parameter: String?)
        if let text = members["error"]?.stringValue, !text.isEmpty {
            found = (text, nil, nil)
        } else if case .object(let inner)? = members["message"], let body = Self(inner) {
            found = (body.message, body.type, body.parameter)
        } else if let text = members["message"].flatMap(Self.text(of:)) {
            found = (text, nil, nil)
        } else if let validation = members["detail"].flatMap(Self.validation) {
            found = validation
        } else if codes.word != nil || codes.status != nil || type != nil || parameter != nil {
            // An error that names its kind without a message gives its own text, so its other members still count.
            found = (String(JSONValue.object(members).text.prefix(1_000)), nil, nil)
        } else {
            return nil
        }
        self.init(
            message: found.message, type: type ?? statusWord ?? found.type, code: codes.word, status: codes.status,
            parameter: parameter ?? found.parameter ?? Self.quotedMember(in: found.message),
            retryDelay: members["details"].flatMap(Self.retryDelay(in:)),
            failedGeneration: members["failed_generation"]?.stringValue)
    }

    /// The text of a message that isn't an error object: a string, or any other value's JSON.
    private static func text(of value: JSONValue) -> String? {
        switch value {
        case .null: nil
        case .string(let text): text.isEmpty ? nil : text
        default: value.text
        }
    }

    /// The code as a word, and the status it names: a `code` that's a number from 400 to 599, as text or a number, or
    /// else a `status_code` or a `status` that is. Any other `code` is the word, such as `invalid_api_key` or `3280`.
    private static func codes(_ members: JSONObject) -> (word: String?, status: Int?) {
        func status(_ value: JSONValue?) -> Int? {
            let number: Int? =
                switch value {
                case .integer(let number)?: number
                case .string(let text)?: Int(text)
                default: nil
                }
            return number.flatMap { (400...599).contains($0) ? $0 : nil }
        }
        let code = members["code"]
        let word: String? =
            switch code {
            case .string(let text)? where !text.isEmpty && status(code) == nil: text
            case .integer(let number)? where status(code) == nil: String(number)
            default: nil
            }
        return (word, status(code) ?? status(members["status_code"]) ?? status(members["status"]))
    }

    /// What a `detail` member says: its text, or for a list of what a validation found, each finding's `msg`, with the
    /// type and member of the first, its `loc` without a leading `body`, such as `stream_options` or
    /// `messages.1.content`.
    private static func validation(_ detail: JSONValue) -> (message: String, type: String?, parameter: String?)? {
        if let text = detail.stringValue, !text.isEmpty { return (text, nil, nil) }
        guard case .array(let findings) = detail else { return nil }
        let messages = findings.compactMap { $0["msg"]?.stringValue }
        guard !messages.isEmpty, let first = findings.first else { return nil }
        var location: [String] = []
        if case .array(let parts)? = first["loc"] {
            location = parts.compactMap { part in
                switch part {
                case .string(let text): text
                case .integer(let index): String(index)
                default: nil
                }
            }
            if location.first == "body" { location.removeFirst() }
        }
        return (messages.joined(separator: "; "), first["type"]?.stringValue, location.isEmpty ? nil : location.joined(separator: "."))
    }

    /// The request member a message quotes, in the forms providers quote one in, or `nil` when it quotes none: `Unknown
    /// name "top_k"`, `property 'top_k' is unsupported`, with the message it's in, as in `('messages.1' : property
    /// 'reasoning_content' is unsupported)`, or one that opens the message, as in `` `reasoning_effort` must be one of
    /// ``, `'temperature' : number must be at most 2`, `Invalid reasoning_effort: xhigh` or `temperature must be in the
    /// range`, or one that ends a message that starts with `invalid`, as in `invalid Qwen3.8 reasoning_effort`.
    static func quotedMember(in message: String) -> String? {
        if let match = message.firstMatch(of: /Unknown name "([^"]+)"/) { return String(match.1) }
        if let match = message.firstMatch(of: /\('([^']+)' : property '([^']+)' is unsupported\)/) { return "\(match.1).\(match.2)" }
        if let match = message.firstMatch(of: /property '([^']+)' is unsupported/) { return String(match.1) }
        if let match = message.prefixMatch(of: #/`([a-z_.]+)` /#) { return String(match.1) }
        if let match = message.prefixMatch(of: #/'([a-z_.]+)' : /#) { return String(match.1) }
        if let match = message.prefixMatch(of: #/Invalid ([a-z]+(?:_[a-z]+)+): /#) { return String(match.1) }
        if let match = message.prefixMatch(of: #/([a-z]+(?:_[a-z]+)*) must be /#) { return String(match.1) }
        if let match = message.wholeMatch(of: #/(?i:invalid) .* ([a-z]+(?:_[a-z]+)+)/#) { return String(match.1) }
        return nil
    }

    /// The wait a `google.rpc.RetryInfo` in an error's `details` names, such as `7s`, or `nil` when there's none.
    private static func retryDelay(in details: JSONValue) -> Duration? {
        guard case .array(let entries) = details else { return nil }
        for entry in entries where entry["@type"]?.stringValue?.hasSuffix("google.rpc.RetryInfo") == true {
            guard let delay = entry["retryDelay"]?.stringValue, delay.hasSuffix("s"), let seconds = Double(delay.dropLast()),
                seconds >= 0
            else { continue }
            return .seconds(seconds)
        }
        return nil
    }
}

// MARK: - What a failure becomes

/// A failure a provider reported, before it becomes the error a session throws.
///
/// Failures Foundation Models has a case for throw `LanguageModelError`, so apps handle them the same way for every
/// model, and a guided answer the provider says broke its schema throws `GeneratedContent.ParsingError`. The rest throw
/// `OpenAICompatibleError`.
struct OpenAICompatibleFailure: Sendable {
    /// The name of the provider that failed.
    private let providerName: String

    /// The company that ran the model, when the provider names one.
    private let host: String?

    /// What the provider's own words say a failure is.
    private let words: OpenAICompatibleProvider.FailureWords

    /// The HTTP status, or for an error in the stream, the status its error names.
    private let status: HTTPStatus?

    /// The provider's error, or `nil` when the response carries none the module reads.
    private let body: OpenAICompatibleErrorBody?

    /// What went wrong: the provider's message, or the module's own words for a response without one.
    private let message: String

    /// The provider's id for the request.
    private let requestID: String?

    /// How long the provider asks to wait, from the `retry-after-ms` or `Retry-After` header, or else from its error.
    private let retryAfter: Duration?

    /// A failed response, whose body the error is read from in whichever shape it has.
    ///
    /// - Parameters:
    ///   - rejected: The response.
    ///   - provider: The provider that failed.
    ///   - requestID: The provider's id for the request.
    init(_ rejected: RequestFailure<OpenAICompatibleErrorBody>, provider: OpenAICompatibleProvider, requestID: String?) {
        let status = rejected.status ?? .other(0)
        let body = (try? JSONValue(json: rejected.rawBody)).flatMap(OpenAICompatibleErrorBody.init)
        providerName = provider.name
        host = provider.host
        words = provider.failureWords
        self.status = status
        self.body = body
        message =
            body?.message
            ?? Self.message(describing: rejected.rawBody, status: status, contentType: rejected.header(API.Header.contentType))
        self.requestID = requestID
        retryAfter = rejected.retryAfter ?? body?.retryDelay
    }

    /// A failure in the stream: an error event, or an answer the provider says failed, with its error if it has one.
    ///
    /// - Parameters:
    ///   - body: The provider's error, or `nil` when the failure carries none.
    ///   - message: The format's words for the failure, for one that carries no error.
    ///   - provider: The provider that failed.
    ///   - requestID: The provider's id for the request.
    init(streamError body: OpenAICompatibleErrorBody?, message: String, provider: OpenAICompatibleProvider, requestID: String?) {
        providerName = provider.name
        host = provider.host
        words = provider.failureWords
        status = body?.status.map(HTTPStatus.init(code:))
        self.body = body
        self.message = body?.message ?? message
        self.requestID = requestID
        retryAfter = body?.retryDelay
    }

    /// The error to throw.
    ///
    /// - Parameters:
    ///   - contextSize: The model's context size, for an oversized prompt whose message doesn't name it.
    ///   - imageEntries: The request's entries that carry an image, which an error for an image the provider can't use
    ///     names.
    ///   - now: The time a rate limit's reset date counts from.
    /// - Returns: `LanguageModelError` when Foundation Models has a case for the failure, `GeneratedContent.ParsingError`
    ///   for a guided answer the provider says broke its schema, with what the model generated as its raw content, and
    ///   `OpenAICompatibleError` otherwise.
    func error(contextSize: Int?, imageEntries: [Transcript.Entry] = [], now: Date = .now) -> any Error {
        if let code = body?.code, words.schemaMisses.contains(code) {
            return GeneratedContent.ParsingError(rawContent: body?.failedGeneration ?? "", debugDescription: message)
        }
        guard let failure = providerFailure(contextSize: contextSize, imageEntries: imageEntries, now: now) else {
            return OpenAICompatibleError(
                providerName: providerName, status: status?.code, message: message, code: code,
                errorType: body?.type.map(OpenAICompatibleError.Code.init(rawValue:)), parameter: body?.parameter,
                requestID: requestID, retryAfter: retryAfter, isQuotaExhausted: isQuotaExhausted)
        }
        let metadata = OpenAICompatibleErrorMetadata.metadata(
            status: status?.code, code: code, requestID: requestID, providerName: providerName, host: host)
        return LanguageModelError(failure, message: message, metadata: metadata)
    }

    /// The kind of failure: `authentication` for a 400 whose message says the key is missing or refused, in the
    /// provider's words, then the provider's code, then the kind the HTTP status stands for, then the provider's error
    /// type for a status with no kind of its own, such as a 400, and `server` for a failure in the stream that names
    /// neither a status nor a type. Providers spell their types differently, so a status's kind keeps one word for
    /// one kind, such as `not_found` for every 404 without a code.
    private var code: OpenAICompatibleError.Code {
        if status == .badRequest, Self.says(message, any: words.refusedKey) { return .authentication }
        if let code = body?.code { return OpenAICompatibleError.Code(rawValue: code) }
        let kind = status.map(Self.code(for:))
        if let kind, kind != .unmapped { return kind }
        if let type = body?.type { return OpenAICompatibleError.Code(rawValue: type) }
        return kind ?? .server
    }

    /// The kind a status stands for, for a body that names none: any status from 500 up is the provider failing, and a
    /// status with no kind of its own, such as a 400 or a 429, is `unmapped`. Whether a status becomes
    /// `LanguageModelError` is decided in ``providerFailure(contextSize:imageEntries:now:)``, not here.
    private static func code(for status: HTTPStatus) -> OpenAICompatibleError.Code {
        switch status {
        case .unauthorized: .authentication
        case .paymentRequired: .paymentRequired
        case .forbidden: .permissionDenied
        case .notFound: .notFound
        case .conflict: .conflict
        case .unprocessableContent: .unprocessable
        case .internalServerError, .badGateway, .serviceUnavailable, .gatewayTimeout, .originTimeout, .overloaded: .server
        case .badRequest, .requestTimeout, .preconditionFailed, .contentTooLarge, .tooManyRequests: .unmapped
        case .other(let code): code >= 500 ? .server : .unmapped
        }
    }

    /// Whether the account ran out of quota, credits or balance: an HTTP 402, or `insufficient_quota` as the code or the
    /// error type.
    private var isQuotaExhausted: Bool {
        status == .paymentRequired || [body?.code, body?.type].contains(OpenAICompatibleError.Code.insufficientQuota.rawValue)
    }

    /// The `LanguageModelError` case the failure becomes, or `nil` when it becomes an `OpenAICompatibleError`. A quota
    /// that ran out stays the module's, since waiting doesn't clear it, although it can arrive as a 429, and so does a
    /// 413 whose code says rate limit, a request too large for the account's limits, since no wait lets it through.
    private func providerFailure(contextSize: Int?, imageEntries: [Transcript.Entry], now: Date) -> LanguageModelError.ProviderFailure? {
        let code = body?.code
        if isQuotaExhausted { return nil }
        if code == "context_length_exceeded"
            || (status == .badRequest
                && (LanguageModelError.ProviderFailure.namesContext(message) || Self.says(message, any: words.oversizedContext)))
        {
            return Self.contextSizes(in: message) ?? .contextSizeExceeded(message: message, contextSize: contextSize)
        }
        if status != .contentTooLarge, status == .tooManyRequests || code == "rate_limit_exceeded" {
            return .rateLimited(resetDate: LanguageModelError.ProviderFailure.resetDate(after: retryAfter, from: now))
        }
        if code.map(Self.guardrailCodes.contains) == true || Self.says(message, any: words.refusedContent) { return .guardrailViolation }
        if code.map(Self.unsupportedImageCodes.contains) == true { return .unsupportedContent(imageEntries) }
        if status == .requestTimeout || status == .gatewayTimeout || status == .originTimeout { return .timeout }
        return nil
    }

    /// The codes of a request or answer a content filter stopped.
    private static let guardrailCodes: Set<String> = ["content_policy_violation", "content_filter"]

    /// Whether a message holds any of a provider's words.
    private static func says(_ message: String, any words: [String]) -> Bool {
        words.contains { message.contains($0) }
    }

    /// An oversized prompt with the sizes a message names as `The input token count (9000) exceeds the maximum number of
    /// tokens allowed (8192)`, or `nil` for a message that doesn't.
    private static func contextSizes(in message: String) -> LanguageModelError.ProviderFailure? {
        guard let match = message.firstMatch(of: /\((\d+)\) exceeds the maximum number of tokens allowed \((\d+)\)/),
            let tokenCount = Int(match.1), let contextSize = Int(match.2)
        else { return nil }
        return .contextSizeExceeded(contextSize: contextSize, tokenCount: tokenCount)
    }

    /// The codes of an image the provider can't use. One it couldn't download stays the module's error.
    private static let unsupportedImageCodes: Set<String> = [
        "invalid_image", "invalid_image_format", "invalid_base64_image", "image_too_large", "image_too_small",
        "image_parse_error", "unsupported_image_media_type",
    ]

    /// The module's words for a response whose body holds no error it reads: up to 1,000 characters of its text, or for
    /// an empty or HTML body, the status with the content type and the size, so a gateway's page stays out of the
    /// message.
    ///
    /// - Parameters:
    ///   - body: The response's body.
    ///   - status: The response's status.
    ///   - contentType: The response's `Content-Type`, if any.
    /// - Returns: The message.
    private static func message(describing body: Data, status: HTTPStatus, contentType: String?) -> String {
        let type = contentType?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "HTTP \(status.code), empty \(type.map { "\($0) " } ?? "")body"
        }
        if type?.contains("html") == true || text.hasPrefix("<") {
            return "HTTP \(status.code), \(type ?? "HTML") body of \(body.count) bytes"
        }
        return String(text.prefix(1_000))
    }
}

// MARK: - Logging

extension OpenAICompatibleError: LoggableError {
    package var logFields: (kind: String, status: Int?, code: String?, host: String?) {
        ("OpenAICompatibleError", status, code.rawValue, nil)
    }
}
