import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

@Suite("Responses request")
struct ResponsesRequestTests {
    @Test func `the format writes its members in a fixed order, leaves out a seed and raises a token limit below 16`() throws {
        let options = GenerationOptions(
            samplingMode: .random(probabilityThreshold: 0.5, seed: 1), temperature: 0.2, maximumResponseTokens: 10)
        let request = generationRequest([prompt(text("Hi"))], options: options, metadata: ["team": "coach"])

        let sent = try SentRequest(request)

        #expect(keys(sent.body) == ["model", "input", "stream", "temperature", "top_p", "max_output_tokens", "metadata"])
        #expect(sent.body["model"] == "vendor/model")
        #expect(sent.body["stream"] == true)
        #expect(sent.body["max_output_tokens"] == 16)
        #expect(sent.adjustments == [.unsentSettings(["seed"]), .raisedTokenLimit(requested: 10, sent: 16)])
    }

    @Test func `the exchange's members go after the format's, in the order it writes them`() throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.exchange.prepares = { $0.members = ["service_tier": "flex", "prompt_cache_key": "session"] }

        let body = try SentRequest(generationRequest([prompt(text("Hi"))]), model: model).body

        #expect(keys(body) == ["model", "input", "stream", "service_tier", "prompt_cache_key"])
    }

    @Test func `the exchange's storage, encrypted reasoning, reasoning and text members go out in the format's places`() throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.exchange.prepares = { request in
            request.storage = .notStored
            request.asksForEncryptedReasoning = true
            request.reasoning = .init(effort: "low", summary: "auto")
            request.textMembers = ["verbosity": "low"]
        }
        let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

        let body = try SentRequest(request, model: model).body

        #expect(keys(body) == ["model", "input", "stream", "store", "include", "text", "reasoning"])
        #expect(body["store"] == false)
        #expect(body["include"] == ["reasoning.encrypted_content"])
        #expect(keys(body["text"]) == ["format", "verbosity"])
        #expect(keys(body["text"]?["format"]) == ["type", "name", "schema", "strict"])
        #expect(body["text"]?["format"]?["type"] == "json_schema")
        #expect(body["text"]?["format"]?["strict"] == true)
        #expect(body["text"]?["verbosity"] == "low")
        #expect(body["reasoning"] == ["effort": "low", "summary": "auto"])
    }

    @Test func `storage the provider keeps sends store, and the provider's default sends none`() throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.exchange.prepares = { request in
            request.storage = .stored
            request.reasoning = .init()
        }

        let stored = try SentRequest(generationRequest([prompt(text("Hi"))]), model: model).body
        let automatic = try SentRequest(generationRequest([prompt(text("Hi"))])).body

        #expect(stored["store"] == true)
        #expect(stored["reasoning"] == nil)
        #expect(automatic["store"] == nil)
    }

    @Test func `members the models don't list are left out, then settings the format has no member for`() throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.unsupportedMembers = [.temperature, .maxOutputTokens]
        let options = GenerationOptions(samplingMode: .random(top: 40, seed: 3), temperature: 0.2, maximumResponseTokens: 10)

        let sent = try SentRequest(generationRequest([prompt(text("Hi"))], options: options), model: model)

        // A token limit left out isn't raised.
        #expect(keys(sent.body) == ["model", "input", "stream"])
        #expect(sent.adjustments == [.unlistedParameters(["temperature", "max_output_tokens"]), .unsentSettings(["top_k", "seed"])])
    }

    @Test func `members the exchange leaves out with the request's settings are noted`() throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.exchange.prepares = { request in
            request.leftOutMembers = [.temperature, .topP]
            request.movedEffort = .init(requested: "medium", sent: "low")
        }
        let options = GenerationOptions(temperature: 0.2)

        let sent = try SentRequest(generationRequest([prompt(text("Hi"))], options: options), model: model)

        #expect(sent.body["temperature"] == nil)
        #expect(sent.adjustments == [.unsentSettings(["temperature"]), .movedEffort(requested: "medium", sent: "low")])
    }

    @Test func `the session's tools go as functions whose arguments aren't held to the schema, with the tool choice`() throws {
        let request = generationRequest(
            [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())],
            options: GenerationOptions(toolCallingMode: .required))

        let body = try SentRequest(request).body

        #expect(keys(body) == ["model", "input", "stream", "tools", "tool_choice"])
        #expect(keys(body["tools"]?[0]) == ["type", "name", "description", "parameters", "strict"])
        #expect(body["tools"]?[0]?["name"] == "lookUp")
        #expect(body["tools"]?[0]?["strict"] == false)
        #expect(body["tool_choice"] == "required")
    }

    @Test func `an exchange that leaves the session's tools out sends neither tools nor tool choice`() throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.exchange.prepares = { $0.sendsSessionTools = false }
        let request = generationRequest(
            [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())],
            options: GenerationOptions(toolCallingMode: .required))

        let body = try SentRequest(request, model: model).body

        #expect(body["tools"] == nil)
        #expect(body["tool_choice"] == nil)
    }

    @Test func `server tools go after the session's, and the tool choice only with the session's`() throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.exchange.prepares = { $0.serverTools = [["type": "web_search"]] }
        let options = GenerationOptions(toolCallingMode: .required)
        let withSessionTool = generationRequest(
            [prompt(text("Hi"))], tools: [Transcript.ToolDefinition(tool: LookUpTool())], options: options)

        let both = try SentRequest(withSessionTool, model: model).body
        let alone = try SentRequest(generationRequest([prompt(text("Hi"))], options: options), model: model).body

        #expect(both["tools"]?[0]?["name"] == "lookUp")
        #expect(both["tools"]?[1] == ["type": "web_search"])
        #expect(both["tool_choice"] == "required")
        #expect(alone["tools"] == [["type": "web_search"]])
        #expect(alone["tool_choice"] == nil)
    }

    @Test func `a schema goes in full, with the portable schema ready`() throws {
        let request = generationRequest([prompt(text("Rate it."))], schema: Rating.generationSchema)

        let sent = try SentRequest(request)

        #expect(sent.body["text"]?["format"]?["schema"]?["properties"]?["stars"]?["maximum"] == 5)
        #expect(sent.portableSchemaBody?["text"]?["format"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
        #expect(sent.portableSchemaBody?["text"]?["format"]?["schema"]?["properties"]?["stars"]?["description"] != nil)
    }
}
