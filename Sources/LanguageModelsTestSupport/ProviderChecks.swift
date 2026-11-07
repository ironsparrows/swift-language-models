package import FoundationModels
package import LanguageModelsCore
package import Testing

/// Checks what every provider's test target has to show, for a provider built on a shared model.
///
/// The models the provider gives its shared model are the ones the test names, in the order the provider tries them, since
/// each request looks through them for a removed one. And a host may ignore a guide, so an answer that breaks one throws
/// `GeneratedContent.ParsingError` with the ``GuideViolations``, and an answer that meets them decodes.
///
/// It can't see a report, which only logs, so a provider with a format of its own has to show its call to
/// `reportRemovedModels(for:)` another way.
///
/// - Parameters:
///   - model: Creates the provider's model, sending to a stub.
///   - ids: The ids of the models a request of the model may reach, in the order the provider tries them.
///   - reach: Reads the models the provider gives its shared model.
///   - answer: What the provider sends for an answer with this text.
///   - sourceLocation: Where a failure shows.
/// - Throws: What `reach` throws, and what the model throws for the answer that meets its guides.
package func checkProvider<Model: LanguageModel>(
    model: (HTTPStub) -> Model,
    reaching ids: [String],
    reach: (Model) throws -> [any ModelDetails],
    answering answer: (String) -> StubResponse,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let stub = HTTPStub(answer(#"{"stars":9}"#), answer(#"{"stars":4}"#))

    let reached = try reach(model(stub))
    let error = await #expect(throws: GeneratedContent.ParsingError.self, sourceLocation: sourceLocation) {
        try await LanguageModelSession(model: model(stub)).respond(to: "Rate it.", generating: Rating.self)
    }
    let rating = try await LanguageModelSession(model: model(stub)).respond(to: "Rate it.", generating: Rating.self)

    #expect(reached.map { $0.id.rawValue } == ids, sourceLocation: sourceLocation)
    #expect((error?.underlyingError as? GuideViolations)?.violations.map(\.path) == ["stars"], sourceLocation: sourceLocation)
    #expect(rating.content.stars == 4, sourceLocation: sourceLocation)
    #expect(stub.requests.count == 2, sourceLocation: sourceLocation)
}
