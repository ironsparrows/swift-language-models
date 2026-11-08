import Foundation
import Testing

@testable import OpenRouterLanguageModels

@Suite("OpenRouter pricing", .timeLimit(.minutes(1)))
struct OpenRouterPricingTests {
    /// Long prompts cost more, and weekday nights from 01:00 to 04:00 UTC cost more again, except for cache reads.
    private static let pricing = OpenRouterPricing(
        prompt: 1,
        completion: 5,
        cacheRead: 0.1,
        overrides: [
            .init(condition: .init(promptTokensAbove: 272_000), prompt: 2, completion: 7.5),
            .init(
                condition: .init(
                    weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                    hours: .init(start: .seconds(3_600), end: .seconds(14_400))
                ),
                prompt: 3
            ),
        ]
    )

    /// Monday, 2 November 2026, at 02:00 UTC.
    private static let mondayNight = Date(timeIntervalSince1970: 1_793_584_800)

    @Test func `a request that matches no override pays the base prices`() {
        let prices = Self.pricing.prices(forPromptTokens: 1_000, at: Self.mondayNight.addingTimeInterval(6 * 3_600))

        #expect(prices == OpenRouterPricing(prompt: 1, completion: 5, cacheRead: 0.1))
    }

    @Test func `the prompt length must exceed the threshold`() {
        #expect(Self.pricing.prices(forPromptTokens: 272_000, at: Self.mondayNight.addingTimeInterval(6 * 3_600)).prompt == 1)
        #expect(Self.pricing.prices(forPromptTokens: 272_001, at: Self.mondayNight.addingTimeInterval(6 * 3_600)).prompt == 2)
    }

    @Test func `a later override wins for the prices it sets, and the others carry over`() {
        let prices = Self.pricing.prices(forPromptTokens: 300_000, at: Self.mondayNight)

        #expect(prices == OpenRouterPricing(prompt: 3, completion: 7.5, cacheRead: 0.1))
    }

    @Test func `the fees carry over to a request's prices, and an override changes the audio price`() {
        let pricing = OpenRouterPricing(
            prompt: 1,
            completion: 5,
            reasoning: 6,
            audio: 2,
            image: 0.5,
            request: 0.002,
            webSearch: 0.005,
            overrides: [.init(condition: .init(promptTokensAbove: 200_000), prompt: 2, audio: 4)]
        )

        #expect(
            pricing.prices(forPromptTokens: 1_000)
                == OpenRouterPricing(prompt: 1, completion: 5, reasoning: 6, audio: 2, image: 0.5, request: 0.002, webSearch: 0.005)
        )
        #expect(
            pricing.prices(forPromptTokens: 300_000)
                == OpenRouterPricing(prompt: 2, completion: 5, reasoning: 6, audio: 4, image: 0.5, request: 0.002, webSearch: 0.005)
        )
    }

    @Test func `a weekday override doesn't apply on the weekend`() {
        let sundayNight = Self.mondayNight.addingTimeInterval(-24 * 3_600)

        #expect(Self.pricing.prices(forPromptTokens: 1_000, at: sundayNight).prompt == 1)
    }

    @Test(arguments: [(57_600, true), (86_399, true), (0, false), (3_600, false)])
    func `a window that ends before it starts runs past midnight`(seconds: Int, isInside: Bool) {
        let evening = OpenRouterPricing.TimeWindow(start: .seconds(57_600), end: .seconds(0))

        #expect(evening.contains(.seconds(seconds)) == isInside)
    }

    @Test func `a window includes its start and leaves out its end`() {
        let night = OpenRouterPricing.TimeWindow(start: .seconds(3_600), end: .seconds(14_400))

        #expect(night.contains(.seconds(3_600)))
        #expect(!night.contains(.seconds(14_400)))
    }
}
