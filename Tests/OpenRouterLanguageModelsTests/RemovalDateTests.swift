import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels
@testable import LanguageModelsCore
@testable import OpenRouterLanguageModels

@Suite("Removal date")
struct RemovalDateTests {
    @Test func `a model OpenRouter lists has no removal date`() {
        #expect(fallback("vendor/model").removalDate == nil)
    }

    @Test func `the catalog's removed models carry the day they left and are left out of its lookup by id`() throws {
        // Removed models stay in the catalog, so an empty list means the removals weren't generated.
        try #require(!ModelRemovals.openRouter.dates.isEmpty)
        for (id, day) in ModelRemovals.openRouter.dates {
            let id = OpenRouterModelID(rawValue: id)

            #expect(fallback(id).removalDate == day)
            #expect(OpenRouterModel<ContextOptions.ReasoningLevel>(catalogID: id) == nil)
        }
    }

    @Test func `a request reports the removed models it may reach, in the order OpenRouter tries them`() throws {
        let removed = ModelRemovals.openRouter.dates.sorted { $0.key > $1.key }
        let first = try #require(removed.first)
        let last = try #require(removed.last)
        try #require(first.key != last.key)
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(
            HTTPStub(), id: OpenRouterModelID(rawValue: first.key),
            fallbacks: [fallback("vendor/listed"), fallback(OpenRouterModelID(rawValue: last.key))])

        let reports = try model.chatCompletions(model.executorConfiguration).removedModels

        #expect(
            reports == [
                ModelRemovals.Report(id: first.key, removedOn: first.value), ModelRemovals.Report(id: last.key, removedOn: last.value),
            ])
        #expect(reports.first?.message.hasPrefix("The request names \(first.key), which its provider stopped listing on") == true)
    }

    @Test func `a request that reaches only models OpenRouter lists reports none`() throws {
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(HTTPStub(), fallbacks: [fallback("vendor/listed")])

        #expect(try model.chatCompletions(model.executorConfiguration).removedModels.isEmpty)
    }

    @Test func `a request to a removed model is still sent`() async throws {
        let id = try #require(ModelRemovals.openRouter.dates.keys.min())
        let stub = HTTPStub(events(text("Hi"), done()))
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, id: OpenRouterModelID(rawValue: id))
        let request = generationRequest([.prompt(Transcript.Prompt(segments: [.text(.init(content: "Hi"))]))])
        let channel = LanguageModelExecutorGenerationChannel()
        let reader = Task { for try await _ in channel {} }
        defer { reader.cancel() }

        try await model.chatCompletions(model.executorConfiguration).respond(to: request, streamingInto: channel)

        let sent = try #require(stub.requests.first)
        #expect(try JSONValue(json: sent.body)["model"]?.stringValue == id)
    }
}
