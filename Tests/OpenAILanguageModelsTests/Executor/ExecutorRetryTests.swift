import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels
@testable import OpenAILanguageModels

/// OpenAI's requests retry as the official SDKs do, with the stubs' models waiting for nothing between retries.
@Suite("Executor: retries")
struct ExecutorRetryTests {
    @Test(arguments: [408, 409, 429, 500, 502, 503, 504, 529])
    func `a status the official SDKs retry is retried twice`(status: Int) async throws {
        let stub = HTTPStub(failure(status), failure(status), answer())

        #expect(try await respond(stub) == "Hi.")
        #expect(stub.requests.count == 3)
    }

    @Test(arguments: [400, 401, 403, 404, 422])
    func `a client error isn't retried`(status: Int) async throws {
        let stub = HTTPStub(failure(status), answer())

        let error = try await #require(throws: OpenAIError.self) { try await respond(stub) }

        #expect(error.status == status)
        #expect(stub.requests.count == 1)
    }

    @Test func `x-should-retry true retries a status that isn't retried otherwise`() async throws {
        let stub = HTTPStub(failure(400, headers: ["x-should-retry": "true"]), answer())

        #expect(try await respond(stub) == "Hi.")
        #expect(stub.requests.count == 2)
    }

    @Test func `x-should-retry false fails at once`() async throws {
        let stub = HTTPStub(failure(503, headers: ["x-should-retry": "false"]), answer())

        let error = try await #require(throws: OpenAIError.self) { try await respond(stub) }

        #expect(error.status == 503)
        #expect(stub.requests.count == 1)
    }

    @Test func `a rate limit that asks to wait more than 2 minutes fails at once, with the wait`() async throws {
        let stub = HTTPStub(failure(429, headers: ["Retry-After": "300"]), answer())

        let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

        guard case .rateLimited(let context) = error, let reset = context.resetDate else {
            Issue.record("Threw \(error)")
            return
        }
        #expect(reset.timeIntervalSinceNow > 290)
        #expect(stub.requests.count == 1)
    }

    @Test(arguments: [
        (HTTPHeaderName.retryAfter, "90", Duration.seconds(90)),
        (.retryAfter, "120", .seconds(120)),
        (.retryAfterMilliseconds, "1500", .milliseconds(1_500)),
    ])
    func `a retry waits as long as OpenAI asks, up to 2 minutes, as openai-python does`(
        header: HTTPHeaderName, value: String, wait: Duration
    ) throws {
        let url = try #require(URL(string: "https://api.openai.com/v1/responses"))
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: [header.rawValue: value])

        #expect(RequestRetries.standard.policy(statuses: API.retriesStatus).retry(1, status: 429, response: response)?.wait == wait)
    }

    @Test func `the configuration's retry limit caps the retries`() async throws {
        let stub = HTTPStub(failure(503), failure(503), answer())
        var limited = reasoningModel(stub)
        limited.configuration.retries.limit = 1

        let error = try await #require(throws: OpenAIError.self) {
            try await LanguageModelSession(model: limited).respond(to: "Hi")
        }

        #expect(error.status == 503)
        #expect(stub.requests.count == 2)
    }

    @Test func `disabled retries send a failed request once`() async throws {
        let stub = HTTPStub(failure(503), answer())
        var model = reasoningModel(stub)
        model.configuration.retries = .disabled

        await #expect(throws: OpenAIError.self) { try await LanguageModelSession(model: model).respond(to: "Hi") }

        #expect(stub.requests.count == 1)
    }

    @Test func `a wait past the configuration's longest server wait fails at once, with the wait`() async throws {
        let stub = HTTPStub(failure(503, headers: ["Retry-After": "10"]), answer())
        var model = reasoningModel(stub)
        model.configuration.retries.longestServerWait = .seconds(5)

        let error = try await #require(throws: OpenAIError.self) { try await LanguageModelSession(model: model).respond(to: "Hi") }

        #expect(error.retryAfter == .seconds(10))
        #expect(stub.requests.count == 1)
    }

    @Test func `a model's default configuration retries twice and waits up to 10 minutes for data`() {
        let configuration = OpenAILanguageModel(.gpt6Luna, auth: .apiKey { "" }).configuration

        #expect(configuration.retries == .standard)
        #expect(configuration.retries.limit == 2)
        #expect(configuration.idleTimeout == .seconds(600))
        #expect(configuration.images == .standard)
    }

    @Test(arguments: [URLError.Code.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet])
    func `a failed connection is retried twice`(code: URLError.Code) async throws {
        let stub = HTTPStub(.failure(URLError(code)), .failure(URLError(code)), answer())

        #expect(try await respond(stub) == "Hi.")
        #expect(stub.requests.count == 3)
    }

    @Test func `a dropped stream isn't retried, since the answer already started`() async throws {
        let stub = HTTPStub(
            responseStream([created()], [textDelta("Hel")]).droppingConnection(with: URLError(.networkConnectionLost)), answer())

        let error = try await #require(throws: URLError.self) { try await respond(stub) }

        #expect(error.code == .networkConnectionLost)
        #expect(stub.requests.count == 1)
    }

    private func respond(_ stub: HTTPStub) async throws -> String {
        try await LanguageModelSession(model: reasoningModel(stub)).respond(to: "Hi").content
    }

    private func answer() -> StubResponse {
        responseStream([created()], [textDelta("Hi."), completed()])
    }

    private func failure(_ status: Int, headers: [String: String] = [:]) -> StubResponse {
        .json(#"{"error":{"message":"Failed.","type":"server_error"}}"#, status: status, headers: headers)
    }
}
