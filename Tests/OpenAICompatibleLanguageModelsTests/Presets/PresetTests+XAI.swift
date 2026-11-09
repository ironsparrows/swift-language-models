import Foundation
import FoundationModels
import InlineSnapshotTesting
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    /// xAI's preset, on streams written from xAI's documentation and SDKs, since only its error for an incorrect key was
    /// captured.
    @Suite("xAI")
    struct XAI {
        @Test func `xAI's models speak Responses, reason unless a request turns it off, and take its efforts`() throws {
            let details = OpenAICompatibleModel("grok-4.3", on: .xAI)

            #expect(OpenAICompatibleProvider.xAI.name == "xAI")
            #expect(OpenAICompatibleProvider.xAI.url == URL(string: "https://api.x.ai/v1"))
            #expect(OpenAICompatibleProvider.xAI.format == .responses)
            #expect(OpenAICompatibleProvider.xAI.keyHeader == .bearer)
            #expect(details.reasoning == .onByDefault)
            #expect(details.reasoningEfforts.compactMap(\.effortWord) == ["xhigh", "high", "medium", "low", "none"])
            #expect(details.capabilities.listed == [.toolCalling, .guidedGeneration, .reasoning, .vision])
            #expect(OpenAICompatibleLanguageModel(details, auth: .unauthenticated).configuration == OpenAICompatibleConfiguration())
        }

        @Test func `a request isn't stored, asks for encrypted reasoning, sends top_k and leaves out metadata`() async throws {
            let stub = HTTPStub(events(textDelta("Hi"), completed()))
            let session = LanguageModelSession(model: model(stub, on: .xAI.at(stub.baseURL)), instructions: "Answer in one word.")

            _ = try await session.respond(
                to: "Hi", options: GenerationOptions(samplingMode: .random(top: 40, seed: 7), maximumResponseTokens: 50),
                contextOptions: ContextOptions(reasoningLevel: .light), metadata: ["team": "meals"])

            assertInlineSnapshot(of: stub.requests[0].body, as: .memberLines) {
                """
                {
                  "model": "test-model",
                  "input": [
                    {
                      "role": "developer",
                      "content": "Answer in one word."
                    },
                    {
                      "role": "user",
                      "content": "Hi"
                    }
                  ],
                  "stream": true,
                  "store": false,
                  "include": [
                    "reasoning.encrypted_content"
                  ],
                  "reasoning": {
                    "effort": "low"
                  },
                  "max_output_tokens": 50,
                  "top_k": 40
                }
                """
            }
            guard case .response(let answer)? = session.transcript.last else {
                Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
                return
            }
            #expect(answer.providerMetadata.host == "xAI")
        }

        @Test(arguments: [
            (OpenAICompatibleOptions.Storage.automatic, false),
            (.notStored, false),
            (.stored, true),
        ])
        func `a response is stored only when the app's options ask, and encrypted reasoning is asked for either way`(
            storage: OpenAICompatibleOptions.Storage, stored: Bool
        ) async throws {
            let stub = HTTPStub(events(textDelta("Hi"), completed()))

            _ = try await LanguageModelSession(
                model: model(stub, on: .xAI.at(stub.baseURL), options: OpenAICompatibleOptions(storage: storage))
            ).respond(to: "Hi")

            let sent = try body(stub)
            #expect(sent["store"] == .bool(stored))
            #expect(sent["include"] == ["reasoning.encrypted_content"])
        }

        @Test func `a model that doesn't reason doesn't ask for encrypted reasoning`() async throws {
            let stub = HTTPStub(events(textDelta("Hi"), completed()))
            let details = OpenAICompatibleModel("grok-3", on: .xAI.at(stub.baseURL), reasoning: .unsupported)
            let model = OpenAICompatibleLanguageModel(details, session: stub.session, configuration: .stubbed, auth: .apiKey { "sk-test" })

            _ = try await LanguageModelSession(model: model).respond(to: "Hi")

            #expect(try body(stub)["include"] == nil)
        }

        @Test(arguments: [(429, 2), (503, 1), (500, 1)])
        func `a failed request is sent again only after a rate limit`(status: Int, requests: Int) async {
            // xAI's flat error body, with words written for the test.
            let stub = HTTPStub(
                .json(#"{"code":"unavailable","error":"Try again later."}"#, status: status), events(textDelta("Hi"), completed()))

            _ = try? await LanguageModelSession(model: model(stub, on: .xAI.at(stub.baseURL))).respond(to: "Hi")

            #expect(stub.requests.count == requests)
        }

        @Test func `an incorrect key has the authentication code, as a 401 has`() async {
            // xAI's 400 for an incorrect key, as captured on its Chat Completions endpoint.
            let stub = HTTPStub(
                .json(
                    #"{"code":"invalid-argument","error":"Incorrect API key provided. You can obtain an API key from https://console.x.ai."}"#,
                    status: 400))

            let error = await #expect(throws: OpenAICompatibleError.self) {
                try await LanguageModelSession(model: model(stub, on: .xAI.at(stub.baseURL))).respond(to: "Hi")
            }

            #expect(
                error
                    == OpenAICompatibleError(
                        providerName: "xAI", status: 400,
                        message: "Incorrect API key provided. You can obtain an API key from https://console.x.ai.", code: .authentication))
        }
    }
}
