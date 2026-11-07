import Foundation
import FoundationModels
import Testing

@testable import LanguageModels
@testable import OpenRouterLanguageModels

extension OpenRouterErrorTests {
    @Suite("Retry delays")
    struct RetryDelays {
        private static let now = Date(timeIntervalSince1970: 1_793_000_000)

        @Test func `a rate limit's reset date is the wait after the moment of the failure`() throws {
            let failure = OpenRouterFailure(status: 429, body: nil, retryAfter: .seconds(30))

            let error = try #require(failure.error(contextSize: nil, now: Self.now) as? LanguageModelError)

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            #expect(info.resetDate == Self.now.addingTimeInterval(30))
        }

        @Test(arguments: [("30", 30.0), ("1.5", 1.5), ("-4", 0), ("inf", 86_400), ("1e300", 86_400)])
        func `a number of seconds is clamped to a day`(header: String, seconds: Double) {
            #expect(Duration(retryAfter: header, now: Self.now) == .seconds(seconds))
        }

        @Test func `an HTTP date is the time until then`() {
            #expect(Duration(retryAfter: "Tue, 27 Oct 2026 06:13:50 GMT", now: Date(timeIntervalSince1970: 1_793_081_600)) == .seconds(30))
        }

        @Test(arguments: ["Sunday, 06-Nov-94 08:49:37 GMT", "Sun, 6 Nov 1994 08:49:37 GMT"])
        func `an HTTP date in the obsolete form or with a one-digit day is read too`(header: String) {
            #expect(Duration(retryAfter: header, now: Date(timeIntervalSince1970: 784_111_747)) == .seconds(30))
        }

        @Test(arguments: [nil, "", "soon", "nan"])
        func `a header that isn't a delay gives none`(header: String?) {
            #expect(Duration(retryAfter: header, now: Self.now) == nil)
        }

        @Test(arguments: [("1793000030000", 30.0), ("1793000030", 30.0), ("1792999990", 0)])
        func `a rate limit reset is the time until then, in milliseconds or seconds`(header: String, seconds: Double) {
            #expect(Duration(rateLimitReset: header, now: Self.now) == .seconds(seconds))
        }
    }
}
