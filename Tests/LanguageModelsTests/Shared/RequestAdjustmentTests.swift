import FoundationModels
import Testing

@testable import LanguageModels

@Suite("API format: request adjustments and metadata")
struct RequestAdjustmentTests {
    @Test func `metadata past the limits, or not a string, is left out and named by key`() {
        var metadata: [String: GeneratedContent] = Dictionary(
            uniqueKeysWithValues: (100..<117).map { ("key\($0)", GeneratedContent("value")) })
        metadata["count"] = GeneratedContent(3)
        metadata[String(repeating: "k", count: 65)] = GeneratedContent("too long a key")
        metadata["long"] = GeneratedContent(String(repeating: "v", count: 513))

        let (json, droppedKeys) = RequestMetadata.limited(metadata)

        #expect(droppedKeys == ["count", String(repeating: "k", count: 65), "key116", "long"].sorted())
        guard case .object(let sent)? = json else {
            Issue.record("The metadata isn't an object: \(String(describing: json))")
            return
        }
        #expect(sent.members.map(\.key) == (100..<116).map { "key\($0)" })
    }

    @Test(arguments: [
        RequestAdjustment.unlistedParameters(["temperature", "seed"]),
        .droppedMetadata(keys: ["user-qz9@example.com"]),
        .movedEffort(requested: "medium", sent: "low"),
        .movedEffort(requested: "turbo", sent: nil),
    ])
    func `each message names the model and never a metadata key`(adjustment: RequestAdjustment) {
        let message = adjustment.message(model: "vendor/model", provider: "Vendor")

        #expect(message.contains("vendor/model"))
        #expect(!message.contains("qz9"))
    }

    @Test func `the runtime warning adds the keys of metadata left out to the message`() {
        let dropped = RequestAdjustment.droppedMetadata(keys: ["count", "note"])
        let moved = RequestAdjustment.movedEffort(requested: "medium", sent: "low")

        let message = dropped.message(model: "vendor/model", provider: "Vendor")
        #expect(dropped.warning(model: "vendor/model", provider: "Vendor") == "\(message) Keys: count, note.")
        #expect(moved.warning(model: "vendor/model", provider: "Vendor") == moved.message(model: "vendor/model", provider: "Vendor"))
    }
}
