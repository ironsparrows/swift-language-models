import FoundationModels
import LanguageModelsCore
import LanguageModelsTestSupport
import Testing

@Suite("Profile effort")
struct DynamicProfileEffortTests {
    @Test(arguments: [HighLowEffort.high, .low])
    func `a profile sends its typed effort to the model`(effort: HighLowEffort) async throws {
        #expect(try await levelReceived(from: EchoProfile(effort: effort)) == effort.rawValue)
    }

    @Test func `a runtime level reaches the model unchanged`() async throws {
        let profile = echoProfile().model(EchoModel<ContextOptions.ReasoningLevel>(efforts: []), effort: .custom("none"))

        #expect(try await levelReceived(from: profile) == "none")
    }

    @Test func `a model without an effort sends no reasoning level`() async throws {
        let profile = echoProfile().model(EchoModel<HighLowEffort>(efforts: [.high]))

        #expect(try await levelReceived(from: profile) == "default")
    }

    @Test func `an outer reasoning level doesn't replace the typed effort`() async throws {
        #expect(try await levelReceived(from: EchoProfile(effort: .low).reasoningLevel(.deep)) == "low")
    }

    @Test func `a request's context options replace the typed effort`() async throws {
        let level = try await levelReceived(from: EchoProfile(effort: .low), options: ContextOptions(reasoningLevel: .deep))

        #expect(level == "deep")
    }

    @Test func `a detailed model takes its capabilities from its details`() {
        #expect(EchoModel<HighLowEffort>(efforts: [.high, .low]).capabilities.listed == [.toolCalling, .reasoning])
    }

    private func levelReceived(
        from profile: sending some LanguageModelSession.DynamicProfile,
        options: ContextOptions = ContextOptions()
    ) async throws -> String {
        try await LanguageModelSession(profile: profile).respond(to: "Which level?", contextOptions: options).content
    }
}

private func echoProfile() -> LanguageModelSession.Profile {
    LanguageModelSession.Profile { Instructions("Echo the reasoning level.") }
}

private struct EchoProfile: LanguageModelSession.DynamicProfile {
    let effort: HighLowEffort

    var body: some LanguageModelSession.DynamicProfile {
        echoProfile().model(EchoModel(efforts: [HighLowEffort.high, .low]), effort: effort)
    }
}
