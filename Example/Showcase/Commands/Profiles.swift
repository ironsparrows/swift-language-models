import Foundation
import FoundationModels
import OpenRouterLanguageModels

/// A Dynamic Profile that moves a session between models and reasoning levels, keeping the conversation.
///
/// The profile reads a session property, so setting `session.properties.thinksHard` sends the next request to Claude
/// at a high level instead of GPT-5.4 Mini with reasoning off. Each model's effort type lists only the levels it
/// accepts, so a level it doesn't take fails to compile.
struct Profiles: Command {
    let name = "profiles"
    let summary = "Switch models and effort mid-session with a Dynamic Profile"

    func run(_ arguments: [String]) async throws {
        let session = LanguageModelSession(profile: TutorProfile())

        for (question, thinksHard) in [("What's 17 × 23?", false), ("Why are there infinitely many primes?", true)] {
            session.properties.thinksHard = thinksHard
            print(Style.bold(question))
            let response = try await session.respond(to: question)
            print(response.content)
            if case .response(let answer)? = response.transcriptEntries.last, let model = answer.openRouter.model {
                print(Style.green("\(model.rawValue) answered."))
            }
            print("\(Footer(response))\n")
        }
    }
}

extension SessionPropertyValues {
    /// Whether ``TutorProfile`` answers with its stronger model, at a high level.
    @SessionPropertyEntry var thinksHard = false
}

/// A math tutor that answers quick questions fast and cheaply, and hard ones with more thought.
struct TutorProfile: LanguageModelSession.DynamicProfile {
    let quick = OpenRouterLanguageModel(.openaiGpt5_4Mini, auth: .apiKey(openRouterKey))
    let thorough = OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey(openRouterKey))

    @SessionProperty(\.thinksHard) var thinksHard

    var body: some DynamicProfile {
        if thinksHard {
            Profile { Instructions("You're a patient math tutor. Keep answers short.") }.model(thorough, effort: .high)
        } else {
            Profile { Instructions("You're a patient math tutor. Keep answers short.") }.model(quick, effort: .off)
        }
    }
}
