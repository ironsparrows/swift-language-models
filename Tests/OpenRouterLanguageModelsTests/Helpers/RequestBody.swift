import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport

@testable import OpenRouterLanguageModels

/// The body OpenRouter sends for Foundation Models' request, straight from the model, without the checks a session makes
/// first.
///
/// - Parameters:
///   - request: Foundation Models' request.
///   - model: A model that sends to the stub.
///   - stub: The stub, which answers the request.
/// - Returns: The body the stub received.
/// - Throws: What the model throws for the request.
func requestBody(
    _ request: LanguageModelExecutorGenerationRequest,
    model: OpenRouterLanguageModel<some ModelEffort>,
    stub: HTTPStub
) async throws -> JSONValue {
    let channel = LanguageModelExecutorGenerationChannel()
    let reader = Task { for try await _ in channel {} }
    defer { reader.cancel() }
    _ = try await model.chatCompletions(model.executorConfiguration).run(request, streamingInto: channel)
    return try body(stub)
}
