import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAILanguageModels

extension OpenAIExchangeTests {
    @Suite("Requests")
    struct Requests {
        @Test func `a model that reasons takes sampling settings only while its effort is none`() async throws {
            let options = GenerationOptions(temperature: 0.5)
            let off = try await sentBody({ reasoningModel($0) }, options: options, reasoningLevel: .off)
            let light = try await sentBody({ reasoningModel($0) }, options: options, reasoningLevel: .light)

            #expect(off["temperature"] == 0.5)
            #expect(off["reasoning"] == ["effort": "none"])
            #expect(light["temperature"] == nil)
            #expect(light["reasoning"] == ["effort": "low"])
        }

        @Test func `a model that reasons takes sampling settings as the app set them when no effort is set`() async throws {
            let body = try await sentBody({ reasoningModel($0) }, options: GenerationOptions(temperature: 0.5))

            #expect(body["temperature"] == 0.5)
            #expect(body["reasoning"] == nil)
        }

        @Test func `a model that always reasons never takes sampling settings, even when no effort is set`() async throws {
            let body = try await sentBody(
                { model($0, details(reasoning: .mandatory, efforts: [ContextOptions.ReasoningLevel.medium, .low])) },
                options: GenerationOptions(temperature: 0.5))

            #expect(body["temperature"] == nil)
        }

        @Test func `a level the model doesn't accept goes as the nearest effort it does`() async throws {
            let body = try await sentBody(
                { model($0, details(efforts: [ContextOptions.ReasoningLevel.high, .medium])) }, reasoningLevel: .light)

            #expect(body["reasoning"] == ["effort": "medium"])
        }

        @Test func `settings a model doesn't list are left out`() async throws {
            let body = try await sentBody(
                { model($0, details(parameters: [.maxOutputTokens, .reasoning], efforts: [ContextOptions.ReasoningLevel.low, .off])) },
                options: GenerationOptions(temperature: 0.5, maximumResponseTokens: 50), reasoningLevel: .off)

            #expect(body["temperature"] == nil)
            #expect(body["max_output_tokens"] == 50)
        }

        @Test func `a model that doesn't reason sends no reasoning, and its instructions as a system message`() async throws {
            let body = try await sentBody({ plainModel($0) }, instructions: "Be brief.")

            #expect(body["reasoning"] == nil)
            #expect(body["include"] == nil)
            #expect(input(body).first == ["role": "system", "content": "Be brief."])
        }

        @Test func `a response schema for a model without structured outputs fails before anything is sent`() async {
            let stub = HTTPStub()
            let languageModel = model(
                stub, details(parameters: [.maxOutputTokens, .reasoning], efforts: [ContextOptions.ReasoningLevel.medium]))
            let session = LanguageModelSession(model: languageModel)

            await #expect(throws: LanguageModelError.self) {
                _ = try await session.respond(to: "Name a food.", generating: FoodTool.Arguments.self)
            }
            #expect(stub.requests.isEmpty)
        }

        @Test func `a session with tools on a model without tools fails before anything is sent, as Foundation Models checks`() async {
            let stub = HTTPStub()
            let withoutTools: OpenAIModel<Efforts.Unsupported> = details(parameters: [.maxOutputTokens], reasoning: .unsupported)
            let session = LanguageModelSession(model: model(stub, withoutTools), tools: [FoodTool()])

            await #expect(throws: LanguageModelError.self) { _ = try await session.respond(to: "Hi") }
            #expect(stub.requests.isEmpty)
        }

        @Test func `requiring a tool call of a model without tools fails before anything is sent`() async {
            let stub = HTTPStub()
            let languageModel = model(
                stub, details(parameters: [.maxOutputTokens], reasoning: .unsupported) as OpenAIModel<Efforts.Unsupported>)
            let session = LanguageModelSession(model: languageModel, tools: [FoodTool()])

            await #expect(throws: LanguageModelError.self) {
                _ = try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: .required))
            }
            #expect(stub.requests.isEmpty)
        }

        @Test func `reasoning goes back only to the model that wrote it or a dated snapshot of it`() async throws {
            let item: JSONValue = ["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "blob"]
            func reasoning(by writer: String) -> Transcript.Entry {
                .reasoning(
                    Transcript.Reasoning(
                        metadata: ["reasoningOrigin": "openai-responses", LanguageModelMetadataKey.model: writer], segments: [],
                        signature: JSONValue.array([item]).data))
            }
            func items(after writer: String) async throws -> [JSONValue] {
                let transcript = Transcript(entries: [
                    .prompt(Transcript.Prompt(segments: [text("Hi")])), reasoning(by: writer),
                    .response(Transcript.Response(assetIDs: [], segments: [text("Hello.")])),
                ])
                return input(try await sentBody({ reasoningModel($0) }, transcript: transcript)).filter { $0["type"] == "reasoning" }
            }

            #expect(try await items(after: "gpt-test") == [item])
            #expect(try await items(after: "gpt-test-2026-10-01") == [item])
            #expect(try await items(after: "gpt-other").isEmpty)
        }
    }
}

/// The body a model sends for a prompt, with an answer that ends at once.
func sentBody<Effort: ModelEffort>(
    _ makeModel: (HTTPStub) -> OpenAILanguageModel<Effort>,
    instructions: String? = nil,
    transcript: Transcript? = nil,
    options: GenerationOptions = GenerationOptions(),
    reasoningLevel: ContextOptions.ReasoningLevel? = nil
) async throws -> JSONValue {
    let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
    let languageModel = makeModel(stub)
    let session =
        if let transcript {
            LanguageModelSession(model: languageModel, transcript: transcript)
        } else {
            LanguageModelSession(model: languageModel, instructions: instructions)
        }
    _ = try await session.respond(to: "Hello", options: options, contextOptions: ContextOptions(reasoningLevel: reasoningLevel))
    return try body(stub)
}
