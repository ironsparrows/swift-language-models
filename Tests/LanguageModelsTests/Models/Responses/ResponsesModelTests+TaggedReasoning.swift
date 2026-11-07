import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Tagged reasoning")
    struct TaggedReasoning {
        @Test func `text in reasoning tags stays the answer's text, since the format has reasoning of its own`() async {
            let stub = HTTPStub(
                events(
                    item("response.output_item.added", at: 0, ["type": "message", "id": "msg_1", "phase": "final_answer"]),
                    textDelta("<think>Tags.</think>", at: 0), textDelta("Answer.", at: 0), lifecycle("response.completed")))

            let exchange = await ExactExchange(stub, LanguageModelSession(model: model(stub)), recordingHeaders: /^X-/) { session, _ in
                try await session.respond(to: "Start with the tag.").usage
            }

            #expect(exchange.error == nil)
            #expect(
                exchange.transcript.last
                    == #"response ["<think>Tags.</think>Answer."] metadata: {"finishReason":"stop","test.phases":[{"length":27,"phase":"final_answer"}]}"#
            )
        }
    }
}
