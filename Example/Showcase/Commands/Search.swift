import Foundation
import FoundationModels
import OpenRouterLanguageModels

/// Server tools: OpenRouter searches the web while the model answers, and the answer lists the pages it cites.
///
/// The app implements nothing; the model calls the search as it needs, and only its answer reaches the session.
struct Search: Command {
    let name = "search"
    let summary = "Answer from a web search, with numbered citations"
    let usage = "[question]"

    func run(_ arguments: [String]) async throws {
        let model = OpenRouterLanguageModel(
            .openaiGpt5_4Mini,
            serverTools: [.webSearch(maximumResults: 5)],
            auth: .apiKey(openRouterKey)
        )
        let session = LanguageModelSession(model: model)
        let question = arguments.text(or: "What's new in the latest Swift release?")

        let stream = session.streamResponse(to: question)
        var answer = Streamer()
        for try await snapshot in stream {
            answer.show(snapshot.content)
        }
        answer.finish()

        let response = try await stream.collect()
        if case .response(let entry)? = response.transcriptEntries.last {
            for (index, citation) in entry.openRouter.citations.enumerated() {
                print("[\(index + 1)] \(citation.title ?? "Untitled")", Style.dim(citation.url.absoluteString))
            }
        }
        print(Footer(response))
    }
}
