import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ConnectionTests {
    @Suite("Retries")
    struct Retries {
        @Test func `retry-after-ms comes before Retry-After`() throws {
            let headers = [HTTPHeaderName.retryAfterMilliseconds.rawValue: "1500", HTTPHeaderName.retryAfter.rawValue: "60"]
            let url = try #require(URL(string: "https://example.com/chat"))
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: headers)
            let retry = backoff().retry(1, status: 503, response: response)

            #expect(retry?.wait == .milliseconds(1_500))
        }

        @Test func `cancelling during the wait before the retry throws a cancellation and sends nothing more`() async throws {
            let stub = HTTPStub(
                .json("{}", status: 503, headers: [HTTPHeaderName.retryAfter.rawValue: "60"]), .json("{}"))
            let http = http(stub, backoff())
            let request = request(stub)

            let task = Task { try await http.data(for: request) }
            for await _ in stub.sentResponses { break }
            task.cancel()

            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(stub.requests.count == 1)
        }

        @Test(arguments: [408, 409, 429, 500, 503, 529, 599])
        func `the backoff policy retries its statuses twice`(status: Int) async throws {
            let stub = HTTPStub(.json("{}", status: status), .json("{}", status: status), .json("{}"))
            var retries: [HTTPClient.Retry] = []

            _ = try await http(stub, backoff()).data(for: request(stub)) { retries.append($0) }

            #expect(retries.map(\.status) == [status, status])
            #expect(retries.map(\.number) == [1, 2])
            #expect(retries.allSatisfy { $0.limit == 2 })
            #expect(stub.requests.count == 3)
        }

        @Test func `the backoff policy fails after its retries`() async throws {
            let failure = StubResponse.json("{}", status: 503)
            let stub = HTTPStub(failure, failure, failure, .json("{}"))

            let rejected = try await #require(throws: HTTPClient.Failure.self) {
                try await http(stub, backoff()).data(for: request(stub))
            }

            #expect(rejected.status == 503)
            #expect(stub.requests.count == 3)
        }

        @Test(arguments: [400, 401, 404, 422])
        func `the backoff policy doesn't retry a client error`(status: Int) async throws {
            let stub = HTTPStub(.json("{}", status: status), .json("{}"))

            await #expect(throws: HTTPClient.Failure.self) { try await http(stub, backoff()).data(for: request(stub)) }

            #expect(stub.requests.count == 1)
        }

        @Test(arguments: [("true", 400, 2), ("false", 503, 1), ("False", 503, 2)])
        func `the backoff policy does what x-should-retry says, whatever the status`(header: String, status: Int, requests: Int) async {
            let stub = HTTPStub(.json("{}", status: status, headers: [HTTPHeaderName.shouldRetry.rawValue: header]), .json("{}"))

            _ = try? await http(stub, backoff()).data(for: request(stub))

            #expect(stub.requests.count == requests)
        }

        @Test func `the backoff policy doubles its wait for each retry, up to its longest, cut by up to a quarter`() async throws {
            let failure = StubResponse.json("{}", status: 500)
            let stub = HTTPStub(failure, failure, failure, failure, .json("{}"))
            var waits: [Duration] = []

            _ = try await http(stub, backoff(delay: .milliseconds(4), longestDelay: .milliseconds(10), retries: 4))
                .data(for: request(stub)) { waits.append($0.wait) }

            let longest: [Duration] = [.milliseconds(4), .milliseconds(8), .milliseconds(10), .milliseconds(10)]
            #expect(waits.count == longest.count)
            for (wait, longest) in zip(waits, longest) {
                #expect(wait > longest * 0.75 && wait <= longest, "Waited \(wait) for at most \(longest)")
            }
        }

        @Test(arguments: [
            (HTTPHeaderName.retryAfterMilliseconds, "125", Duration.milliseconds(125)),
            (.retryAfter, "0.125", .milliseconds(125)),
            (.retryAfter, "0", .zero),
        ])
        func `the backoff policy waits for the Retry-After a response asks for, and backs off from a zero one`(
            header: HTTPHeaderName, value: String, wait: Duration
        ) async throws {
            let stub = HTTPStub(.json("{}", status: 429, headers: [header.rawValue: value]), .json("{}"))
            var waited: Duration?

            _ = try await http(stub, backoff()).data(for: request(stub)) { waited = $0.wait }

            #expect(waited == wait)
            #expect(stub.requests.count == 2)
        }

        @Test func `the backoff policy fails at once when the response asks for more than 2 minutes`() async throws {
            let headers = [HTTPHeaderName.retryAfter.rawValue: "121", HTTPHeaderName.shouldRetry.rawValue: "true"]
            let stub = HTTPStub(.json("{}", status: 429, headers: headers), .json("{}"))

            let failure = try await #require(throws: HTTPClient.Failure.self) {
                try await http(stub, backoff()).data(for: request(stub))
            }

            #expect(failure.retryAfter == .seconds(121))
            #expect(stub.requests.count == 1)
        }

        @Test(arguments: [
            URLError.Code.timedOut, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .notConnectedToInternet,
            .networkConnectionLost, .secureConnectionFailed, .badServerResponse,
        ])
        func `the backoff policy retries a failed connection`(code: URLError.Code) async throws {
            let stub = HTTPStub(.failure(URLError(code)), .failure(URLError(code)), StubResponse(chunks: [Data("{}".utf8)]))
            var retries: [HTTPClient.Retry] = []

            _ = try await http(stub, backoff()).stream(for: request(stub)) { retries.append($0) }

            #expect(retries.map(\.error?.code) == [code, code])
            #expect(retries.allSatisfy { $0.status == nil })
            #expect(stub.requests.count == 3)
        }

        @Test func `a connection that keeps timing out throws the timeout after the retries`() async throws {
            let timeout = StubResponse.failure(URLError(.timedOut))
            let stub = HTTPStub(timeout, timeout, timeout, .json("{}"))

            let error = try await #require(throws: LanguageModelError.self) {
                try await http(stub, backoff()).data(for: request(stub))
            }

            guard case .timeout = error else {
                Issue.record("Threw \(error)")
                return
            }
            #expect(stub.requests.count == 3)
        }

        @Test(arguments: [(URLError.Code.cancelled, true), (.badURL, false), (.userAuthenticationRequired, false)])
        func `the backoff policy doesn't retry a cancellation or an error that isn't a failed connection`(
            code: URLError.Code, isCancellation: Bool
        ) async {
            let stub = HTTPStub(.failure(URLError(code)), .json("{}"))

            let error = await #expect(throws: (any Error).self) { try await http(stub, backoff()).data(for: request(stub)) }

            #expect(isCancellation ? error is CancellationError : (error as? URLError)?.code == code, "Threw \(String(describing: error))")
            #expect(stub.requests.count == 1)
        }

        @Test func `the policy retries up to the limit, then fails`() throws {
            let policy = RequestRetries(limit: 1, initialDelay: .zero).policy(statuses: { $0 == 503 })

            #expect(policy.retry(1, status: 503, response: nil)?.wait == .zero)
            #expect(policy.retry(2, status: 503, response: nil)?.wait == nil)
            #expect(policy.retry(1, status: 400, response: nil)?.wait == nil)
        }

        @Test func `the policy's first wait is the initial delay, cut by up to a quarter, and doubles after it`() throws {
            let policy = RequestRetries(limit: 3, initialDelay: .seconds(1)).policy(statuses: { _ in true })

            let first = try #require(policy.retry(1, status: 503, response: nil)).wait
            let second = try #require(policy.retry(2, status: 503, response: nil)).wait
            #expect(first >= .milliseconds(750) && first <= .seconds(1))
            #expect(second >= .milliseconds(1_500) && second <= .seconds(2))
        }

        @Test func `a server wait past the longest one fails at once, and a shorter one is waited`() throws {
            let policy = RequestRetries(longestServerWait: .seconds(5)).policy(statuses: { _ in true })
            let url = try #require(URL(string: "https://example.com"))

            let long = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: ["Retry-After": "6"])
            let short = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: ["Retry-After": "5"])
            #expect(policy.retry(1, status: 503, response: long)?.wait == nil)
            #expect(policy.retry(1, status: 503, response: short)?.wait == .seconds(5))
        }

        @Test func `negative retry settings count as zero`() throws {
            let policy = RequestRetries(limit: -3, initialDelay: .seconds(-1), longestServerWait: .seconds(-1))
                .policy(statuses: { _ in true })

            #expect(policy.retries == 0)
            #expect(policy.retry(1, status: 503, response: nil)?.wait == nil)
        }
    }
}
