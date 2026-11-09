import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    /// Ollama's preset, on a stream captured from Ollama 0.40.15, ids swapped.
    @Suite("Ollama")
    struct Ollama {
        @Test func `Ollama's models take its efforts, and a failed request isn't sent again`() throws {
            let details = OpenAICompatibleModel("qwen3:0.6b", on: .ollama)

            #expect(OpenAICompatibleProvider.ollama.name == "Ollama")
            #expect(OpenAICompatibleProvider.ollama.url == URL(string: "http://localhost:11434/v1/"))
            #expect(OpenAICompatibleProvider.ollama.format == .chatCompletions)
            #expect(details.reasoning == .offByDefault)
            #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["max", "xhigh", "high", "medium", "low", "minimal", "none"])
            #expect(details.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
            #expect(
                OpenAICompatibleLanguageModel(details, auth: .unauthenticated).configuration
                    == OpenAICompatibleConfiguration(retries: .disabled))
        }

        @Test func `a request leaves out metadata and top_k, which Ollama ignores, and asks for usage`() async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))

            _ = try await LanguageModelSession(model: model(stub, on: .ollama.at(stub.baseURL))).respond(
                to: "Hi", options: GenerationOptions(samplingMode: .random(top: 40, seed: 7), maximumResponseTokens: 50),
                contextOptions: ContextOptions(reasoningLevel: .light), metadata: ["team": "meals"])

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
                  "reasoning_effort": "low",
                  "seed": 7,
                  "max_tokens": 50
                }
                """
            }
        }

        @Test(.tags(.loopback), arguments: [true, false])
        func `an image at a web address is refused before it's sent, and an image sent as data goes`(atWebAddress: Bool) async throws {
            let stub = HTTPStub(chunks(text("A cat."), finish()))
            let pixels = try #require(TestImage.halves(width: 8, height: 8))
            // Foundation Models reads an image at a web address itself, more than once, and refuses one it can't read, so
            // the image is served.
            let png = try #require(TestImage.file(of: pixels, as: .png))
            let reply = LoopbackReply(headers: ["Content-Type": "image/png"], writes: [png])
            let images = try await LoopbackServer { _ in Array(repeating: reply, count: 6) }
            let image =
                atWebAddress
                ? Transcript.ImageAttachment(imageURL: images.baseURL.appending(path: "cat.png"))
                : Transcript.ImageAttachment(pixels)
            let history = Transcript(entries: [
                .prompt(Transcript.Prompt(segments: [.text(.init(content: "Keep this.")), .attachment(.init(content: .image(image)))])),
                .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Kept."))])),
            ])
            let session = LanguageModelSession(model: model(stub, on: .ollama.at(stub.baseURL)), transcript: history)

            do {
                _ = try await session.respond(to: "What's in it?")
                #expect(!atWebAddress)
                #expect(stub.requests.count == 1)
            } catch let error as LanguageModelError {
                guard case .unsupportedTranscriptContent = error else {
                    Issue.record("Expected unsupported transcript content, got \(error)")
                    return
                }
                #expect(atWebAddress)
                #expect("\(error)".contains("Ollama takes only images sent as data"))
                #expect(stub.requests.isEmpty)
            }
        }

        @Test(arguments: [GenerationOptions.ToolCallingMode.required, .allowed])
        func `a request that requires a tool call is refused before it's sent, and tool_choice, which Ollama ignores, is left out`(
            mode: GenerationOptions.ToolCallingMode
        ) async throws {
            let stub = HTTPStub(chunks(text("Hi"), finish()))
            let session = LanguageModelSession(model: model(stub, on: .ollama.at(stub.baseURL)), tools: [WeatherTool()])

            do {
                _ = try await session.respond(to: "Say hi.", options: GenerationOptions(toolCallingMode: mode))
                #expect(mode == .allowed)
                #expect(try body(stub)["tools"] != nil)
                #expect(try body(stub)["tool_choice"] == nil)
            } catch let error as LanguageModelError {
                guard case .unsupportedCapability(let context) = error else {
                    Issue.record("Expected an unsupported capability, got \(error)")
                    return
                }
                #expect(mode == .required)
                #expect(context.capability == .toolCalling)
                #expect(stub.requests.isEmpty)
            }
        }

        @Test func `a model's reasoning goes back with its tool calls as reasoning, to that model only`() async throws {
            let recorded = try Bundle.module.fixture("Captured/ollama-tool-round.sse")
            let stub = HTTPStub(.eventStream(recorded), chunks(text("It's 17 degrees in Paris."), finish()))
            let other = HTTPStub(chunks(text("Still 17 degrees."), finish()))
            let qwen = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("qwen3:0.6b", on: .ollama.at(stub.baseURL)), session: stub.session, configuration: .stubbed,
                auth: .unauthenticated)
            let llama = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("llama3.2:1b", on: .ollama.at(other.baseURL)), session: other.session,
                configuration: .stubbed, auth: .unauthenticated)
            let session = LanguageModelSession(model: qwen, tools: [WeatherTool()])

            _ = try await session.respond(to: "What is the weather in Paris?")
            _ = try await LanguageModelSession(model: llama, tools: [WeatherTool()], transcript: session.transcript).respond(
                to: "And tomorrow?")

            let replayed = try #require(try body(stub, 1)["messages"]?[1])
            #expect(replayed["role"] == "assistant")
            #expect(replayed["reasoning"]?.stringValue?.hasPrefix("Okay, the user is asking about the weather in Paris.") == true)
            #expect(replayed["tool_calls"]?[0]?["id"] == "call_test0001")
            let elsewhere = try #require(try body(other)["messages"]?[1])
            #expect(elsewhere["tool_calls"]?[0]?["id"] == "call_test0001")
            #expect(elsewhere["reasoning"] == nil)
        }
    }
}
