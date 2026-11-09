import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension OpenAICompatibleExchangeTests {
    @Suite("Authentication")
    struct Authentication {
        @Test(
            arguments: [
                (OpenAICompatibleProvider.KeyHeader.bearer, "Authorization", "Bearer sk-test"),
                (.named("api-key"), "api-key", "sk-test"),
            ] as [(OpenAICompatibleProvider.KeyHeader, String, String)])
        func `an API key goes in the provider's key header`(keyHeader: OpenAICompatibleProvider.KeyHeader, name: String, value: String)
            async throws
        {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: provider(stub, keyHeader: keyHeader))).respond(to: "Hi")

            #expect(stub.requests[0].request.value(forHTTPHeaderField: name) == value)
        }

        @Test(
            arguments: [
                (OpenAICompatibleProvider.Format.chatCompletions, OpenAICompatibleAuthentication.apiKey { "sk-test" }, "Bearer sk-test"),
                (.responses, .apiKey { "sk-test" }, "Bearer sk-test"),
                (.chatCompletions, .apiKey { "" }, "Bearer fixed"),
                (.chatCompletions, .unauthenticated, "Bearer fixed"),
            ] as [(OpenAICompatibleProvider.Format, OpenAICompatibleAuthentication, String)])
        func `the provider's headers go with every request, and a key header of the same name replaces one, whatever its case`(
            format: OpenAICompatibleProvider.Format, auth: OpenAICompatibleAuthentication, authorization: String
        ) async throws {
            let stub = HTTPStub(format == .responses ? events(textDelta("Hi"), completed()) : chunks(text("Hi"), finish()))
            let headers = ["X-Team": "meals", "authorization": "Bearer fixed"]

            _ = try await LanguageModelSession(model: model(stub, on: provider(stub, format: format, headers: headers), auth: auth))
                .respond(to: "Hi")

            #expect(stub.requests[0].request.value(forHTTPHeaderField: "X-Team") == "meals")
            #expect(stub.requests[0].request.value(forHTTPHeaderField: "Authorization") == authorization)
        }

        @Test func `a proxy's URL and headers stand in for the provider's, with the provider's headers kept`() async throws {
            let proxy = HTTPStub(chunks(text("Hi"), finish()))
            let unreached = HTTPStub()
            let model = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("test-model", on: provider(unreached, headers: ["X-Team": "meals"])), session: proxy.session,
                auth: .proxied(baseURL: proxy.baseURL, headers: { ["X-App-Token": "app-1"] }))

            _ = try await LanguageModelSession(model: model).respond(to: "Hi")

            let request = try #require(proxy.requests.first?.request)
            #expect(request.url?.host() == proxy.baseURL.host())
            #expect(request.value(forHTTPHeaderField: "X-App-Token") == "app-1")
            #expect(request.value(forHTTPHeaderField: "X-Team") == "meals")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(unreached.requests.isEmpty)
        }

        @Test func `headers without a base URL go to the provider's own URL, as a gateway described as the provider takes them`()
            async throws
        {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, auth: .proxied(headers: { ["X-App-Token": "app-1"] }))).respond(to: "Hi")

            #expect(stub.requests[0].request.value(forHTTPHeaderField: "X-App-Token") == "app-1")
            #expect(stub.requests[0].request.url?.path == "/chat/completions")
        }

        @Test func `a provider at another address keeps everything else it does`() throws {
            let other = try #require(URL(string: "https://gateway.example.com/v1"))
            let original = OpenAICompatibleProvider(
                name: "Gateway", url: try #require(URL(string: "https://api.example.com/v1")), format: .responses,
                keyHeader: .named("api-key"),
                headers: ["X-Team": "meals"])

            let moved = original.at(other)

            #expect(moved.url == other)
            #expect(
                moved
                    == OpenAICompatibleProvider(
                        name: "Gateway", url: other, format: .responses, keyHeader: .named("api-key"), headers: ["X-Team": "meals"]))
        }
    }
}
