import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Request")
    struct Request {
        @Test func `the format writes its members in a fixed order`() throws {
            let options = GenerationOptions(
                samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 10)
            let request = generationRequest([prompt(text("Hi"))], options: options, metadata: ["team": "coach"])

            let body = try ChatCompletionsSentRequest(request).body

            #expect(keys(body) == ["model", "messages", "stream", "temperature", "top_p", "seed", "max_completion_tokens", "metadata"])
            #expect(body["model"] == "vendor/model")
            #expect(body["stream"] == true)
        }

        @Test func `the exchange adds its members, in the model's order`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.members = ["models": ["vendor/fallback"], "plugins": []] }

            let body = try ChatCompletionsSentRequest(generationRequest([prompt(text("Hi"))]), model: model).body

            #expect(keys(body) == ["model", "models", "messages", "stream", "plugins"])
        }

        @Test func `members the models don't list are left out and noted in body order, before metadata left out`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.movedEffort = .init(requested: "medium", sent: "low") }
            model.unsupportedMembers = [.temperature, .maxCompletionTokens]
            let options = GenerationOptions(
                samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 10)
            let request = generationRequest([prompt(text("Hi"))], options: options, metadata: ["count": 3])

            let completion = try ChatCompletionsSentRequest(request, model: model)

            #expect(keys(completion.body) == ["model", "messages", "stream", "top_p", "seed"])
            #expect(
                completion.adjustments == [
                    .unlistedParameters(["temperature", "max_completion_tokens"]), .droppedMetadata(keys: ["count"]),
                    .movedEffort(requested: "medium", sent: "low"),
                ])
        }

        @Test func `the last instructions' last part carries the exchange's marks`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.prepares = { $0.instructionsMark = ["cache_control": ["type": "ephemeral"]] }
            let entries: [Transcript.Entry] = [
                .instructions(Transcript.Instructions(segments: [text("Be brief.")], toolDefinitions: [])), prompt(text("Hi")),
            ]

            let sent = messages(try ChatCompletionsSentRequest(generationRequest(entries), model: model).body)

            #expect(sent.first?["content"] == [["type": "text", "text": "Be brief.", "cache_control": ["type": "ephemeral"]]])
        }
    }
}
