import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension OpenAICompatibleExchangeTests {
    @Suite("Requests")
    struct Requests {
        @Test func `a Chat Completions request asks for usage, and sends the token limit and effort as most providers take them`()
            async throws
        {
            let stub = HTTPStub(chunks(text("Hi"), finish(), usage()))

            _ = try await LanguageModelSession(model: model(stub)).respond(
                to: "Hi", options: GenerationOptions(temperature: 0.5, maximumResponseTokens: 50),
                contextOptions: ContextOptions(reasoningLevel: .deep))

            #expect(stub.requests[0].request.url?.path == "/chat/completions")
            assertInlineSnapshot(of: stub.requests[0].body, as: .memberLines) {
                """
                {
                  "model": "test-model",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Hi"
                    }
                  ],
                  "stream": true,
                  "stream_options": {
                    "include_usage": true
                  },
                  "reasoning_effort": "high",
                  "temperature": 0.5,
                  "max_tokens": 50
                }
                """
            }
        }

        @Test func `a Responses request sends the effort in reasoning and the storage the options ask for`() async throws {
            let stub = HTTPStub(events(textDelta("Hi"), completed()))
            let options = OpenAICompatibleOptions(storage: .notStored)

            _ = try await LanguageModelSession(model: model(stub, format: .responses, options: options)).respond(
                to: "Hi", options: GenerationOptions(temperature: 0.5, maximumResponseTokens: 50),
                contextOptions: ContextOptions(reasoningLevel: .deep))

            #expect(stub.requests[0].request.url?.path == "/responses")
            assertInlineSnapshot(of: stub.requests[0].body, as: .memberLines) {
                """
                {
                  "model": "test-model",
                  "input": [
                    {
                      "role": "user",
                      "content": "Hi"
                    }
                  ],
                  "stream": true,
                  "store": false,
                  "reasoning": {
                    "effort": "high"
                  },
                  "temperature": 0.5,
                  "max_output_tokens": 50
                }
                """
            }
        }

        @Test(arguments: [OpenAICompatibleProvider.Format.chatCompletions, .responses])
        func `the app's members go out as written, over the module's, and never over the model, transcript, stream or tools`(
            format: OpenAICompatibleProvider.Format
        ) async throws {
            let stub = HTTPStub(format == .responses ? events(textDelta("Hi"), completed()) : chunks(text("Hi"), finish()))
            var options = OpenAICompatibleOptions()
            options.additionalMembers = [
                "keep_alive": GeneratedContent("10m"), "temperature": GeneratedContent(0.2), "stream": GeneratedContent(false),
                "chat_template_kwargs": try GeneratedContent(json: #"{"enable_thinking":false}"#),
            ]

            _ = try await LanguageModelSession(model: model(stub, format: format, options: options)).respond(
                to: "Hi", options: GenerationOptions(temperature: 0.5))

            let sent = try body(stub)
            #expect(sent["keep_alive"] == "10m")
            #expect(sent["temperature"] == 0.2)
            #expect(sent["stream"] == true)
            #expect(sent["chat_template_kwargs"] == ["enable_thinking": false])
        }

        @Test func `an app's reasoning_effort replaces the module's`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))
            let options = OpenAICompatibleOptions(additionalMembers: ["reasoning_effort": GeneratedContent("max")])

            _ = try await LanguageModelSession(model: model(stub, options: options)).respond(
                to: "Hi", contextOptions: ContextOptions(reasoningLevel: .light))

            #expect(try body(stub)["reasoning_effort"] == "max")
        }

        @Test func `a request that fails with a 409 or a 429 is sent again, as one to a provider described by its name and URL`()
            async throws
        {
            let stub = HTTPStub(
                .json(#"{"error":{"message":"Busy."}}"#, status: 409), .json(#"{"error":{"message":"Slow down."}}"#, status: 429),
                chunks(text("Hi"), finish()))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            #expect(response.content == "Hi")
            #expect(stub.requests.count == 3)
        }

        @Test func `a reasoning level goes out as the nearest of the model's own efforts`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))
            let details = OpenAICompatibleModel("test-model", on: provider(stub), efforts: [.high, .low])
            let model = OpenAICompatibleLanguageModel(details, session: stub.session, auth: .unauthenticated)

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: .moderate))

            #expect(try body(stub)["reasoning_effort"] == "low")
        }
    }
}
