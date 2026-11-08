import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterOptionsTests {
    @Suite("Settings")
    struct Settings {
        @Test func `a setting goes in the body only when every model lists its parameter`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let options = OpenRouterOptions(
                frequencyPenalty: 0.5, presencePenalty: 0.2, stopSequences: ["END"], logitBias: [50_256: -100, 13: 2.5], verbosity: .low,
                serviceTier: .flex, endUserID: "user-1")
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(
                stub, parameters: [.frequencyPenalty, .stop, .logitBias], cacheControl: nil, options: options)

            _ = try await LanguageModelSession(model: model).respond(to: "Hi")

            let sent = String(decoding: try #require(stub.requests.first).body, as: UTF8.self)
            let settings = ["frequency_penalty", "presence_penalty", "stop", "logit_bias", "verbosity", "service_tier", "user"]
                .compactMap { name in sent.range(of: #""\#(name)":"#).map { (name: name, place: $0.lowerBound) } }
                .sorted { $0.place < $1.place }.map(\.name)
            #expect(settings == ["frequency_penalty", "stop", "logit_bias", "service_tier", "user"])
            #expect(try body(stub)["logit_bias"]?.text == #"{"13":2.5,"50256":-100}"#)
        }

        @Test func `a token limit is left out when the models list neither of its parameters`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, parameters: [.temperature])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", options: GenerationOptions(maximumResponseTokens: 100))

            let body = try body(stub)
            #expect(body["max_tokens"] == nil)
            #expect(body["max_completion_tokens"] == nil)
        }

        @Test(arguments: [([.temperature], 0), ([.topK], nil)] as [(Set<OpenRouterParameter>, JSONValue?)])
        func `greedy sampling is left out only when the models don't list temperature`(
            parameters: Set<OpenRouterParameter>,
            temperature: JSONValue?
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, parameters: parameters)

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", options: GenerationOptions(samplingMode: .greedy))

            #expect(try body(stub)["temperature"] == temperature)
        }
    }
}
