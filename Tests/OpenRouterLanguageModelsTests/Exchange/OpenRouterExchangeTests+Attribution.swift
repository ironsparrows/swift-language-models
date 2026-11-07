import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("App attribution")
    struct Attribution {
        @Test func `the app's name, website, first two categories and visibility go in OpenRouter's headers`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let details = OpenRouterModel<Efforts.Unsupported>(
                id: "vendor/model", displayName: "Vendor: Model", releaseDate: .distantPast, supportedParameters: chatParameters)
            let app = OpenRouterApp(
                name: "Coach", url: URL(string: "https://coach.example"), categories: [.personalAgent, .generalChat, .writingAssistant],
                isHidden: true)
            let model = OpenRouterLanguageModel(
                details, app: app, session: stub.session, auth: .apiKey(baseURL: stub.baseURL) { "sk-or-test" })

            _ = try await LanguageModelSession(model: model).respond(to: "Hi")

            let request = try #require(stub.requests.first).request
            #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://coach.example")
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Title") == "Coach")
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Categories") == "personal-agent,general-chat")
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-App-Visibility") == "hidden")
        }

        @Test func `an app without categories that isn't hidden sends neither header`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            try await respond(stub)

            let request = try #require(stub.requests.first).request
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-Categories") == nil)
            #expect(request.value(forHTTPHeaderField: "X-OpenRouter-App-Visibility") == nil)
        }

        @Test func `the model reads back its app, base URL, session and idle timeout, and so does the open form`() throws {
            let app = OpenRouterApp(name: "Coach", url: URL(string: "https://coach.example"), categories: [.personalAgent])
            let baseURL = try #require(URL(string: "https://proxy.example/openrouter/"))
            let session = URLSession(configuration: .ephemeral)
            let model = OpenRouterLanguageModel(
                fallback("openai/gpt-5-mini"), app: app, session: session,
                configuration: OpenRouterConfiguration(idleTimeout: .seconds(90)),
                auth: .proxied(baseURL: baseURL))

            #expect(model.app == app)
            #expect(model.auth.baseURL == baseURL)
            #expect(model.session === session)
            #expect(model.configuration.idleTimeout == .seconds(90))
            let open = OpenRouterLanguageModel(model)
            #expect(open.app == app)
            #expect(open.auth.baseURL == baseURL)
            #expect(open.session === session)
            #expect(open.configuration.idleTimeout == .seconds(90))
        }

        @Test func `a model without settings names no app and keeps OpenRouter's address, the shared session and its timeout`() {
            let model = OpenRouterLanguageModel(fallback("openai/gpt-5-mini"), auth: .apiKey { "sk-or-test" })

            #expect(model.app == OpenRouterApp())
            #expect(model.auth.baseURL == nil)
            #expect(model.session === URLSession.shared)
            #expect(model.configuration.idleTimeout == nil)
        }

        @Test func `a change to the configuration applies to the next request`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()), events(text("Hi"), done()))
            let details = OpenRouterModel<Efforts.Unsupported>(
                id: "vendor/model", displayName: "Vendor: Model", releaseDate: .distantPast, supportedParameters: chatParameters)
            var model = OpenRouterLanguageModel(details, session: stub.session, auth: .apiKey(baseURL: stub.baseURL) { "sk-or-test" })

            _ = try await LanguageModelSession(model: model).respond(to: "Hi")
            model.configuration.idleTimeout = .seconds(7)
            _ = try await LanguageModelSession(model: model).respond(to: "Hi")

            #expect(model.executorConfiguration.settings.idleTimeout == .seconds(7))
            #expect(stub.requests.map(\.request.timeoutInterval).last == 7)
        }
    }
}
