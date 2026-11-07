import LanguageModelsCore
import Testing

@Suite("Model reasoning")
struct ModelReasoningTests {
    @Test(arguments: [
        (ModelReasoning.unsupported, false, false, false),
        (.offByDefault, true, false, true),
        (.onByDefault, true, true, true),
        (.mandatory, true, true, false),
    ])
    func `each kind of reasoning says whether it's supported, on by default and can be turned off`(
        reasoning: ModelReasoning,
        isSupported: Bool,
        isEnabledByDefault: Bool,
        canBeTurnedOff: Bool
    ) {
        #expect(reasoning.isSupported == isSupported)
        #expect(reasoning.isEnabledByDefault == isEnabledByDefault)
        #expect(reasoning.canBeTurnedOff == canBeTurnedOff)
    }
}
