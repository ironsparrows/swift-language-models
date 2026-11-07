package import Foundation
package import LanguageModelsCore

extension ProviderHTTP {
    /// When a provider's request that fails is sent again, and how long it waits first.
    ///
    /// A provider makes its policy from the app's ``RequestRetries`` with
    /// ``RequestRetries/policy(statuses:retriedErrors:)``, giving only the statuses it retries.
    package struct RetryPolicy: Sendable {
        /// The most times a request is sent again.
        package let retries: Int

        /// The errors of a failed connection after which a request is sent again, such as a timeout.
        package let retriedErrors: Set<URLError.Code>

        /// Whether a response is retried, from its status and its `x-should-retry` header, if any.
        private let retriesResponse: @Sendable (_ status: Int, _ shouldRetry: String?) -> Bool

        /// The wait before a retry, from how many retries came before it and the wait the response asks for, if
        /// any, or `nil` to fail at once.
        private let wait: @Sendable (_ retried: Int, _ asked: Duration?) -> Duration?

        /// Creates a policy.
        ///
        /// - Parameters:
        ///   - retries: The most times a request is sent again.
        ///   - retriedErrors: The errors of a failed connection after which a request is sent again.
        ///   - retriesResponse: Whether a response is retried, from its status and its `x-should-retry` header, if
        ///     any.
        ///   - wait: The wait before a retry, from how many retries came before it and the wait the response asks for,
        ///     if any, or `nil` to fail at once.
        package init(
            retries: Int,
            retriedErrors: Set<URLError.Code>,
            retriesResponse: @escaping @Sendable (_ status: Int, _ shouldRetry: String?) -> Bool,
            wait: @escaping @Sendable (_ retried: Int, _ asked: Duration?) -> Duration?
        ) {
            self.retries = retries
            self.retriedErrors = retriedErrors
            self.retriesResponse = retriesResponse
            self.wait = wait
        }

        /// The retry of a request whose response failed, or `nil` when the request fails at once.
        ///
        /// - Parameters:
        ///   - number: The retry's number, from 1.
        ///   - status: The response's status.
        ///   - response: The response, whose `x-should-retry`, `retry-after-ms` and `Retry-After` headers count.
        /// - Returns: The retry, or `nil` when the request has made its retries, the status isn't retried, or the
        ///   response asks for a longer wait than the policy allows.
        package func retry(_ number: Int, status: Int, response: HTTPURLResponse?) -> Retry? {
            guard number <= retries,
                retriesResponse(status, response?.value(forHTTPHeaderField: HTTPHeaderName.shouldRetry.rawValue)),
                let wait = wait(number - 1, ProviderHTTP.retryAfter(of: response))
            else { return nil }
            return Retry(status: status, error: nil, wait: wait, number: number, limit: retries)
        }

        /// The retry of a request whose connection failed, or `nil` when the request fails at once.
        ///
        /// - Parameters:
        ///   - number: The retry's number, from 1.
        ///   - error: The connection's error.
        /// - Returns: The retry, or `nil` when the request has made its retries or the error isn't retried.
        package func retry(_ number: Int, after error: URLError) -> Retry? {
            guard number <= retries, retriedErrors.contains(error.code), let wait = wait(number - 1, nil)
            else { return nil }
            return Retry(status: nil, error: error, wait: wait, number: number, limit: retries)
        }
    }

    /// A request that's sent again: what failed, and how long it waits first.
    package struct Retry: Sendable {
        /// The failed response's status, or `nil` when the connection failed.
        package let status: Int?

        /// The failed connection's error, or `nil` when a response failed.
        package let error: URLError?

        /// The wait before the request is sent again.
        package let wait: Duration

        /// The retry's number, from 1.
        package let number: Int

        /// The most times the request is sent again.
        package let limit: Int
    }
}

extension ProviderHTTP.RetryPolicy {
    /// The errors of a connection that couldn't be made, timed out or was lost, or that brought back a response that
    /// isn't HTTP.
    package static let connectionErrors: Set<URLError.Code> = [
        .timedOut, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost,
        .secureConnectionFailed, .badServerResponse,
    ]

    /// Up to `retries` retries of a failed connection or a response whose status `statuses` retries, with a wait that
    /// doubles from `delay` up to `longestDelay` and is cut by up to a quarter at random.
    ///
    /// A response's `x-should-retry` decides when it's `true` or `false`, whatever the status. A response that asks in
    /// `retry-after-ms` or `Retry-After` for a wait more than zero and at most `longestRetryAfter` waits that long
    /// instead, and one that asks for more fails at once.
    ///
    /// - Parameters:
    ///   - retries: The most times a request is sent again.
    ///   - statuses: Whether a status is retried, when `x-should-retry` doesn't say.
    ///   - delay: The wait before the first retry, before it's cut.
    ///   - longestDelay: The longest wait that doubling reaches.
    ///   - longestRetryAfter: The longest wait a response can ask for and still be retried, after that wait.
    ///   - retriedErrors: The errors of a failed connection after which a request is sent again.
    /// - Returns: The policy.
    package static func exponentialBackoff(
        retries: Int,
        statuses: @escaping @Sendable (Int) -> Bool,
        delay: Duration,
        longestDelay: Duration,
        longestRetryAfter: Duration,
        retriedErrors: Set<URLError.Code> = connectionErrors
    ) -> Self {
        Self(
            retries: retries, retriedErrors: retriedErrors,
            retriesResponse: { status, shouldRetry in
                switch shouldRetry {
                case "true": true
                case "false": false
                default: statuses(status)
                }
            },
            wait: { retried, asked in
                if let asked {
                    if asked > longestRetryAfter { return nil }
                    if asked > .zero { return asked }
                }
                let doubled = (0..<retried).reduce(delay) { wait, _ in Swift.min(wait * 2, longestDelay) }
                return Swift.min(doubled, longestDelay) * (1 - 0.25 * Double.random(in: 0..<1))
            })
    }
}

extension RequestRetries {
    /// The retry policy these settings make, for a provider that retries a response whose status `statuses` retries,
    /// after any of `retriedErrors`.
    ///
    /// - Parameters:
    ///   - statuses: Whether a response's status is retried when its `x-should-retry` doesn't say.
    ///   - retriedErrors: The errors of a failed connection after which a request is sent again.
    /// - Returns: The policy.
    package func policy(
        statuses: @escaping @Sendable (Int) -> Bool,
        retriedErrors: Set<URLError.Code> = ProviderHTTP.RetryPolicy.connectionErrors
    ) -> ProviderHTTP.RetryPolicy {
        let delay = max(initialDelay, .zero)
        return .exponentialBackoff(
            retries: max(limit, 0), statuses: statuses, delay: delay, longestDelay: delay * 16,
            longestRetryAfter: max(longestServerWait, .zero), retriedErrors: retriedErrors)
    }
}
