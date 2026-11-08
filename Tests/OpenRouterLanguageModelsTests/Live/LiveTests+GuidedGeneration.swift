import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenRouterLanguageModels
import Testing

@diagnose(DeprecatedDeclaration, as: warning)
extension LiveTests {
    @Suite("Guided generation")
    struct GuidedGeneration {
        /// Models with strict structured outputs. The Anthropic alias shows that a schema written for Anthropic also
        /// goes to a model named through `~`.
        static let models = [
            LiveModel(.openaiGpt4_1Nano),
            LiveModel(.anthropicClaudeHaiku5_5),
            LiveModel(.anthropicClaudeHaikuLatest),
            LiveModel(.googleGemini2_5FlashLite),
            LiveModel(.deepseekDeepseekV4Flash),
        ]

        @Test(arguments: models)
        func `the host accepts the schema and its answer decodes`(model: LiveModel) async throws {
            let session = LanguageModelSession(model: model.languageModel)

            let trip = try await session.respond(to: "Plan a short trip to Lisbon.", generating: Trip.self).content

            record(trip, named: "trip.txt")
            #expect(trip.activities.count == 3)
            #expect((1...14).contains(trip.days))
            #expect(trip.activities.allSatisfy { (1...12).contains($0.hours) })
        }

        @Test func `a streamed list of forty items grows to all of them`() async throws {
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel)

            var counts: [Int] = []
            var last: GeneratedContent?
            let stream = session.streamResponse(to: "List forty things to pack for a week of hiking.", generating: PackingList.self)
            for try await snapshot in stream {
                counts.append(snapshot.content.items?.count ?? 0)
                last = snapshot.rawContent
            }
            let list = try PackingList(try #require(last))

            record(list.items, named: "items.txt")
            #expect(list.items.count == 40)
            #expect(counts.count > 1)
            #expect(counts == counts.sorted())
        }

        /// How many times each model answers the same request, to see how often its answers decode.
        static let tries = 5

        /// Models with strict structured outputs, whose host holds the answer to the schema.
        static let strictModels = [LiveModel(.openaiGpt4_1Nano), LiveModel(.googleGemini2_5FlashLite)]

        /// Models with only JSON mode, which can't hold their answers to a schema.
        static let jsonModeModels = [LiveModel(.qwenQwen3_7Flash), LiveModel(.inclusionaiLing3_0Flash)]

        @Test(arguments: strictModels)
        func `a strict schema's answer decodes on every try`(model: LiveModel) async throws {
            var trips: [Trip] = []
            for _ in 0..<Self.tries {
                let session = LanguageModelSession(model: model.languageModel)
                trips.append(try await session.respond(to: "Plan a short trip to Lisbon.", generating: Trip.self).content)
            }

            record(trips, named: "trips.txt")
            #expect(trips.count == Self.tries)
            #expect(trips.allSatisfy { $0.activities.count == 3 && (1...14).contains($0.days) })
        }

        @Test(arguments: jsonModeModels)
        func `a model with only JSON mode is refused before any request`(model: LiveModel) async throws {
            let session = LanguageModelSession(model: model.languageModel)

            let error = try await #require(throws: LanguageModelError.self) {
                try await session.respond(to: "Plan a short trip to Lisbon.", generating: Trip.self)
            }

            record(error, named: "error.txt")
            guard case .unsupportedCapability = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
        }

        /// Models whose answers the guide check reads: an Anthropic model gets the guides only in descriptions, the
        /// others in the full schema.
        static let guideModels = [
            LiveModel(.anthropicClaudeHaiku5_5), LiveModel(.openaiGpt4_1Nano), LiveModel(.googleGemini2_5FlashLite),
        ]

        @Test(arguments: guideModels)
        func `an answer that breaks a guide throws, and one that decodes meets every guide`(model: LiveModel) async throws {
            var outcomes: [String] = []
            var broken = 0
            for _ in 0..<Self.tries {
                let session = LanguageModelSession(model: model.languageModel)
                do {
                    let planets = try await session.respond(
                        to: "List the planets of the solar system, and say how many there are.", generating: Planets.self
                    ).content
                    #expect(planets.names.count == 5)
                    #expect((1...5).contains(planets.total))
                    outcomes.append("Decoded: \(planets.total), \(planets.names)")
                } catch let error as GeneratedContent.ParsingError {
                    #expect(error.debugDescription.hasPrefix("The answer breaks its schema's guides:"), "\(error.debugDescription)")
                    broken += 1
                    outcomes.append("Threw: \(error.debugDescription)")
                }
            }

            record(outcomes.joined(separator: "\n"), named: "outcomes.txt")
            print("Guide check, \(model.testDescription): \(broken) of \(Self.tries) answers broke a guide")
        }

        @Test func `an answer cut off inside its JSON throws the parsing error`() async throws {
            let session = LanguageModelSession(model: LiveModel(.openaiGpt4_1Nano).languageModel)

            let error = try await #require(throws: GeneratedContent.ParsingError.self) {
                try await session.respond(
                    to: "Plan a short trip to Lisbon.", generating: Trip.self, options: GenerationOptions(maximumResponseTokens: 8))
            }

            record(error, named: "error.txt")
        }

        @Test func `a model with neither structured outputs nor JSON mode is refused before any request`() async throws {
            let session = LanguageModelSession(model: LiveModel(.metaLlamaLlama3_1_70bInstruct).languageModel)

            let error = try await #require(throws: LanguageModelError.self) {
                try await session.respond(to: "Plan a short trip to Lisbon.", generating: Trip.self)
            }

            record(error, named: "error.txt")
            guard case .unsupportedCapability = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
        }
    }
}

/// An answer whose guides go against the facts, so a model is tempted to break them.
@Generable
private struct Planets {
    @Guide(description: "The planets' names.", .count(5))
    var names: [String]

    @Guide(description: "How many planets the solar system has.", .range(1...5))
    var total: Int
}

/// A list long enough to stream in many snapshots.
@Generable
private struct PackingList {
    @Guide(description: "Forty short items, each a few words.", .count(40))
    var items: [String]
}
