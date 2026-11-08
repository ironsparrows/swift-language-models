import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ConnectionTests {
    /// A connection to a stub that retries any status from 500 to 599, without waiting.
    static func connection(
        _ stub: HTTPStub,
        authentication: Connection.Authentication = .unauthenticated,
        idleTimeout: Duration? = nil,
        retryLimit: Int = 2
    ) -> Connection {
        Connection(
            session: stub.session, authentication: authentication, idleTimeout: idleTimeout,
            retries: RequestRetries(limit: retryLimit, initialDelay: .zero), retrying: .serverErrors)
    }

    /// A plain model sending through a connection to a stub.
    static func plainModel(
        _ stub: HTTPStub,
        authentication: Connection.Authentication = .unauthenticated,
        idleTimeout: Duration? = nil,
        retryLimit: Int = 2
    ) -> ChatCompletions.Model<ChatCompletions.PlainExchange> {
        var model = ChatCompletionsModelTests.plainModel(stub)
        model.connection = connection(stub, authentication: authentication, idleTimeout: idleTimeout, retryLimit: retryLimit)
        return model
    }

    /// An answer to one prompt.
    static var answer: StubResponse {
        chatCompletionsEvents(["choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]]])
    }

    @Suite("Retries")
    struct Retries {
        /// What a failed connection surfaces as.
        enum Outcome: Sendable {
            case urlError(URLError.Code)
            case timeout
            case cancellation

            func matches(_ error: (any Error)?) -> Bool {
                switch self {
                case .urlError(let code):
                    return (error as? URLError)?.code == code
                case .timeout:
                    guard case .timeout? = error as? LanguageModelError else { return false }
                    return true
                case .cancellation:
                    return error is CancellationError
                }
            }
        }

        /// A format, which reads its stream on its own.
        enum Format: CaseIterable, Sendable {
            case chatCompletions, responses

            /// An answer that started and hasn't ended.
            var startedAnswer: StubResponse {
                switch self {
                case .chatCompletions: .eventStream(Data(#"data: {"choices":[{"delta":{"content":"Hel"}}]}\#n\#n"#.utf8))
                case .responses: events(textDelta("Hel"))
                }
            }

            /// Sends one prompt from a session on the format's plain model, through a connection to a stub.
            func respond(_ stub: HTTPStub) async throws {
                switch self {
                case .chatCompletions:
                    _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hi")
                case .responses:
                    var model = ResponsesModelTests.plainModel(stub)
                    model.connection = connection(stub)
                    _ = try await LanguageModelSession(model: model).respond(to: "Hi")
                }
            }
        }

        @Test func `retry-after-ms comes before Retry-After`() throws {
            let headers = [HTTPHeaderName.retryAfterMilliseconds.rawValue: "1500", HTTPHeaderName.retryAfter.rawValue: "60"]
            let url = try #require(URL(string: "https://example.com/chat"))
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: headers)
            let retry = backoff().retry(1, status: .serviceUnavailable, response: response)

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

            #expect(retries.map(\.cause.status) == [HTTPStatus(code: status), HTTPStatus(code: status)])
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

            #expect(rejected.status == .serviceUnavailable)
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

            #expect(retries.map(\.cause.errorCode) == [code, code])
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
            let policy = RequestRetries(limit: 1, initialDelay: .zero).policy(statuses: .serverErrors)

            #expect(policy.retry(1, status: .serviceUnavailable, response: nil)?.wait == .zero)
            #expect(policy.retry(2, status: .serviceUnavailable, response: nil)?.wait == nil)
            #expect(policy.retry(1, status: .badRequest, response: nil)?.wait == nil)
        }

        @Test func `the policy's first wait is the initial delay, cut by up to a quarter, and doubles after it`() throws {
            let policy = RequestRetries(limit: 3, initialDelay: .seconds(1)).policy(statuses: .serverErrors)

            let first = try #require(policy.retry(1, status: .serviceUnavailable, response: nil)).wait
            let second = try #require(policy.retry(2, status: .serviceUnavailable, response: nil)).wait
            #expect(first >= .milliseconds(750) && first <= .seconds(1))
            #expect(second >= .milliseconds(1_500) && second <= .seconds(2))
        }

        @Test func `a server wait past the longest one fails at once, and a shorter one is waited`() throws {
            let policy = RequestRetries(longestServerWait: .seconds(5)).policy(statuses: .serverErrors)
            let url = try #require(URL(string: "https://example.com"))

            let long = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: ["Retry-After": "6"])
            let short = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: ["Retry-After": "5"])
            #expect(policy.retry(1, status: .serviceUnavailable, response: long)?.wait == nil)
            #expect(policy.retry(1, status: .serviceUnavailable, response: short)?.wait == .seconds(5))
        }

        @Test func `negative retry settings count as zero`() throws {
            let policy = RequestRetries(limit: -3, initialDelay: .seconds(-1), longestServerWait: .seconds(-1))
                .policy(statuses: .serverErrors)

            #expect(policy.retries == 0)
            #expect(policy.retry(1, status: .serviceUnavailable, response: nil)?.wait == nil)
        }

        @Test func `a session's request goes out again after a failed connection, until it's answered`() async throws {
            let failure = StubResponse.failure(URLError(.networkConnectionLost))
            let stub = HTTPStub(failure, failure, answer)

            let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hi")

            #expect(response.content == "Hi")
            #expect(stub.requests.count == 3)
        }

        @Test(arguments: [(1, 2), (0, 1)])
        func `a request that keeps failing goes out once, then up to the retry limit`(limit: Int, requests: Int) async {
            let failure = StubResponse.json(#"{"error":{"message":"Overloaded."}}"#, status: 503)
            let stub = HTTPStub(failure, failure, answer)

            await #expect(throws: RequestFailure<APIErrorBody>.self) {
                _ = try await LanguageModelSession(model: plainModel(stub, retryLimit: limit)).respond(to: "Hi")
            }

            #expect(stub.requests.count == requests)
        }

        @Test func `every request names the package in its User-Agent, a retried one too`() async throws {
            let stub = HTTPStub(.json("{}", status: 503), answer)

            _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hi")

            let userAgents = stub.requests.map { $0.request.value(forHTTPHeaderField: "User-Agent") }
            #expect(userAgents == [UserAgent.current, UserAgent.current])
        }

        @Test(arguments: [
            (URLError.Code.notConnectedToInternet, Outcome.urlError(.notConnectedToInternet)),
            (.cannotFindHost, .urlError(.cannotFindHost)),
            (.cannotConnectToHost, .urlError(.cannotConnectToHost)),
            (.secureConnectionFailed, .urlError(.secureConnectionFailed)),
            (.timedOut, .timeout),
            (.cancelled, .cancellation),
        ])
        func `a connection that fails before a response throws the matching error`(code: URLError.Code, outcome: Outcome) async {
            // A failed connection is retried twice, so it fails three times; a cancellation isn't retried.
            let failure = StubResponse.failure(URLError(code))
            let stub = HTTPStub(failure, failure, failure, answer)

            let error = await #expect(throws: (any Error).self) {
                _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hi")
            }

            #expect(outcome.matches(error), "Got \(String(describing: error))")
            #expect(stub.requests.count == (code == .cancelled ? 1 : 3))
        }

        @Test(
            arguments: Format.allCases,
            [(URLError.Code.networkConnectionLost, Outcome.urlError(.networkConnectionLost)), (.timedOut, .timeout)])
        func `a connection that drops mid-stream throws the matching error, without a retry`(
            format: Format, failure: (code: URLError.Code, outcome: Outcome)
        ) async {
            let stub = HTTPStub(format.startedAnswer.droppingConnection(with: URLError(failure.code)), .json("{}"))

            let error = await #expect(throws: (any Error).self) { try await format.respond(stub) }

            #expect(failure.outcome.matches(error), "Got \(String(describing: error))")
            #expect(stub.requests.count == 1)
        }

        @Test func `an error event in the stream isn't retried, since the answer already started`() async {
            let stub = HTTPStub(
                chatCompletionsEvents(["choices": [["delta": ["content": "Hi"]]]], ["error": ["message": "Overloaded."]]), answer)

            await #expect(throws: RequestFailure<APIErrorBody>.self) {
                _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hi")
            }

            #expect(stub.requests.count == 1)
        }

        @Test func `an error the authentication throws passes through as it is, before any request`() async {
            struct KeychainLocked: Error {}
            let stub = HTTPStub(answer)
            let authentication = Connection.Authentication.apiKey({ throw KeychainLocked() }, baseURL: nil, header: { _ in [:] })

            await #expect(throws: KeychainLocked.self) {
                _ = try await LanguageModelSession(model: plainModel(stub, authentication: authentication)).respond(to: "Hi")
            }

            #expect(stub.requests.isEmpty)
        }

        @Test(arguments: [(URLError.Code.notConnectedToInternet, Outcome.urlError(.notConnectedToInternet)), (.timedOut, .timeout)])
        func `a URLError the authentication throws is thrown as a failed connection's is`(code: URLError.Code, outcome: Outcome) async {
            let stub = HTTPStub(answer)
            let authentication = Connection.Authentication.apiKey({ throw URLError(code) }, baseURL: nil, header: { _ in [:] })

            let error = await #expect(throws: (any Error).self) {
                _ = try await LanguageModelSession(model: plainModel(stub, authentication: authentication)).respond(to: "Hi")
            }

            #expect(outcome.matches(error), "Got \(String(describing: error))")
        }
    }
}

extension HTTPClient.Retry.Cause {
    fileprivate var status: HTTPStatus? {
        if case .response(let status) = self { status } else { nil }
    }

    fileprivate var errorCode: URLError.Code? {
        if case .connection(let error) = self { error.code } else { nil }
    }
}
