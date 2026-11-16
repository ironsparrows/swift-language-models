import Foundation
import FoundationModels
import OpenRouterLanguageModels

/// Fallbacks and routing: OpenRouter tries the models in order until one answers, on the hosts the routing allows,
/// and the answer names the model and host that served it.
///
/// Any of the models may answer, so a request asks only for what all of them support.
struct Fallbacks: Command {
    let name = "fallbacks"
    let summary = "Route across fallback models and hosts, and see which answered"
    let usage = "[prompt]"

    func run(_ arguments: [String]) async throws {
        let model = OpenRouterLanguageModel(
            .anthropicClaudeHaiku5_5,
            fallbacks: .openaiGpt5_4Mini, .googleGemini2_5FlashLite,
            routing: OpenRouterRouting(dataCollection: .deny, sort: .price),
            auth: .apiKey(openRouterKey)
        )
        let tried = ([model.details.id] + model.fallbacks.map(\.id)).map(\.rawValue)
        print(Style.dim("Trying \(tried.joined(separator: ", then ")), on hosts that don't collect prompts, cheapest first."))

        let prompt = arguments.text(or: "Suggest a name for a lighthouse keeper's cat.")
        let response = try await LanguageModelSession(model: model).respond(to: prompt)
        print(response.content)

        if case .response(let answer)? = response.transcriptEntries.last {
            let answeredBy = answer.openRouter.model?.rawValue ?? "An unnamed model"
            print(Style.green("\(answeredBy) answered, on \(answer.openRouter.provider ?? "an unnamed host")."))
        }
        print(Footer(response))
    }
}
