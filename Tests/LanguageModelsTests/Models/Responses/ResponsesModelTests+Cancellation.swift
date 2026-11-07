import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Cancellation")
    struct Cancellation {
        @Test func `cancelling an answer mid-stream throws CancellationError, and the session answers the next prompt`() async throws {
            let stub = HTTPStub(
                events(textDelta("One")).keepingConnectionOpen(),
                events(textDelta("Again."), lifecycle("response.completed")))
            let session = LanguageModelSession(model: plainModel(stub))
            var sentResponses = stub.sentResponses.makeAsyncIterator()

            await #expect(throws: CancellationError.self) {
                try await withThrowingTaskGroup { group in
                    group.addTask { _ = try await session.respond(to: "Count.") }
                    // The stub has sent the answer's start and keeps the connection open, so the answer is in flight.
                    _ = await sentResponses.next()
                    group.cancelAll()
                    try await group.waitForAll()
                }
            }

            #expect(stub.requests.count == 1)
            #expect(try await session.respond(to: "Again?").content == "Again.")
        }
    }
}
