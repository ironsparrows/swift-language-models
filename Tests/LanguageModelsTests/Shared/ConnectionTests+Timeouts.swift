import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ConnectionTests {
    @Suite("Timeouts")
    struct Timeouts {
        @Test func `the idle timeout becomes the request's timeout`() async throws {
            let stub = HTTPStub(answer)

            _ = try await LanguageModelSession(model: plainModel(stub, idleTimeout: .seconds(42))).respond(to: "Hi")

            #expect(try #require(stub.requests.first).request.timeoutInterval == 42)
        }
    }
}
