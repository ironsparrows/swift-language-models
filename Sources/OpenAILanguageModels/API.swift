import Foundation
import LanguageModels

/// Facts about OpenAI's API that its dialect relies on. They live outside the dialect because a generic type can't
/// store static values.
enum API {
    /// OpenAI's name, as the log and error messages name it.
    static let name = "OpenAI"

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

    /// The names of OpenAI's own HTTP headers.
    enum Header {
        static let organization: HTTPHeaderName = "OpenAI-Organization"
        static let project: HTTPHeaderName = "OpenAI-Project"
        static let rateLimitResetRequests: HTTPHeaderName = "x-ratelimit-reset-requests"
        static let rateLimitResetTokens: HTTPHeaderName = "x-ratelimit-reset-tokens"
    }
}
