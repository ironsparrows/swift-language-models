import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels
@testable import OpenRouterLanguageModels

@Suite("Request adjustments")
struct RequestAdjustmentTests {
    @Test func `a request whose models list every setting it asks for changes nothing`() throws {
        let options = GenerationOptions(samplingMode: .random(top: 40, seed: 7), temperature: 0.5, maximumResponseTokens: 100)

        #expect(try adjustments(model(HTTPStub()), options: options).isEmpty)
    }

    @Test func `settings the models don't list are left out, in the order the body has them`() throws {
        let options = GenerationOptions(samplingMode: .random(top: 40, seed: 7), temperature: 0.5, maximumResponseTokens: 100)
        let model = model(
            HTTPStub(), parameters: [.maxTokens, .presencePenalty],
            options: OpenRouterOptions(frequencyPenalty: 0.5, presencePenalty: 0.5, stopSequences: ["END"]))

        let unlisted = ["temperature", "top_k", "seed", "frequency_penalty", "stop"]
        #expect(try adjustments(model, options: options) == [.unlistedParameters(unlisted)])
    }

    @Test func `a token limit is left out when the models list neither of its parameters`() throws {
        let model = model(HTTPStub(), parameters: [.temperature])

        #expect(try adjustments(model, options: GenerationOptions(maximumResponseTokens: 100)) == [.unlistedParameters(["max_tokens"])])
    }

    @Test func `greedy sampling is left out only when the models don't list temperature`() throws {
        let greedy = GenerationOptions(samplingMode: .greedy)

        #expect(try adjustments(model(HTTPStub(), parameters: [.temperature]), options: greedy).isEmpty)
        #expect(try adjustments(model(HTTPStub(), parameters: [.topK]), options: greedy) == [.unlistedParameters(["temperature"])])
    }

    @Test(arguments: [
        (ContextOptions.ReasoningLevel.moderate, RequestAdjustment?.some(.movedEffort(requested: "medium", sent: "low"))),
        (.deep, nil),
        (.off, nil),
        (.custom("turbo"), .movedEffort(requested: "turbo", sent: nil)),
    ])
    func `a reasoning level the models don't accept moves to the nearest effort, or is left out`(
        level: ContextOptions.ReasoningLevel,
        adjustment: RequestAdjustment?
    ) throws {
        let model: OpenRouterLanguageModel<ContextOptions.ReasoningLevel> = model(HTTPStub(), efforts: [.custom("high"), .custom("low")])

        #expect(try adjustments(model, reasoningLevel: level) == [adjustment].compactMap(\.self))
    }

    @Test func `a request with metadata it leaves out notes the keys`() throws {
        let adjustments = try adjustments(model(HTTPStub()), metadata: ["count": 3, "name": "Ada"])

        #expect(adjustments == [.droppedMetadata(keys: ["count"])])
    }
}

/// The adjustments of the request for one prompt.
private func adjustments(
    _ model: OpenRouterLanguageModel<some ModelEffort>,
    options: GenerationOptions = GenerationOptions(),
    reasoningLevel: ContextOptions.ReasoningLevel? = nil,
    metadata: [String: any ConvertibleToGeneratedContent] = [:]
) throws -> [RequestAdjustment] {
    let request = LanguageModelExecutorGenerationRequest(
        id: UUID(), transcript: Transcript(entries: [.prompt(Transcript.Prompt(segments: [.text(.init(content: "Hi"))]))]),
        enabledTools: [], generationOptions: options, contextOptions: ContextOptions(reasoningLevel: reasoningLevel),
        metadata: metadata)
    return try sentRequest(request, model: model).adjustments
}
