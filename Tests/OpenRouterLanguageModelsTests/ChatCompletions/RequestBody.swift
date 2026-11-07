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
    try sentRequest(request, model: model).json
}

/// What OpenRouter sends for Foundation Models' request, after its exchange prepared it.
func sentRequest(
    _ generation: LanguageModelExecutorGenerationRequest,
    model: OpenRouterLanguageModel<some ModelEffort>
) throws -> ChatCompletions.Request.Body {
    let chat = try model.chatCompletions(model.executorConfiguration)
    let exchange = chat.exchange
    var request = try ChatCompletions.Request(generation, model: chat, exchange: exchange)
    try exchange.prepare(&request)
    return try request.body()
}
