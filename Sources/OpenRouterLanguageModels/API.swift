import Foundation
import LanguageModels

/// Facts about OpenRouter's API that the model, its exchange and the info calls rely on.
enum API {
    /// OpenRouter's name, as the log and error messages name it.
    static let name = "OpenRouter"

    /// The origin of reasoning that a model wrote through OpenRouter's Chat Completions API, which goes back as the text
    /// and `reasoning_details` of an assistant message.
    ///
    /// Saved transcripts keep this value, so it stays `openrouter`, although it names the format too. Reasoning that
    /// OpenRouter returns in another format gets an origin of its own, so it isn't sent back in this shape.
    static let reasoningOrigin = "openrouter"

    /// Whether a failed response's status is retried: any status from 500 up, which OpenRouter or a host returns while
    /// it's failing or overloaded. A response's `x-should-retry` wins over its status either way.
    @Sendable
    static func retriesStatus(_ status: Int) -> Bool {
        (500..<600).contains(status)
    }

    /// Where OpenRouter's API lives. `URL(string:)` makes it optional, although it never fails.
    static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1/")

    /// Where a request goes: the authentication's base URL, or OpenRouter's.
    ///
    /// - Parameter baseURL: The authentication's base URL, or `nil` for OpenRouter's.
    /// - Returns: The base URL.
    /// - Throws: `OpenRouterError` with `invalidRequest` when there's no valid base URL.
    static func baseURL(_ baseURL: URL?) throws(OpenRouterError) -> URL {
        guard let base = baseURL ?? defaultBaseURL else {
            throw OpenRouterError(message: "The base URL isn't valid.", code: .invalidRequest)
        }
        return base
    }

    /// The paths of OpenRouter's API calls, under the base URL.
    enum Path {
        /// The details of one model, `GET /model/{author}/{slug}`.
        static func model(_ id: OpenRouterModelID) -> String {
            "model/\(id.rawValue)"
        }

        /// The endpoints of one model, `GET /models/{author}/{slug}/endpoints`.
        static func endpoints(of id: OpenRouterModelID) -> String {
            "models/\(id.rawValue)/endpoints"
        }
    }

    /// The names of OpenRouter's own HTTP headers.
    enum Header {
        static let appCategories = "X-OpenRouter-Categories"
        static let appTitle = "X-OpenRouter-Title"
        static let appVisibility = "X-OpenRouter-App-Visibility"
        static let cache = "X-OpenRouter-Cache"
        static let cacheAge = "X-OpenRouter-Cache-Age"
        static let cacheClear = "X-OpenRouter-Cache-Clear"
        static let cacheSourceID = "X-OpenRouter-Cache-Source-Id"
        static let cacheStatus = "X-OpenRouter-Cache-Status"
        static let cacheTimeToLive = "X-OpenRouter-Cache-TTL"
        static let rateLimitReset = "X-RateLimit-Reset"
        static let referer = "HTTP-Referer"
        static let routerMetadata = "X-OpenRouter-Metadata"
        static let sessionID = "X-Session-Id"
    }
}

extension PackageLogger {
    /// The OpenRouter model's messages: what each request sends and leaves out, retries, which model and host
    /// answered, failures and timings.
    ///
    /// It's the same category as a request's log, for code that runs outside a request, such as an option's initializer.
    static let openRouter = PackageLogger(category: API.name)
}
