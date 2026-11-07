import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

/// How requests are sent: retries, redirects and timeouts.
@Suite("Connection", .timeLimit(.minutes(1)))
struct ConnectionTests {
    static func http(_ stub: HTTPStub, _ policy: HTTPClient.RetryPolicy = backoff(retries: 0)) -> HTTPClient {
        HTTPClient(session: stub.session, retryPolicy: policy)
    }

    /// The shared policy's behavior, with configurable waits so these tests finish quickly.
    static func backoff(
        delay: Duration = .zero, longestDelay: Duration = .zero, retries: Int = 2
    ) -> HTTPClient.RetryPolicy {
        .exponentialBackoff(
            retries: retries, statuses: { [408, 409, 429].contains($0) || $0 >= 500 }, delay: delay, longestDelay: longestDelay,
            longestRetryAfter: .seconds(120))
    }

    static func request(_ stub: HTTPStub) -> URLRequest {
        HTTPClient.request(url: stub.baseURL.appending(path: "v1/chat"), authHeaders: [.authorization: "Bearer key"])
    }
}
