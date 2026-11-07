import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterOptionsTests {
    @Suite("Settings")
    struct Settings {
        @Test func `a setting goes in the body only when every model lists its parameter`() throws {
            let options = OpenRouterOptions(
                frequencyPenalty: 0.5, presencePenalty: 0.2, stopSequences: ["END"], logitBias: [50_256: -100, 13: 2.5], verbosity: .low,
                serviceTier: .flex, endUserID: "user-1")
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(
                HTTPStub(), parameters: [.frequencyPenalty, .stop, .logitBias], cacheControl: nil, options: options)

            let body = try requestBody([.prompt(Transcript.Prompt(segments: [.text(.init(content: "Hi"))]))], model: model)

            let settings = keys(body).filter {
                ["frequency_penalty", "presence_penalty", "stop", "logit_bias", "verbosity", "service_tier", "user"].contains($0)
            }
            #expect(settings == ["frequency_penalty", "stop", "logit_bias", "service_tier", "user"])
            #expect(body["logit_bias"]?.text == #"{"13":2.5,"50256":-100}"#)
        }

        @Test(arguments: [
            (OpenRouterOptions.ParallelToolCalls.automatic, JSONValue?.none), (.allowed, true), (.disallowed, false),
        ])
        func `parallel tool calls go with the session's tools only when the options choose`(
            choice: OpenRouterOptions.ParallelToolCalls,
            sent: JSONValue?
        ) throws {
            let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(
                HTTPStub(), parameters: chatParameters.union([.parallelToolCalls]), options: OpenRouterOptions(parallelToolCalls: choice))
            let request = LanguageModelExecutorGenerationRequest(
                id: UUID(), transcript: Transcript(entries: [.prompt(Transcript.Prompt(segments: [.text(.init(content: "Hi"))]))]),
                enabledTools: [Transcript.ToolDefinition(tool: FoodTool())], generationOptions: GenerationOptions(),
                contextOptions: ContextOptions(), metadata: [:])

            let body = try requestBody(request, model: model)

            #expect(body["parallel_tool_calls"] == sent)
        }
    }
}

/// The keys of an object, in order.
private func keys(_ value: JSONValue) -> [String] {
    if case .object(let object) = value { object.members.map(\.key) } else { [] }
}
