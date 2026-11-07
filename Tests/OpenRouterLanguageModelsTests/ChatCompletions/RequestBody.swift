import Foundation
import FoundationModels

@testable import LanguageModels
@testable import OpenRouterLanguageModels

/// The body of the request for a transcript, built straight from it, without the checks a session makes first.
func requestBody(_ entries: [Transcript.Entry], model: OpenRouterLanguageModel<some ModelEffort>) throws -> JSONValue {
    let request = LanguageModelExecutorGenerationRequest(
        id: UUID(), transcript: Transcript(entries: entries), enabledTools: [], generationOptions: GenerationOptions(),
        contextOptions: ContextOptions(), metadata: [:])
    return try requestBody(request, model: model)
}

/// The body OpenRouter sends for Foundation Models' request.
func requestBody(_ request: LanguageModelExecutorGenerationRequest, model: OpenRouterLanguageModel<some ModelEffort>) throws -> JSONValue {
    let dialect = OpenRouterChatCompletions(model: model, executor: .init(configuration: model.executorConfiguration))
    return try ChatCompletionRequest(request, dialect: dialect).body
}
