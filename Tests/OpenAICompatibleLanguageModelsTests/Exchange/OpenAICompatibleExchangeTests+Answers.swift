import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension OpenAICompatibleExchangeTests {
    @Suite("Answers")
    struct Answers {
        @Test(
            arguments: [
                (#"{"reasoning_content":"Thinking."}"#, "Thinking."),
                (#"{"reasoning":"Thinking."}"#, "Thinking."),
                (#"{"reasoning_content":"Thinking.","reasoning":"Thinking."}"#, "Thinking."),
                (#"{"reasoning_content":"First.","reasoning":"Second."}"#, "First."),
                (#"{"reasoning_content":"","reasoning":"Thinking."}"#, "Thinking."),
                (#"{"reasoning":{"text":"Thinking."},"reasoning_content":7}"#, nil),
            ] as [(String, String?)])
        func `a delta's reasoning is read from one spelling, reasoning_content first`(delta: String, reasoning: String?) async throws {
            let stub = HTTPStub(
                chunks(OpenAICompatibleLanguageModelsTests.delta(try JSONValue(json: Data(delta.utf8))), text("Hi"), finish()))
            let session = LanguageModelSession(model: model(stub))

            let response = try await session.respond(to: "Hi")

            #expect(response.content == "Hi")
            #expect(Self.reasoningText(in: session.transcript) == reasoning)
        }

        @Test func `the request id comes from the response's x-request-id header`() async throws {
            let stub = HTTPStub(chunks(headers: ["x-request-id": "req_1"], text("Hi"), finish()))
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Hi")

            guard case .response(let answer)? = session.transcript.last else {
                Issue.record("The transcript ends with \(String(describing: session.transcript.last))")
                return
            }
            #expect(answer.openAICompatible.requestID == "req_1")
            #expect(answer.providerMetadata.host == nil)
        }

        @Test(
            arguments: [
                (OpenAICompatibleProvider.Format.chatCompletions, "openai-compatible/my gateway"),
                (.responses, "openai-compatible-responses/my gateway"),
            ] as [(OpenAICompatibleProvider.Format, String)])
        func `reasoning carries the provider's name and the format as its origin`(format: OpenAICompatibleProvider.Format, origin: String)
            async throws
        {
            let stub = HTTPStub(
                format == .responses
                    ? responseStream(reasoningItem(at: 0, id: "rs_1", summary: "Thinking."), [textDelta("Hi", at: 1), completed()])
                    : chunks(delta(["reasoning": "Thinking."]), text("Hi"), finish()))
            let session = LanguageModelSession(model: model(stub, on: provider(stub, name: "My Gateway", format: format)))

            _ = try await session.respond(to: "Hi")

            let reasoning = session.transcript.compactMap { entry -> Transcript.Reasoning? in
                if case .reasoning(let reasoning) = entry { reasoning } else { nil }
            }
            #expect(reasoning.compactMap { $0.metadata["reasoningOrigin"].flatMap { try? $0.value(String.self) } } == [origin])
        }

        @Test func `reasoning goes back in Responses, to the model that wrote it only, and never in Chat Completions`() async throws {
            let answer = responseStream(reasoningItem(at: 0, id: "rs_1", summary: "Thinking."), [textDelta("Hi", at: 1), completed()])
            let responses = HTTPStub(answer, events(textDelta("Hi"), completed()))
            let renamed = HTTPStub(events(textDelta("Hi"), completed()))
            let otherModel = HTTPStub(events(textDelta("Hi"), completed()))
            let chat = HTTPStub(chunks(text("<think>Thinking.</think>Hi"), finish()), chunks(text("Hi"), finish()))
            let session = LanguageModelSession(model: model(responses, format: .responses))
            let chatSession = LanguageModelSession(model: model(chat))

            _ = try await session.respond(to: "Hi")
            _ = try await session.respond(to: "Again")
            let other = LanguageModelSession(
                model: model(renamed, on: provider(renamed, name: "Other", format: .responses)), transcript: session.transcript)
            _ = try await other.respond(to: "Once more")
            let sibling = OpenAICompatibleLanguageModel(
                OpenAICompatibleModel("other-model", on: provider(otherModel, format: .responses)), session: otherModel.session,
                configuration: .stubbed, auth: .unauthenticated)
            _ = try await LanguageModelSession(model: sibling, transcript: session.transcript).respond(to: "And again")
            _ = try await chatSession.respond(to: "Hi")
            _ = try await chatSession.respond(to: "Again")

            #expect(Self.types(of: try body(responses, 1)["input"]).contains("reasoning"))
            #expect(!Self.types(of: try body(renamed)["input"]).contains("reasoning"))
            #expect(!Self.types(of: try body(otherModel)["input"]).contains("reasoning"))
            #expect(try body(chat, 1)["messages"]?[1] == ["role": "assistant", "content": "Hi"])
        }

        /// The text of the transcript's reasoning entries, or `nil` when it has none.
        private static func reasoningText(in transcript: Transcript) -> String? {
            let texts = transcript.compactMap { entry -> String? in
                guard case .reasoning(let reasoning) = entry else { return nil }
                return reasoning.segments.compactMap { segment in
                    if case .text(let text) = segment { text.content } else { nil }
                }.joined()
            }
            return texts.isEmpty ? nil : texts.joined()
        }

        /// The types of a Responses input's items.
        private static func types(of input: JSONValue?) -> [String] {
            guard case .array(let items)? = input else { return [] }
            return items.compactMap { $0["type"]?.stringValue }
        }
    }
}
