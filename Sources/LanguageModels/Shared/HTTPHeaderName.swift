import LanguageModelsCore

/// The name of an HTTP header, such as `Authorization`.
///
/// Header names are compared as written, so a provider spells each the same way everywhere, as the names here do.
package struct HTTPHeaderName: ProviderVocabulary {
    /// The media types a response may have.
    package static let accept: Self = "Accept"

    /// The credentials of a request, such as `Bearer …`.
    package static let authorization: Self = "Authorization"

    /// The media type of a request's body.
    package static let contentType: Self = "Content-Type"

    /// How long a response asks to wait before trying again.
    package static let retryAfter: Self = "Retry-After"

    /// How long a response asks to wait before trying again, in milliseconds, which takes precedence over
    /// `Retry-After`.
    package static let retryAfterMilliseconds: Self = "retry-after-ms"

    /// The id a provider gave the request, which its support asks for.
    package static let requestID: Self = "x-request-id"

    /// Whether a response says the request may be sent again: `true` or `false`.
    package static let shouldRetry: Self = "x-should-retry"

    /// The client that sends a request.
    package static let userAgent: Self = "User-Agent"

    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }
}
