import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Text")
    struct Text {
        @Test func `a streamed answer becomes the response`() async throws {
            let stub = HTTPStub(events(text("Hello"), text(", world"), done()))
            let session = LanguageModelSession(model: model(stub), instructions: "Be brief.")

            let response = try await session.respond(to: "Say hello.")

            #expect(response.content == "Hello, world")
            let request = try #require(stub.requests.first)
            #expect(request.request.url?.path() == "/chat/completions")
            #expect(request.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
            #expect(request.request.value(forHTTPHeaderField: "X-OpenRouter-Title") == "Coach")
            let body = try body(request)
            #expect(body["model"] == "vendor/model")
            #expect(body["stream"] == true)
            #expect(messages(body) == [["content": "Be brief.", "role": "system"], ["content": "Say hello.", "role": "user"]])
            #expect(body["tools"] == nil)
            #expect(body["session_id"]?.stringValue?.isEmpty == false)
        }

        @Test func `a stream gives growing snapshots`() async throws {
            let stub = HTTPStub(events(text("One"), text(" two"), text(" three"), done()))
            let session = LanguageModelSession(model: model(stub))

            var snapshots: [String] = []
            for try await snapshot in session.streamResponse(to: "Count.") {
                snapshots.append(snapshot.content)
            }

            #expect(snapshots.last == "One two three")
            #expect(snapshots.count >= 2)
        }

        @Test func `usage and metadata reach the response`() async throws {
            let stub = HTTPStub(events(text("Hi"), done(prompt: 1_200, cached: 1_024, cacheWrite: 176, completion: 40, reasoning: 8)))
            let session = LanguageModelSession(model: model(stub))

            let response = try await session.respond(to: "Hi")

            #expect(response.usage.input.totalTokenCount == 1_200)
            #expect(response.usage.input.cachedTokenCount == 1_024)
            #expect(response.usage.output.totalTokenCount == 40)
            #expect(response.usage.output.reasoningTokenCount == 8)
            #expect(metadataNumber(response.usage.metadata, LanguageModelMetadataKey.cost) == 0.000_25)
            #expect(metadataNumber(response.usage.metadata, LanguageModelMetadataKey.cacheWriteTokenCount) == 176)
            let entry = try #require(response.transcriptEntries.last)
            guard case .response(let answer) = entry else {
                Issue.record("The last entry isn't a response: \(entry)")
                return
            }
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.model) == "vendor/model")
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.provider) == "Vendor")
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.responseID) == "gen-1")
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.finishReason) == "stop")
        }

        @Test func `an answer cut off at its token limit ends without an error, with length as its finish reason`() async throws {
            let stub = HTTPStub(events(text("The plan starts with"), done("length")))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Plan the week.")

            #expect(response.content == "The plan starts with")
            guard case .response(let answer)? = response.transcriptEntries.last else {
                Issue.record("The last entry isn't a response: \(response.transcriptEntries)")
                return
            }
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.finishReason) == "length")
        }

        @Test func `the latest model, host and generation id in the stream win`() async throws {
            let choice: JSONValue = ["index": 0, "delta": [:], "finish_reason": "stop"]
            let last: JSONValue = ["id": "gen-2", "model": "vendor/model-2", "provider": "Other", "choices": [choice]]
            let stub = HTTPStub(events(text("Hi"), last))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            guard case .response(let answer)? = response.transcriptEntries.last else {
                Issue.record("The last entry isn't a response: \(response.transcriptEntries)")
                return
            }
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.model) == "vendor/model-2")
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.provider) == "Other")
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.responseID) == "gen-2")
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
                options: GenerationOptions(samplingMode: .random(top: 40, seed: 7), temperature: 3, maximumResponseTokens: 100_000)
            )

            let body = try body(stub)
            #expect(body["temperature"] == 2)
            #expect(body["top_k"] == 40)
            #expect(body["seed"] == 7)
            #expect(body["max_tokens"] == 100_000)
            #expect(body["max_completion_tokens"] == nil)
            #expect(body["top_p"] == nil)
        }

        @Test(arguments: [
            (UInt64(7), JSONValue.integer(7)),
            (UInt64(Int64.max), .integer(Int(Int64.max))),
            (UInt64(1) << 63, .integer(0)),
            ((UInt64(1) << 63) + 7, .integer(7)),
            (UInt64.max, .integer(Int(Int64.max))),
        ])
        func `every seed is sent, a large one without its top bit`(seed: UInt64, sent: JSONValue) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(
                to: "Hi", options: GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9, seed: seed)))

            #expect(try body(stub)["seed"] == sent)
        }

        @Test func `greedy sampling is temperature zero and the single most likely token`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Hi", options: GenerationOptions(samplingMode: .greedy, temperature: 0.8))

            let body = try body(stub)
            #expect(body["temperature"] == 0)
            #expect(body["top_k"] == 1)
        }

        @Test func `greedy sampling with tools is temperature zero alone, so no host is ruled out`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

            _ = try await session.respond(to: "Hi", options: GenerationOptions(samplingMode: .greedy))

            let body = try body(stub)
            #expect(body["temperature"] == 0)
            #expect(body["top_k"] == nil)
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
