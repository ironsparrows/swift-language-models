import Foundation
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterInfoTests {
    @Suite("Live prices")
    struct LivePrices {
        private static func pricing(_ json: String) throws -> OpenRouterPricing? {
            OpenRouterPricing(try JSONDecoder().decode(OpenRouterPricing.Payload.self, from: Data(json.utf8)))
        }

        @Test(arguments: [
            #"{"prompt": "-1", "completion": "-1"}"#,
            #"{"prompt": "0.000001", "completion": "-1"}"#,
            #"{"prompt": "free", "completion": "0"}"#,
            #"{"completion": "0.000001"}"#,
            "{}",
        ])
        func `prices without a usable prompt and completion price make no pricing`(json: String) throws {
            #expect(try Self.pricing(json) == nil)
        }

        @Test func `a free model's zero prices make pricing`() throws {
            let pricing = try #require(try Self.pricing(#"{"prompt": "0", "completion": "0", "request": "-1"}"#))

            #expect(pricing.prompt == 0)
            #expect(pricing.request == nil)
        }

        @Test func `a discount decodes, and none means 0`() throws {
            #expect(try Self.pricing(#"{"prompt": "1", "completion": "1", "discount": 0.25}"#)?.discount == 0.25)
            #expect(try Self.pricing(#"{"prompt": "1", "completion": "1"}"#)?.discount == 0)
        }

        @Test func `a reasoning, audio, image and request price decode`() throws {
            let json = #"{"prompt": "1", "completion": "2", "internal_reasoning": "3", "audio": "4", "image": "5", "request": "6"}"#

            let pricing = try #require(try Self.pricing(json))

            #expect([pricing.reasoning, pricing.audio, pricing.image, pricing.request] == [3, 4, 5, 6])
        }

        @Test func `a window without an end runs to midnight, and one without a start from midnight`() throws {
            let json = #"""
                {"prompt": "1", "completion": "1", "overrides": [{"utc_start": 130, "prompt": "2"}, {"utc_end": 2230, "prompt": "3"}]}
                """#

            let hours = try #require(try Self.pricing(json)).overrides.map(\.condition.hours)

            #expect(hours == [.init(start: .seconds(5_400), end: .seconds(86_400)), .init(start: .zero, end: .seconds(81_000))])
        }

        @Test(arguments: [2_460, 2_500, -100, 130.5, 1e19, 1e300])
        func `an override whose window isn't a time of day is left out`(clockNumber: Double) throws {
            let json = #"{"prompt": "1", "completion": "1", "overrides": [{"utc_start": \#(clockNumber), "prompt": "2"}]}"#

            #expect(try #require(try Self.pricing(json)).overrides.isEmpty)
        }

        @Test func `an override that changes no price kept here is left out`() throws {
            let json = #"{"prompt": "1", "completion": "1", "overrides": [{"min_prompt_tokens": 1000, "image_output": "2"}]}"#

            #expect(try #require(try Self.pricing(json)).overrides.isEmpty)
        }

        @Test func `a prompt threshold rounds down, and an unknown day is skipped`() throws {
            let json = #"""
                {"prompt": "1", "completion": "1", "overrides": [{"min_prompt_tokens": 1000.7, "utc_days": ["monday", "someday"], "prompt": "2"}]}
                """#

            let condition = try #require(try Self.pricing(json)?.overrides.first?.condition)

            #expect(condition.promptTokensAbove == 1_000)
            #expect(condition.weekdays == [.monday])
        }

        @Test(arguments: [(1e300, Int.max), (-1e300, Int.min)])
        func `a prompt threshold beyond Int's range keeps its meaning`(threshold: Double, kept: Int) throws {
            let json = #"{"prompt": "1", "completion": "1", "overrides": [{"min_prompt_tokens": \#(threshold), "prompt": "2"}]}"#

            #expect(try Self.pricing(json)?.overrides.first?.condition.promptTokensAbove == kept)
        }
    }
}
