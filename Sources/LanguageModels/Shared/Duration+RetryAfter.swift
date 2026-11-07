package import Foundation

extension Duration {
    /// The longest wait a header can ask for. A longer one, or one too large to represent, is cut to this.
    private static let longestRetryDelay = 86_400.0

    /// The delay in a `Retry-After` header: a number of seconds, or an HTTP date.
    package init?(retryAfter header: String?, now: Date = .now) {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        if let seconds = Double(header) {
            self.init(clampedSeconds: seconds)
            return
        }
        let strategy = Date.ParseStrategy(
            format:
                "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .gmt
        )
        guard let date = try? Date(header, strategy: strategy) else { return nil }
        self.init(clampedSeconds: date.timeIntervalSince(now))
    }

    /// The delay in a `retry-after-ms` header, in milliseconds.
    package init?(retryAfterMilliseconds header: String?) {
        guard let header, let milliseconds = Double(header.trimmingCharacters(in: .whitespaces)), milliseconds.isFinite else {
            return nil
        }
        self.init(clampedSeconds: milliseconds / 1_000)
    }

    /// The delay until the time in an `X-RateLimit-Reset` header, in milliseconds or seconds since 1970.
    package init?(rateLimitReset header: String?, now: Date = .now) {
        guard let header, let value = Double(header.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        // Times in milliseconds are past 1e11; in seconds, that's the year 5138.
        let reset = Date(timeIntervalSince1970: value > 1e11 ? value / 1_000 : value)
        self.init(clampedSeconds: reset.timeIntervalSince(now))
    }

    /// A delay of the given seconds, at least zero and at most the longest a header can ask for.
    private init?(clampedSeconds seconds: Double) {
        guard !seconds.isNaN else { return nil }
        self = .seconds(Swift.min(Swift.max(seconds, 0), Self.longestRetryDelay))
    }
}
