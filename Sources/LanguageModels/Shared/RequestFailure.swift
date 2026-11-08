package import Foundation
package import FoundationModels
import LanguageModelsCore

// MARK: - Failure

/// A request that failed, before a provider says what it becomes.
///
/// An exchange's `error(for:)`, or the `failure` closure of a cached call, reads it and returns the error to throw:
/// Foundation Models' own when it has a case for the failure, so apps handle it the same way for every model, and
/// otherwise the provider's. Only a shared model or a connection creates one, from what it received.
package struct RequestFailure<ErrorBody: Decodable & Sendable>: Error {
    /// What failed.
    package enum Kind: Sendable {
        /// A response whose status isn't a success, after the retries.
        case rejected

        /// An error event in the stream, which arrives after the response's HTTP 200.
        case errorEvent

        /// An answer that ended in an error the host reported.
        case failedAnswer

        /// An event whose data couldn't be read.
        case unreadableEvent

        /// An answer that was cut off, or has a tool call that can't run.
        case unusableAnswer
    }

    /// What failed.
    package let kind: Kind

    /// The status of a rejected response, which is ``HTTPStatus/other(_:)`` with 0 for a response that isn't HTTP; `nil`
    /// for a failure in the stream.
    package let status: HTTPStatus?

    /// The `error` object, or `nil` when the failure carries none, or none in the provider's type, such as a gateway's
    /// HTML page.
    package let body: ErrorBody?

    /// The whole body of a rejected response, for what a provider sends beside the `error` object; empty otherwise.
    package let rawBody: Data

    /// The wait a rejected response's `retry-after-ms` or `Retry-After` header asks for.
    package let retryAfter: Duration?

    /// The format's own words for what went wrong: the status of a rejected response, and a sentence for any other
    /// failure.
    package let message: String

    /// The request's entries that carry an image, which an error for an image the host rejects names.
    package let imageEntries: [Transcript.Entry]

    private let headers: ResponseHeaders

    /// The value of a header of the response, whether it was rejected or failed while it streamed.
    ///
    /// - Parameter name: The header's name, such as `x-request-id`.
    /// - Returns: The value, or `nil` when the response has no such header.
    package func header(_ name: String) -> String? {
        headers.value(named: name)
    }
}

extension RequestFailure {
    /// A response whose status isn't a success, after the retries.
    ///
    /// - Parameters:
    ///   - failure: The response.
    ///   - imageEntries: The request's entries that carry an image.
    init(rejected failure: HTTPClient.Failure, imageEntries: [Transcript.Entry]) {
        kind = .rejected
        status = failure.status
        body = try? HTTPClient.decoder.decode(Envelope.self, from: failure.body).error
        rawBody = failure.body
        retryAfter = failure.retryAfter
        message = failure.status.text
        self.imageEntries = imageEntries
        headers = ResponseHeaders(failure.response)
    }

    /// An error event in the stream.
    ///
    /// - Parameters:
    ///   - body: The event's `error` object.
    ///   - provider: The provider's name, which the message names.
    ///   - headers: The headers of the response whose stream failed.
    ///   - imageEntries: The request's entries that carry an image.
    init(errorEvent body: ErrorBody, provider: String, headers: ResponseHeaders, imageEntries: [Transcript.Entry]) {
        self.init(.errorEvent, body: body, message: "\(provider) sent an error.", headers: headers, imageEntries: imageEntries)
    }

    /// An answer that ended in an error the host reported.
    ///
    /// - Parameters:
    ///   - body: The answer's `error` object, or `nil` when it has none.
    ///   - headers: The headers of the response whose stream failed.
    ///   - imageEntries: The request's entries that carry an image.
    init(failedAnswer body: ErrorBody?, headers: ResponseHeaders, imageEntries: [Transcript.Entry]) {
        let message = "The model's response ended in an error."
        self.init(.failedAnswer, body: body, message: message, headers: headers, imageEntries: imageEntries)
    }

