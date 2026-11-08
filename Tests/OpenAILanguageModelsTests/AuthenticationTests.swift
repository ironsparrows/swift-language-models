import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

@Suite("Authentication", .timeLimit(.minutes(1)))
struct AuthenticationTests {
    @Test func `an API key goes as a bearer token, with the organization and project when they're set`() async throws {
        let plain = try await sentRequest { .apiKey(baseURL: $0) { "sk-test" } }
        let scoped = try await sentRequest { .apiKey(baseURL: $0, organization: "org-1", project: "proj-1") { "sk-test" } }

        #expect(plain.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(plain.value(forHTTPHeaderField: "OpenAI-Organization") == nil)
        #expect(plain.value(forHTTPHeaderField: "OpenAI-Project") == nil)
        #expect(scoped.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(scoped.value(forHTTPHeaderField: "OpenAI-Organization") == "org-1")
        #expect(scoped.value(forHTTPHeaderField: "OpenAI-Project") == "proj-1")
    }

    @Test func `an empty key sends no headers at all`() async throws {
        let request = try await sentRequest { .apiKey(baseURL: $0, organization: "org-1") { "" } }

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "OpenAI-Organization") == nil)
    }

    @Test func `a key with a base URL and a proxied server go to their own URLs`() throws {
        let url = try #require(URL(string: "https://gateway.example.com/v1/"))

        #expect(OpenAIAuthentication.apiKey(baseURL: url) { "sk-test" }.baseURL == url)
        #expect(OpenAIAuthentication.proxied(baseURL: url).baseURL == url)
        #expect(OpenAIAuthentication.apiKey { "sk-test" }.baseURL == nil)
    }

    @Test func `requests go to the responses path under the base URL, with the proxy's headers`() async throws {
        let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
        let languageModel = OpenAILanguageModel(
            details: details(efforts: [ContextOptions.ReasoningLevel.low]), serverTools: [], options: OpenAIOptions(),
            session: stub.session,
            auth: .proxied(baseURL: stub.baseURL) { ["X-App-Token": "app-1"] },
            configuration: .stubbed)

        _ = try await LanguageModelSession(model: languageModel).respond(to: "Hi")

        let request = try #require(stub.requests.first?.request)
        #expect(request.url?.path == "/responses")
        #expect(request.value(forHTTPHeaderField: "X-App-Token") == "app-1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

/// The request a model sends with an authentication, made for the stub's URL.
private func sentRequest(_ auth: (URL) -> OpenAIAuthentication) async throws -> URLRequest {
    let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
    let languageModel = OpenAILanguageModel(
        details: details(efforts: [ContextOptions.ReasoningLevel.low]), serverTools: [], options: OpenAIOptions(), session: stub.session,
        auth: auth(stub.baseURL), configuration: .stubbed)

    _ = try await LanguageModelSession(model: languageModel).respond(to: "Hi")

    return try #require(stub.requests.first).request
}
