import Foundation
import FoundationModels
import OpenRouterLanguageModels

/// The line under an answer: its tokens, what the prompt cache did, its cost, whether the response cache answered and
/// the host that served it, such as `412 in (380 cached) · 37 out · $0.00021 · Anthropic`.
struct Footer: CustomStringConvertible {
    let usage: LanguageModelSession.Usage
    let answer: Transcript.Response?

    init(_ response: LanguageModelSession.Response<some Generable>) {
        usage = response.usage
        if case .response(let answer)? = response.transcriptEntries.last {
            self.answer = answer
        } else {
            answer = nil
        }
    }

    var description: String {
        var cache: [String] = []
        if usage.input.cachedTokenCount > 0 {
            cache.append("\(usage.input.cachedTokenCount.formatted()) cached")
        }
        if let written = usage.openRouter.cacheWriteTokenCount, written > 0 {
            cache.append("\(written.formatted()) written")
        }

        var parts = ["\(usage.input.totalTokenCount.formatted()) in" + (cache.isEmpty ? "" : " (\(cache.joined(separator: ", ")))")]
        let reasoning = usage.output.reasoningTokenCount
        parts.append("\(usage.output.totalTokenCount.formatted()) out" + (reasoning > 0 ? " (\(reasoning.formatted()) reasoning)" : ""))
        if let cost = usage.openRouter.cost {
            parts.append(cost.dollars)
        }
        if answer?.openRouter.responseCacheStatus == .hit {
            parts.append("from the response cache")
        }
        if let host = answer?.openRouter.provider {
            parts.append(host.rawValue)
        }
        return Style.dim(parts.joined(separator: " · "))
    }
}

extension Decimal {
    /// The amount in US dollars, to two significant digits, such as `$0.00021`.
    var dollars: String {
        formatted(.currency(code: "USD").precision(.significantDigits(1...2)))
    }
}
