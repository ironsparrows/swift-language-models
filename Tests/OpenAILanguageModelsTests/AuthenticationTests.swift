import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels
@testable import OpenAILanguageModels

@Suite("Authentication")
struct AuthenticationTests {
    @Test func `an API key goes as a bearer token, with the organization and project when they're set`() async throws {
        let plain = try await OpenAIAuthentication.apiKey { "sk-test" }.requestAuthentication.requestHeaders()
        let scoped = try await OpenAIAuthentication.apiKey(organization: "org-1", project: "proj-1") { "sk-test" }
            .requestAuthentication.requestHeaders()

        #expect(plain == [.authorization: "Bearer sk-test"])
        #expect(scoped == [.authorization: "Bearer sk-test", "OpenAI-Organization": "org-1", "OpenAI-Project": "proj-1"])
    }

    @Test func `an empty key sends no headers at all`() async throws {
        let headers = try await OpenAIAuthentication.apiKey(organization: "org-1") { "" }.requestAuthentication.requestHeaders()

        #expect(headers.isEmpty)
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
            details: details(efforts: [ContextOptions.ReasoningLevel.low]), options: OpenAIOptions(), session: stub.session,
            auth: .proxied(baseURL: stub.baseURL) { ["X-App-Token": "app-1"] },
            configuration: .stubbed)

        _ = try await LanguageModelSession(model: languageModel).respond(to: "Hi")

        let request = try #require(stub.requests.first?.request)
        #expect(request.url?.path == "/responses")
        #expect(request.value(forHTTPHeaderField: "X-App-Token") == "app-1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
