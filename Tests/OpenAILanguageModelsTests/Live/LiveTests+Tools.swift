import Foundation
import FoundationModels
import LanguageModelsTestSupport
import OpenAILanguageModels
import Testing

@testable import LanguageModels

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite("Tools")
    struct Tools {
        /// A prompt that needs the weather in three cities.
        static let threeCities = "What's the temperature in Lisbon, Porto and Madrid? Use the tool for each city."

        // GPT-5 nano doesn't always call the tool for every city.
        @Test(arguments: [LiveModel.luna])
        func `parallel tool calls form rounds, and the answer uses every output`(model: LiveModel) async throws {
            let session = LanguageModelSession(
                model: try model.languageModel(options: OpenAIOptions(parallelToolCalls: .allowed)), tools: [WeatherTool()])

            let response = try await session.respond(to: Self.threeCities, contextOptions: model.quickContext)

            #expect(Set(try session.transcript.weatherCities()) == ["Lisbon", "Porto", "Madrid"])
            let ids = session.transcript.toolCalls.map(\.id)
            #expect(Set(ids).count == ids.count)
            #expect(response.content.contains("17"))
        }

        @Test func `calls that aren't parallel come one per round`() async throws {
            let session = LanguageModelSession(
                model: try LiveModel.nano.languageModel(options: OpenAIOptions(parallelToolCalls: .disallowed)), tools: [WeatherTool()])

            let response = try await session.respond(to: Self.threeCities, contextOptions: LiveModel.nano.quickContext)

            for case .toolCalls(let calls) in session.transcript { #expect(calls.count == 1) }
            #expect(Set(try session.transcript.weatherCities()) == ["Lisbon", "Porto", "Madrid"])
            #expect(response.content.contains("17"))
        }

        @Test(
            arguments: [
                (LiveModel.nano, OpenAIOptions.Storage.notStored), (.nano, .automatic), (.luna, .notStored), (.luna, .automatic),
            ] as [(LiveModel, OpenAIOptions.Storage)])
        func `reasoning items go back on later turns, encrypted, whether or not OpenAI keeps the response`(
            model: LiveModel, storage: OpenAIOptions.Storage
        ) async throws {
            let session = LanguageModelSession(
                model: try model.languageModel(options: OpenAIOptions(storage: storage)), tools: [WeatherTool()])

            let first = try await session.respond(
                to: "What's the temperature in Lisbon and Porto?", contextOptions: ContextOptions(reasoningLevel: .light))
            let second = try await session.respond(to: "And in Madrid?", contextOptions: ContextOptions(reasoningLevel: .light))

            #expect(first.content.contains("17"))
            #expect(second.content.contains("17"))
            let items = try reasoningEntries(in: session.transcript).flatMap { reasoning -> [JSONValue] in
                guard let signature = reasoning.signature, case .array(let items) = try JSONValue(json: signature) else { return [] }
                return items
            }
            // GPT-5 nano always reasons; GPT-6 Luna may not reason at all for easy calls.
            if model.quickLevel != .off { #expect(!items.isEmpty) }
            #expect(items.allSatisfy { $0["type"] == "reasoning" && $0["encrypted_content"]?.stringValue?.isEmpty == false })
            record(lastAnswer(in: session.transcript)?.metadata ?? [:], named: "metadata.txt")
        }

        @Test func `a session switched from stored to not stored responses still answers`() async throws {
            var model = try LiveModel.nano.languageModel()
            let first = LanguageModelSession(model: model, tools: [WeatherTool()])
            _ = try await first.respond(to: "What's the temperature in Lisbon?", contextOptions: ContextOptions(reasoningLevel: .light))
            model.options.storage = .notStored
            let second = LanguageModelSession(model: model, tools: [WeatherTool()], transcript: first.transcript)

            let response = try await second.respond(to: "And in Porto?", contextOptions: ContextOptions(reasoningLevel: .light))

            #expect(response.content.contains("17"))
        }

        // Reasoning goes back only to the model that wrote it, while each message keeps its phase, which models
        // without phases take too.
        @Test(arguments: [LiveModel.nano, .mini])
        func `a transcript continued on another model still answers`(model: LiveModel) async throws {
            let first = LanguageModelSession(model: try LiveModel.luna.languageModel(), tools: [WeatherTool()])
            _ = try await first.respond(to: "What's the temperature in Lisbon?", contextOptions: ContextOptions(reasoningLevel: .light))
            let second = LanguageModelSession(model: try model.languageModel(), tools: [WeatherTool()], transcript: first.transcript)

            let response = try await second.respond(to: "And in Porto?", contextOptions: model.quickContext)

            #expect(response.content.contains("17"))
        }

        @Test func `a required tool call is made`() async throws {
            let session = LanguageModelSession(model: try LiveModel.nano.languageModel(), tools: [InterruptingWeatherTool()])

            let response = try await respondUntilToolCall(
                session, to: "Say hello.", options: GenerationOptions(toolCallingMode: .required))

            #expect(response == nil)
            #expect(session.transcript.toolCalls.first?.toolName == "getWeather")
        }

        // GPT-6 Luna tells its preamble apart as commentary; GPT-5 nano, which has no message phases, may write the
        // preamble into the answer's JSON instead of calling the tool.
        @Test(arguments: [LiveModel.luna])
        func `a guided answer after a tool call decodes, whatever the model says before it`(model: LiveModel) async throws {
            let session = LanguageModelSession(
                model: try model.languageModel(), tools: [AccessCodeTool()],
                instructions: "Before you call a tool, say in one short sentence what you're about to do.")

            let response: LanguageModelSession.Response<AccessCode>
            do {
                response = try await session.respond(
                    to: "What's today's access code?", generating: AccessCode.self,
                    options: GenerationOptions(maximumResponseTokens: 4_000), contextOptions: model.quickContext)
            } catch let error as GeneratedContent.ParsingError {
                record(error.rawContent, named: "raw-content.txt")
                record(session.transcript, named: "transcript.txt")
                throw error
            }

            record(metadata(of: response).keys.sorted(), named: "metadata-keys.txt")
            #expect(response.content.code == "K7Q2")
        }

        @Test func `a tool without arguments is called with an empty object`() async throws {
            let session = LanguageModelSession(model: try LiveModel.nano.languageModel(), tools: [AccessCodeTool()])

            let response = try await session.respond(
                to: "Get the access code with the tool, then reply with it only.", contextOptions: LiveModel.nano.quickContext)

            #expect(response.content.contains("K7Q2"))
        }

        // A guided answer picks the message it decodes when the message starts, since its text streams before
        // `response.output_item.done`, so each message's phase must arrive with `response.output_item.added`.
        @Test func `a message's phase arrives when the message starts`() async throws {
            let key = APIKeyTrait.current ?? ""
            var request = URLRequest(url: try #require(URL(string: "https://api.openai.com/v1/responses")))
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let tool: JSONValue = [
                "type": "function", "name": "getAccessCode", "description": "Gets today's access code.",
                "parameters": ["type": "object", "properties": [:], "additionalProperties": false], "strict": false,
            ]
            let body: JSONValue = [
                "model": "gpt-6-luna", "stream": true, "tools": [tool], "reasoning": ["effort": "low"],
                "instructions": "Before you call a tool, say in one short sentence what you're about to do.",
                "input": "What's today's access code?",
            ]
            request.httpBody = body.data

            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            var startPhases: [Int: String] = [:]
            var endPhases: [Int: String] = [:]
            for try await event in ServerSentEvent.Events(bytes) {
                guard let json = try? JSONValue(json: Data(event.data.utf8)), json["item"]?["type"] == "message",
                    case .integer(let index)? = json["output_index"]
                else { continue }
                let phase = json["item"]?["phase"]?.stringValue ?? "none"
                if json["type"] == "response.output_item.added" { startPhases[index] = phase }
                if json["type"] == "response.output_item.done" { endPhases[index] = phase }
            }

            record(endPhases, named: "phases.txt")
            if endPhases.isEmpty { try Test.cancel("The model wrote no message before its call.") }
            #expect(startPhases == endPhases)
        }
    }
}

/// An access code, as a guided answer holds it.
@Generable
private struct AccessCode {
    var code: String
}

/// A tool that takes no arguments, whose answer the model can't know.
private struct AccessCodeTool: Tool {
    let name = "getAccessCode"
    let description = "Gets today's access code."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        "The access code is K7Q2."
    }
}
