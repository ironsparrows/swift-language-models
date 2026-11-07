import Foundation
import FoundationModels
import OpenRouterLanguageModels

/// A small evaluation by hand: the same requests go to several models, changing only the session's `model:`, and each
/// answer is checked against the expected booking, so the models compare by how often they're right, what they cost
/// and how long they take.
///
/// Apple's on-device model joins when it's available. A request that fails is counted apart rather than as a wrong
/// answer. This command doesn't import Apple's Evaluations framework, because a command-line tool needs Xcode's developer
/// frameworks to load it.
struct Compare: Command {
    let name = "compare"
    let summary = "Run the same requests on several models, and compare right answers, cost and time"

    func run(_ arguments: [String]) async throws {
        var models: [(name: String, model: any LanguageModel)] = [
            ("Claude Haiku 5.5", OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey(openRouterKey))),
            ("GPT-5 Mini", OpenRouterLanguageModel(.openaiGpt5Mini, auth: .apiKey(openRouterKey))),
            ("Gemini 2.5 Flash Lite", OpenRouterLanguageModel(.googleGemini2_5FlashLite, auth: .apiKey(openRouterKey))),
        ]
        if SystemLanguageModel.default.isAvailable {
            models.insert(("Apple on-device", SystemLanguageModel.default), at: 0)
        }
        print(Style.dim("\(Self.samples.count) booking requests to each of \(models.count) models, one at a time.\n"))

        for (name, model) in models {
            let result = await Self.evaluate(model)
            var parts = ["\(result.right)/\(Self.samples.count) right"]
            if result.failed > 0 {
                parts.append(Style.red("\(result.failed) failed"))
            }
            parts.append(String(format: "%.1f s", result.seconds))
            if let cost = result.cost {
                parts.append(cost.dollars)
            }
            print(name.padded(to: 24) + parts.joined(separator: " · "))
        }
    }

    /// How one model did on every sample.
    struct Result {
        var right = 0
        var failed = 0
        var cost: Decimal?
        var seconds = 0.0
    }

    /// Sends each sample in a session of its own, so no answer sees another, and checks the booking it returns.
    static func evaluate(_ model: any LanguageModel) async -> Result {
        var result = Result()
        let start = ContinuousClock.now
        for (request, expected) in samples {
            do {
                let session = LanguageModelSession(model: model, instructions: "Extract the hotel booking from the request.")
                let response = try await session.respond(to: request, generating: Booking.self)
                if response.content.matches(expected) {
                    result.right += 1
                }
                if let cost = response.usage.openRouter.cost {
                    result.cost = (result.cost ?? 0) + cost
                }
            } catch {
                result.failed += 1
            }
        }
        let elapsed = (ContinuousClock.now - start).components
        result.seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return result
    }

    /// Requests and the booking each should give, from plain to tricky.
    static let samples: [(request: String, expected: Booking)] = [
        ("Book me 3 nights in Lisbon.", Booking(city: "Lisbon", nights: 3)),
        ("I need a room in Kyoto for a week.", Booking(city: "Kyoto", nights: 7)),
        ("Two nights in Porto, then home.", Booking(city: "Porto", nights: 2)),
        ("Find a hotel in Athens from Friday to Monday.", Booking(city: "Athens", nights: 3)),
        ("Paris for 5 nights. Actually make that Rome, same length.", Booking(city: "Rome", nights: 5)),
    ]

    @Generable
    struct Booking {
        @Guide(description: "The city of the hotel.")
        var city: String

        @Guide(description: "How many nights to stay.", .range(1...30))
        var nights: Int
    }
}

extension Compare.Booking {
    /// Whether the booking is the expected one, whatever the city's capitalization.
    func matches(_ expected: Self) -> Bool {
        city.caseInsensitiveCompare(expected.city) == .orderedSame && nights == expected.nights
    }
}