    /// A stream the format couldn't use.
    ///
    /// - Parameters:
    ///   - problem: What went wrong.
    ///   - provider: The provider's name, which the message names.
    ///   - headers: The headers of the response whose stream failed.
    ///   - imageEntries: The request's entries that carry an image.
    init(_ problem: StreamProblem, provider: String, headers: ResponseHeaders, imageEntries: [Transcript.Entry]) {
        let kind: Kind =
            switch problem {
            case .unreadableEvent: .unreadableEvent
            case .cutOff, .toolCallWithoutName, .incompleteToolArguments, .tokenLimitInToolCall: .unusableAnswer
            }
        self.init(kind, body: nil, message: problem.message(provider: provider), headers: headers, imageEntries: imageEntries)
    }

    private init(_ kind: Kind, body: ErrorBody?, message: String, headers: ResponseHeaders, imageEntries: [Transcript.Entry]) {
        self.kind = kind
        status = nil
        self.body = body
        rawBody = Data()
        retryAfter = nil
        self.message = message
        self.imageEntries = imageEntries
        self.headers = headers
    }
}

// MARK: - Stream problems

/// Why a format couldn't use a provider's streamed response, which a ``RequestFailure`` puts in words.
///
/// Only a shared model reports one.
enum StreamProblem: Error, Equatable {
    /// An event's data isn't one the format can read, with the reason it couldn't be read.
    case unreadableEvent(String)

    /// The stream ended before it was complete.
    case cutOff

    /// A tool call never got its name.
    case toolCallWithoutName

    /// A tool call's arguments aren't a whole JSON object, such as ones that stop partway.
    case incompleteToolArguments(toolName: String)

    /// The answer reached its token limit inside a tool call.
    case tokenLimitInToolCall

    /// What went wrong, as an error says it.
    ///
    /// - Parameter provider: The provider's name, such as `OpenRouter`.
    /// - Returns: A sentence for the error's message.
    fileprivate func message(provider: String) -> String {
        switch self {
        case .unreadableEvent(let reason): "\(provider) sent an event that couldn't be read: \(reason)"
        case .cutOff: "The response ended before it was complete."
        case .toolCallWithoutName: "The model sent a tool call without its name."
        case .incompleteToolArguments(let toolName): "The model sent arguments for \(toolName) that aren't a whole JSON object."
        case .tokenLimitInToolCall: "The answer reached its token limit inside a tool call."
        }
    }
}

// MARK: - Foundation Models' errors

extension LanguageModelError {
    /// A failure a provider reported that Foundation Models has a case for.
    package enum ProviderFailure {
        /// The prompt is longer than the model's context, with the sizes when known; 0 stands for an unknown one.
        case contextSizeExceeded(contextSize: Int, tokenCount: Int)
        case rateLimited(resetDate: Date?)
        case guardrailViolation
        case refusal
        case timeout
        /// Content of these entries that the host can't use, such as an image in a format it doesn't take.
        case unsupportedContent([Transcript.Entry])
    }

    /// The error a provider's failure becomes.
    ///
    /// - Parameters:
    ///   - failure: The Foundation Models case the failure stands for.
    ///   - message: What went wrong, as the provider said it.
    ///   - metadata: The failure's facts, under the shared keys such as `status`, and the provider's own.
    package init(_ failure: ProviderFailure, message: String, metadata: [String: any Sendable]) {
        switch failure {
        case .contextSizeExceeded(let contextSize, let tokenCount):
            var exceeded = ContextSizeExceeded(contextSize: contextSize, tokenCount: tokenCount, debugDescription: message)
            // Foundation Models 2.1.14, in Xcode 27.2, drops the initializer's `metadata` argument, so it's set
            // afterwards.
            exceeded.metadata = metadata
            self = .contextSizeExceeded(exceeded)
        case .rateLimited(let resetDate):
            self = .rateLimited(.init(resetDate: resetDate, debugDescription: message, metadata: metadata))
        case .guardrailViolation:
            self = .guardrailViolation(.init(debugDescription: message, metadata: metadata))
        case .refusal:
            self = .refusal(.init(explanation: message, debugDescription: message, metadata: metadata))
        case .timeout:
            self = .timeout(.init(debugDescription: message, metadata: metadata))
        case .unsupportedContent(let entries):
            self = .unsupportedTranscriptContent(.init(unsupportedContent: entries, debugDescription: message, metadata: metadata))
        }
    }
}

