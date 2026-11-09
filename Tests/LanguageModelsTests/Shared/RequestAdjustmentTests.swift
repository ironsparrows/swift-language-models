import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

@Suite("Request adjustments", .timeLimit(.minutes(1)))
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

    @Test func `metadata a Chat Completions request leaves out is noted by key`() throws {
        let generation = generationRequest([prompt(text("Hi"))], metadata: ["count": 3, "name": "Ada"])

        #expect(try ChatCompletionsSentRequest(generation).adjustments == [.droppedMetadata(keys: ["count"])])
    }

    @Test func `metadata a Responses request leaves out is noted by key`() throws {
        let generation = generationRequest([prompt(text("Hi"))], metadata: ["count": 3, "name": "Ada"])

        #expect(try ResponsesSentRequest(generation).adjustments == [.droppedMetadata(keys: ["count"])])
    }

    @Test(
        arguments: [(MovedEffort(requested: "medium", sent: "low"), "low"), (MovedEffort(requested: "turbo", sent: nil), nil)]
            as [(MovedEffort, String?)])
    func `an effort that a Chat Completions exchange moved is noted`(moved: MovedEffort, sent: String?) throws {
        var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
        model.exchange.prepares = { $0.movedEffort = moved }

        let adjustments = try ChatCompletionsSentRequest(generationRequest([prompt(text("Hi"))]), model: model).adjustments

        #expect(adjustments == [.movedEffort(requested: moved.requested, sent: sent)])
    }

    @Test(
        arguments: [(MovedEffort(requested: "medium", sent: "low"), "low"), (MovedEffort(requested: "turbo", sent: nil), nil)]
            as [(MovedEffort, String?)])
    func `an effort that a Responses exchange moved is noted`(moved: MovedEffort, sent: String?) throws {
        var model = Responses.Model<ResponsesTestExchange>.test()
        model.exchange.prepares = { $0.movedEffort = moved }

        let adjustments = try ResponsesSentRequest(generationRequest([prompt(text("Hi"))]), model: model).adjustments

        #expect(adjustments == [.movedEffort(requested: moved.requested, sent: sent)])
    }

    @Test(arguments: [
        RequestAdjustment.unlistedParameters(["temperature", "seed"]),
        .droppedMetadata(keys: ["user-qz9@example.com"]),
        .movedEffort(requested: "medium", sent: "low"),
        .movedEffort(requested: "turbo", sent: nil),
        .keptMembers(["stream", "tools"]),
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
