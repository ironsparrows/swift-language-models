import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

@Suite("Chat Completions request")
struct ChatCompletionsRequestTests {
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

    @Test func `a schema goes as strict structured outputs, with a portable body for a host that rejects a constraint`() throws {
        let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

        let completion = try ChatCompletionsSentRequest(request)

        let format = try #require(completion.body["response_format"])
        #expect(format["type"] == "json_schema")
        #expect(format["json_schema"]?["name"] == "Rating")
        #expect(format["json_schema"]?["strict"] == true)
        #expect(format["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == 5)
        let portable = try #require(completion.portableSchemaBody?["response_format"]?["json_schema"]?["schema"])
        #expect(portable["properties"]?["stars"]?["maximum"] == nil)
    }

    @Test func `an exchange that sends the portable schema from the start has no body to retry with`() throws {
        var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
        model.exchange.prepares = { $0.usesPortableSchema = true }
        let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

        let completion = try ChatCompletionsSentRequest(request, model: model)

        #expect(completion.body["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
        #expect(completion.portableSchemaBody == nil)
    }

    @Test func `tools go as functions, with the tool choice the options ask for`() throws {
        let request = generationRequest(
            [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())],
            options: GenerationOptions(toolCallingMode: .required))

        let body = try ChatCompletionsSentRequest(request).body

        #expect(body["tools"]?[0]?["type"] == "function")
        #expect(body["tools"]?[0]?["function"]?["name"] == "lookUp")
        #expect(body["tool_choice"] == "required")
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
