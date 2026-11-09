// snippet.hide
import Foundation
import FoundationModels
import OpenAICompatibleLanguageModels

func errors(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.errors
    do {
        let response = try await session.respond(to: "Plan dinner.")
        print(response.content)
    } catch LanguageModelError.rateLimited(let limit) {
        print("Try again after \(limit.resetDate ?? .now).")
    } catch LanguageModelError.contextSizeExceeded(let exceeded) {
        print("The conversation needs \(exceeded.tokenCount) tokens, and the model takes \(exceeded.contextSize).")
    } catch let error as OpenAICompatibleError where error.isQuotaExhausted {
        print("The account at \(error.providerName) is out of credits.")
    } catch let error as OpenAICompatibleError {
        print("\(error.providerName): \(error.code.rawValue), type \(error.errorType?.rawValue ?? "none"): \(error.message)")
        print("The setting it concerns:", error.parameter ?? "none")
        print("HTTP status:", error.status.map(String.init) ?? "none, a failure in the stream")
        print("Request id, for the provider's support:", error.requestID ?? "none")
        print("Wait before retrying:", error.retryAfter?.description ?? "none")
    } catch let error as LanguageModelError {
        print("Provider:", error.openAICompatible.providerName ?? "none")
        print("Code:", error.openAICompatible.code?.rawValue ?? "none")
        print("Request id, for the provider's support:", error.openAICompatible.requestID ?? "none")
    }
    // snippet.end
    // snippet.hide
}

func metadata(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.metadata
    let response = try await session.respond(to: "Plan dinner.", options: GenerationOptions(maximumResponseTokens: 300))
    print("Reasoning tokens:", response.usage.output.reasoningTokenCount)
    if case .response(let answer)? = response.transcriptEntries.last {
        print("Answered by", answer.openAICompatible.model?.rawValue ?? "an unnamed model")
        print("Run by", answer.providerMetadata.host ?? "a host the module can't name")
        print("The provider's id for the request:", answer.openAICompatible.requestID ?? "none")
        if answer.openAICompatible.finishReason == .length {
            print("The answer was cut short at its token limit.")
        }
    }
    // snippet.end
    // snippet.hide
}
