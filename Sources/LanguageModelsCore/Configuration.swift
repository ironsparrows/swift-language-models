// MARK: - Retries

/// How a request that fails before any data arrives is sent again: how many times, and how long it waits first.
///
/// A provider's configuration holds one, such as `OpenAIConfiguration`'s `retries`. A failed connection is retried for
/// every provider, and each provider decides which failed responses are, such as a server error. A request is never
/// retried once its answer starts arriving, or after it's cancelled:
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
    ///   - limit: The most times a request is sent again. The default is 2.
    ///   - initialDelay: The wait before the first retry, which doubles for each retry after it. The default is half a
    ///     second.
    ///   - longestServerWait: The longest wait a server can ask for and still have the request retried. The default is
    ///     2 minutes.
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

// MARK: - Image encoding

/// How image attachments are encoded before they're sent: upright, on white, and as JPEG no larger than a size.
///
/// A provider's configuration that sends images holds one, such as `OpenAIConfiguration`'s `images`. A smaller
/// image costs fewer input tokens, and a larger one keeps small print legible:
///
/// ```swift
/// model.configuration.images = ImageEncoding(maximumSide: 1_024)
/// ```
///
/// An image at a web address goes as its address, so neither setting applies to it.
public struct ImageEncoding: Sendable, Hashable {
    /// The longest side, in pixels, of an image sent as data. A larger image is scaled down to it, keeping its shape,
    /// and a smaller one is never scaled up. A side under 1 counts as 1.
    public var maximumSide: Int

    /// The JPEG quality, from 0 for the smallest file to 1 for the best image. A value outside that range counts as
    /// the nearest end of it, and NaN as the default.
    public var quality: Double

    /// Creates encoding settings.
    ///
    /// - Parameters:
    ///   - maximumSide: The longest side, in pixels, of an image sent as data. The default, 2,048, is the largest image
    ///     that OpenAI's models see in full detail, and close to what other providers keep.
    ///   - quality: The JPEG quality, from 0 to 1. The default, 0.85, keeps small text legible at a fraction of PNG's
    ///     size.
    public init(maximumSide: Int = 2_048, quality: Double = 0.85) {
        self.maximumSide = maximumSide
        self.quality = quality
    }

    /// Images up to 2,048 pixels on their longest side, at a JPEG quality of 0.85.
    public static let standard = ImageEncoding()
}
