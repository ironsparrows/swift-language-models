import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Text")
    struct Text {
        @Test func `a request carries the key, the app's name and the session's id`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            try await respond(stub)

            let request = try #require(stub.requests.first)
            #expect(request.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
            #expect(request.request.value(forHTTPHeaderField: "X-OpenRouter-Title") == "Coach")
            #expect(try body(request)["session_id"]?.stringValue?.isEmpty == false)
        }

        @Test func `the cost and the host reach the response`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            #expect(metadataNumber(response.usage.metadata, "cost") == 0.000_25)
            #expect(metadataString(try lastResponse(of: response).metadata, "provider") == "Vendor")
        }

        @Test func `the latest host in the stream wins`() async throws {
            let stub = HTTPStub(events(text("Hi"), adding(["provider": "Other"], to: done())))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            #expect(metadataString(try lastResponse(of: response).metadata, "provider") == "Other")
        }

        @Test func `a request turns context compression off, even for a model whose context is large`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            try await respond(stub)

            #expect(try body(stub)["plugins"] == [["id": "context-compression", "enabled": false]])
        }

        @Test func `generation options become the parameters the model lists`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub, parameters: [.temperature, .topK, .seed, .maxTokens]))

            _ = try await session.respond(
                to: "Hi",
                options: GenerationOptions(samplingMode: .random(top: 40, seed: 7), temperature: 0.5, maximumResponseTokens: 100_000)
            )

            let body = try body(stub)
            #expect(body["temperature"] == 0.5)
            #expect(body["top_k"] == 40)
            #expect(body["seed"] == 7)
            #expect(body["max_tokens"] == 100_000)
            #expect(body["max_completion_tokens"] == nil)
        }

        @Test func `greedy sampling asks for the single most likely token`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Hi", options: GenerationOptions(samplingMode: .greedy))

            #expect(try body(stub)["top_k"] == 1)
        }

        @Test func `greedy sampling with tools doesn't ask for the single most likely token, so no host is ruled out`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            _ = try await session.respond(to: "Hi", options: GenerationOptions(samplingMode: .greedy))

            #expect(try body(stub)["top_k"] == nil)
        }

        @Test func `a setting the model doesn't list is left out`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub, parameters: [.maxTokens]))

            _ = try await session.respond(
                to: "Hi", options: GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9), temperature: 0.5))

            let body = try body(stub)
            #expect(body["temperature"] == nil)
            #expect(body["top_p"] == nil)
        }

        @Test func `OpenRouter options are sent when the model lists them`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let options = OpenRouterOptions(
                frequencyPenalty: 0.5, minP: 0.1, stopSequences: ["END"], serviceTier: .flex, endUserID: "user-1")
            let session = LanguageModelSession(model: model(stub, parameters: [.frequencyPenalty, .stop], options: options))

            _ = try await session.respond(to: "Hi")

            let body = try body(stub)
            #expect(body["frequency_penalty"] == 0.5)
            #expect(body["stop"] == ["END"])
            #expect(body["min_p"] == nil)
            #expect(body["service_tier"] == "flex")
            #expect(body["user"] == "user-1")
        }

        @Test(arguments: [
            (Set<OpenRouterParameter>([.verbosity]), JSONValue?.some("xhigh")),
            (Set<OpenRouterParameter>([.temperature]), nil),
        ])
        func `verbosity is sent only when the model lists it`(parameters: Set<OpenRouterParameter>, verbosity: JSONValue?) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let options = OpenRouterOptions(verbosity: .xhigh)

            _ = try await LanguageModelSession(model: model(stub, parameters: parameters, options: options)).respond(to: "Hi")

            #expect(try body(stub)["verbosity"] == verbosity)
        }
    }
}
