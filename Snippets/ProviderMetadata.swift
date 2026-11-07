// snippet.hide
import Foundation
import FoundationModels
import OpenRouterLanguageModels

func answerFacts(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.response
    let response = try await session.respond(to: "Plan dinner.", options: GenerationOptions(maximumResponseTokens: 300))

    if case .response(let answer)? = response.transcriptEntries.last {
        print("Answered by", answer.providerMetadata.model ?? "an unnamed model")
        print("Run by", answer.providerMetadata.host ?? "an unnamed host")
        if answer.providerMetadata.finishReason == .length {
            print("The answer was cut short at its token limit.")
        }
        for citation in answer.providerMetadata.citations {
            print("Cites", citation.title ?? citation.url.absoluteString)
        }
    }
    // snippet.end
    // snippet.hide
}

func toolCallFacts(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.toolCalls
    let response = try await session.respond(to: "Plan dinner from what's in the fridge.")

    for case .toolCalls(let calls) in response.transcriptEntries {
        print("\(calls.providerMetadata.model ?? "A model") asked for \(calls.count) tool calls.")
    }
    // snippet.end
    // snippet.hide
}

func usageFacts(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.usage
    let response = try await session.respond(to: "Plan dinner.")

    print("Output tokens:", response.usage.output.totalTokenCount)
    if let dollars = response.usage.providerMetadata.cost {
        print("It cost $\(dollars).")
    }
    if let written = response.usage.providerMetadata.cacheWriteTokenCount {
        print("\(written) prompt tokens went into the host's cache.")
    }
    // snippet.end
    // snippet.hide
}

func cost(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.cost
    let response = try await session.respond(to: "Plan dinner from what's in the fridge.")

    // Each round of tool calls is a request of its own, and the entry that ends each request has its cost.
    let cost = response.transcriptEntries.reduce(Decimal.zero) { total, entry in
        switch entry {
        case .toolCalls(let calls): total + (calls.providerMetadata.usage.cost ?? 0)
        case .response(let answer): total + (answer.providerMetadata.usage.cost ?? 0)
        default: total
        }
    }
    print("It cost $\(cost).")
    // snippet.end
    // snippet.hide
}

func errorFacts(session: LanguageModelSession) async throws {
    // snippet.show
    // snippet.errors
    do {
        let response = try await session.respond(to: "Plan dinner.")
        print(response.content)
    } catch let error as LanguageModelError {
        print("HTTP status:", error.providerMetadata.status.map(String.init) ?? "none")
        print("The provider's code:", error.providerMetadata.errorCode ?? "none")
        print("The host that failed:", error.providerMetadata.provider ?? "unnamed")
        print("Request id, for the provider's support:", error.providerMetadata.requestID ?? "none")
    }
    // snippet.end
    // snippet.hide
}
