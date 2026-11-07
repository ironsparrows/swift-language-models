import Foundation
import LanguageModels
import LanguageModelsTestSupport

@testable import OpenRouterLanguageModels

/// A JSON response whose body is a fixture saved from OpenRouter, or built from its API description.
func fixtureResponse(_ name: String, status: Int = 200) throws -> StubResponse {
    .json(String(decoding: try Bundle.module.fixture(name), as: UTF8.self), status: status)
}

/// A connection to a stub, with a cache of its own and the shared retry policy without its waits.
func connection(_ stub: HTTPStub) -> Connection {
    let authentication = Connection.Authentication(baseURL: stub.baseURL) { [:] }
    let connection = Connection(
        session: stub.session, authentication: authentication, idleTimeout: nil, retries: .immediate(),
        retrying: .serverErrors)
    return connection.isolatingCache()
}

extension RequestRetries {
    /// The standard retries without their waits, so a test that retries finishes at once.
    static func immediate(limit: Int = RequestRetries.standard.limit) -> Self {
        RequestRetries(limit: limit, initialDelay: .zero)
    }
}

/// The value of a header of the request the stub received at an index.
func header(_ name: String, of stub: HTTPStub, at index: Int = 0) -> String? {
    stub.requests.indices.contains(index) ? stub.requests[index].request.value(forHTTPHeaderField: name) : nil
}