extension LanguageModelError.ProviderFailure {
    /// An oversized prompt, with the sizes its error's message names, the model's own context size when it names none,
    /// and 0 for one that isn't known.
    ///
    /// - Parameters:
    ///   - message: The error's message.
    ///   - contextSize: The model's context size, if known.
    /// - Returns: The failure.
    package static func contextSizeExceeded(message: String, contextSize: Int?) -> Self {
        let sizes = contextSizes(in: message)
        return .contextSizeExceeded(contextSize: sizes.limit ?? contextSize ?? 0, tokenCount: sizes.requested ?? 0)
    }

    /// When a rate limit resets, from the wait a response names.
    ///
    /// - Parameters:
    ///   - wait: How long the limit lasts, if known.
    ///   - now: The time the wait counts from.
    /// - Returns: The date, or `nil` when there's no wait.
    package static func resetDate(after wait: Duration?, from now: Date) -> Date? {
        wait.map { now.addingTimeInterval($0 / .seconds(1)) }
    }

    /// Whether an error's message names the context's length or window, as a 400 for an oversized prompt does.
    package static func namesContext(_ message: String) -> Bool {
        message.contains(/(?i)context (?:length|window)/)
    }

    /// The sizes the message of an oversized prompt's error names, each when it names it: the model's context size,
    /// as in "maximum context length is 8192" or "context window of 8192", and the tokens the request needs, as in
    /// "requested about 9000" or "resulted in 9000".
    ///
    /// - Parameter message: The error's message.
    /// - Returns: The context size and the tokens the request needs.
    static func contextSizes(in message: String) -> (limit: Int?, requested: Int?) {
        let limit = message.firstMatch(of: /(?:maximum context length is|context window of) (\d+)/).flatMap { Int($0.1) }
        let requested = message.firstMatch(of: /(?:requested (?:about )?|resulted in )(\d+)/).flatMap { Int($0.1) }
        return (limit, requested)
    }
}

extension LanguageModelError {
    /// The error for transcript content a provider can't take.
    package static func unsupported(_ entry: Transcript.Entry, _ description: String) -> LanguageModelError {
        .unsupportedTranscriptContent(.init(unsupportedContent: [entry], debugDescription: description))
    }

    /// The error for a capability a model doesn't have, such as tool calling.
    package static func unsupported(_ capability: LanguageModelCapabilities.Capability, _ description: String) -> LanguageModelError {
        .unsupportedCapability(.init(capability: capability, debugDescription: description))
    }
}

// MARK: - Wire

/// The `error` object that OpenAI's formats send in a failed response's body, `{"error": {"message", "type",
/// "code", "param"}}`, which other providers that follow the formats send too, often with members of their own.
///
/// The message is required. The other members are read when they have the expected kind and are `nil`
/// otherwise, since providers vary them.
package struct APIErrorBody: Decodable, Sendable {
    /// What went wrong.
    package private(set) var message: String

    /// The kind of error, such as `invalid_request_error`.
    package var type: String?

    /// The error's code, a number or a word depending on the provider.
    package private(set) var code: JSONValue?

    /// The request parameter the error concerns.
    package private(set) var param: String?

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        code = try container.decodeIfPresent(JSONValue.self, forKey: .code)
        param = try? container.decodeIfPresent(String.self, forKey: .param)
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case type
        case code
        case param
    }
}

extension RequestFailure {
    /// The body of a failed response, `{"error": {…}}`.
    private struct Envelope: Decodable {
        let error: ErrorBody
    }
}
