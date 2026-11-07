/// How a request that fails before any data arrives is sent again: how many times, and how long it waits first.
///
/// A provider's configuration holds one, such as `OpenAIConfiguration`'s `retries`, and the provider decides which
/// failures are worth retrying, such as a failed connection or a server error. A request is never retried once its
/// answer starts arriving, or after it's cancelled:
///
/// ```swift
/// // Fail fast on an interactive screen.
/// model.configuration.retries = RequestRetries(limit: 1, longestServerWait: .seconds(5))
///
/// // Retry nothing, such as in a test or an evaluation that retries on its own.
/// model.configuration.retries = .disabled
/// ```
///
/// Without a wait the server asks for, a retry waits ``initialDelay``, doubled for each retry before it up to 16 times
/// ``initialDelay``, and cut by up to a quarter at random, so many clients that failed together don't retry together.
public struct RequestRetries: Sendable, Hashable {
    /// The most times a request is sent again; 0 sends it once only. A negative limit counts as 0.
    public var limit: Int

    /// The wait before the first retry, which doubles for each retry after it. A negative delay counts as zero.
    public var initialDelay: Duration

    /// The longest wait a server can ask for, with `retry-after-ms` or `Retry-After`, and still have the request
    /// retried after it. A server that asks for longer fails the request at once, with the wait on its error, so the
    /// app can retry later. A negative wait counts as zero.
    public var longestServerWait: Duration

    /// Creates retry settings.
    ///
    /// - Parameters:
    ///   - limit: The most times a request is sent again. The default is 2, as in OpenAI's own SDKs.
    ///   - initialDelay: The wait before the first retry, which doubles for each retry after it.
    ///   - longestServerWait: The longest wait a server can ask for and still have the request retried.
    public init(limit: Int = 2, initialDelay: Duration = .milliseconds(500), longestServerWait: Duration = .seconds(120)) {
        self.limit = limit
        self.initialDelay = initialDelay
        self.longestServerWait = longestServerWait
    }

    /// Up to 2 retries, the first after half a second, with a wait of up to 2 minutes when a server asks for one.
    public static let standard = RequestRetries()

    /// No retries: a request that fails throws at once.
    public static let disabled = RequestRetries(limit: 0)
}
