import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

@Suite("Finish reason", .timeLimit(.minutes(1)))
struct FinishReasonTests {
    @Test(arguments: [
        ("stop", FinishReason.stop),
        ("length", .length),
        ("end_turn", FinishReason(rawValue: "end_turn")),
    ])
    func `the response entry that ends an answer reads its finish reason, even one without a static member`(
        sent: String,
        reason: FinishReason
    ) async throws {
        let stub = HTTPStub(events(text("The plan starts with"), done(sent)))

        let response = try await LanguageModelSession(model: model(stub)).respond(to: "Plan the week.")

        #expect(try lastResponse(of: response).openRouter.finishReason == reason)
    }

    @Test func `a response entry that doesn't end its answer has no finish reason`() async throws {
        let stub = HTTPStub(
            events(
                text("Let me look that up. "), toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                done("tool_calls")),
            events(text("An egg has 100 kcal."), done())
        )
        let session = LanguageModelSession(model: model(stub), tools: [FoodTool()])

        let response = try await session.respond(to: "Calories in an egg?")

        let answers = response.transcriptEntries.compactMap { entry in
            if case .response(let answer) = entry { answer } else { nil }
        }
        #expect(answers.map(\.openRouter.finishReason) == [nil, .stop])
    }
}
