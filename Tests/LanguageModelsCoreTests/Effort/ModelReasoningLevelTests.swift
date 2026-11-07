import FoundationModels
import LanguageModelsCore
import Testing

@Suite("Model reasoning level")
struct ModelReasoningLevelTests {
    @Test(arguments: [HighLowEffort.high, .low])
    func `a model's own effort becomes the level named after it`(effort: HighLowEffort) {
        let model = EchoModel(efforts: [HighLowEffort.high, .low])

        #expect(model.reasoningLevel(effort) == .custom(effort.rawValue))
    }

    @Test func `a request sends the model's own level`() async throws {
        let model = EchoModel(efforts: [HighLowEffort.high, .low])
        let options = ContextOptions(reasoningLevel: model.reasoningLevel(.low))

        let response = try await LanguageModelSession(model: model).respond(to: "Which level?", contextOptions: options)

        #expect(response.content == "low")
    }

    @Test(arguments: [ContextOptions.ReasoningLevel.deep, .custom("xhigh")])
    func `a model known only at runtime takes any level unchanged`(level: ContextOptions.ReasoningLevel) {
        let model = EchoModel<ContextOptions.ReasoningLevel>(efforts: [])

        #expect(model.reasoningLevel(level) == level)
    }
}
