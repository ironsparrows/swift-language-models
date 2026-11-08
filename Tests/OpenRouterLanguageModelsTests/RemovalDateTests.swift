import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

@Suite("Removal date", .timeLimit(.minutes(1)))
struct RemovalDateTests {
    @Test func `a model OpenRouter lists has no removal date`() {
        #expect(fallback("vendor/model").removalDate == nil)
    }

    @Test(arguments: ModelRemovals.openRouter.dates.sorted { $0.key < $1.key })
    func `a removed model carries the day it left and is left out of the catalog's lookup by id`(id: String, day: Date) {
        let id = OpenRouterModelID(rawValue: id)

        #expect(fallback(id).removalDate == day)
        #expect(OpenRouterModel<ContextOptions.ReasoningLevel>(catalogID: id) == nil)
    }
}
