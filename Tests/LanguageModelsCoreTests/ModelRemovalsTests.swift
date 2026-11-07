import Foundation
import FoundationModels
import Testing

@testable import LanguageModelsCore

@Suite("Model removals")
struct ModelRemovalsTests {
    private static let gone = Date(timeIntervalSince1970: 1_793_404_800)
    private static let earlier = Date(timeIntervalSince1970: 1_793_232_000)

    @Test func `a removal table gives the day a model left, and nothing for a listed one`() {
        let removals = ModelRemovals(["vendor/gone": Self.gone])

        #expect(removals.removalDate(of: "vendor/gone") == Self.gone)
        #expect(removals.removalDate(of: "vendor/model") == nil)
    }

    @Test func `a model and fallbacks that are still listed name no removed model`() {
        let model = EchoModel<HighLowEffort>(efforts: [], fallbacks: [.init(id: "fallback", reasoningEfforts: [])])

        #expect(model.removedModels.isEmpty)
    }

    @Test func `a removed model and fallback are named with their days, in the order the provider tries them`() {
        let model = EchoModel<HighLowEffort>(
            efforts: [],
            removalDate: Self.gone,
            fallbacks: [
                .init(id: "listed", reasoningEfforts: []),
                .init(id: "fallback", reasoningEfforts: [], removalDate: Self.earlier),
            ]
        )

        #expect(
            model.removedModels == [
                ModelRemovals.Report(id: "echo", removedOn: Self.gone), ModelRemovals.Report(id: "fallback", removedOn: Self.earlier),
            ]
        )
    }

    @Test func `the message names the model and the day it left`() {
        #expect(
            ModelRemovals.Report(id: "vendor/gone", removedOn: Self.gone).message
                == "The request names vendor/gone, which its provider stopped listing on 2026-10-31, so it may fail. Choose another model."
        )
    }

    @Test func `a request to a removed model is still sent`() async throws {
        let profile = LanguageModelSession.Profile { Instructions("Echo the reasoning level.") }
            .model(EchoModel<HighLowEffort>(efforts: [], removalDate: Self.gone))

        #expect(try await LanguageModelSession(profile: profile).respond(to: "Which level?").content == "default")
    }
}
