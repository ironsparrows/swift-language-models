import Foundation
import FoundationModels
import LanguageModelsCore
import Testing

@Suite("Metadata values")
struct MetadataValuesTests {
    @Test func `a value of another kind reads as unknown, and a list skips what isn't a structure`() {
        let values = MetadataValues([
            "number": GeneratedContent(kind: .number(1)),
            "text": GeneratedContent(kind: .string("2 seconds")),
            "list": GeneratedContent(
                kind: .array([GeneratedContent("Vendor"), GeneratedContent(properties: ["provider": "Other", "status": "OK"])])),
        ])

        #expect(values.string("number") == nil)
        #expect(values.bool("number") == nil)
        #expect(values.integer("text") == nil)
        #expect(values.decimal("text") == nil)
        #expect(values.duration("text") == nil)
        #expect(values.structures("text").isEmpty)
        #expect(values.structures("list").map { $0.string("provider") } == ["Other"])
        #expect(values.structures("list").map { $0.integer("status") } == [nil])
    }

    @Test(arguments: [
        (2.016, Duration.milliseconds(2_016)), (0.1, .milliseconds(100)), (12, .seconds(12)), (0.000_000_15, .nanoseconds(150)),
    ])
    func `a number of seconds reads as the exact duration it spells`(seconds: Double, duration: Duration) {
        #expect(values(holding: seconds).duration("value") == duration)
    }

    @Test(arguments: [
        (0.000_012_345, "0.000012345"),
        (0.000_25, "0.00025"),
        (0.000_000_15, "0.00000015"),
        (0.1, "0.1"),
        (123_456_789.123, "123456789.123"),
        (0, "0"),
    ])
    func `an amount reads as the decimal its shortest spelling names`(amount: Double, expected: String) {
        #expect(values(holding: amount).decimal("value") == Decimal(string: expected))
    }

    @Test func `a count that isn't whole or an amount that isn't finite reads as unknown`() {
        #expect(values(holding: 1.5).integer("value") == nil)
        #expect(values(holding: .infinity).decimal("value") == nil)
    }

    /// Values with one number, under the key `value`.
    private func values(holding number: Double) -> MetadataValues {
        MetadataValues(["value": GeneratedContent(kind: .number(number))])
    }
}
