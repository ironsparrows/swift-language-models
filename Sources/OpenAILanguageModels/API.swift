import Foundation
import LanguageModels

/// Facts about OpenAI's API that the model and its exchange rely on.
enum API {
    /// OpenAI's name, as the log and error messages name it.
    static let name = "OpenAI"

    /// The origin of reasoning that a model wrote through OpenAI's Responses API, which goes back as the answer's
    /// `reasoning` items, with their reasoning encrypted.
    ///
    /// Saved transcripts keep this value, so it never changes.
    static let reasoningOrigin = "openai-responses"

    /// Whether a failed response's status is retried, as the official SDKs retry it: a 408, 409 or 429, or any status
    /// from 500 up. A response's `x-should-retry` wins over its status either way.
    @Sendable
    static func retriesStatus(_ status: Int) -> Bool {
        [408, 409, 429].contains(status) || status >= 500
    }

    /// Where OpenAI's API lives. `URL(string:)` makes it optional, although it never fails.
    static let defaultBaseURL = URL(string: "https://api.openai.com/v1/")

    /// Where a request goes: the authentication's base URL, or OpenAI's.
    ///
    /// - Parameter baseURL: The authentication's base URL, or `nil` for OpenAI's.
    /// - Returns: The base URL.
    /// - Throws: `OpenAIError` with `invalidRequest` when there's no valid base URL.
    static func baseURL(_ baseURL: URL?) throws(OpenAIError) -> URL {
        guard let base = baseURL ?? defaultBaseURL else {
            throw OpenAIError(message: "The base URL isn't valid.", code: .invalidRequest)
        }
        return base
    }

    /// The names of the HTTP headers OpenAI's API reads and sends.
    enum Header {
        static let authorization = "Authorization"
        static let organization = "OpenAI-Organization"
        static let project = "OpenAI-Project"
        static let rateLimitResetRequests = "x-ratelimit-reset-requests"
        static let rateLimitResetTokens = "x-ratelimit-reset-tokens"
        static let requestID = "x-request-id"
    }
}
