import Foundation
import LanguageModels
import LanguageModelsTestSupport

@testable import OpenRouterLanguageModels

/// A JSON response whose body is a fixture saved from OpenRouter, or built from its API description.
func fixtureResponse(_ name: String, status: Int = 200) throws -> StubResponse {
    .json(String(decoding: try Bundle.module.fixture(name), as: UTF8.self), status: status)
}

/// A transport to a stub with the given headers, a cache of its own unless one is given, and the shared retry policy
/// without its waits.
func transport(
    _ stub: HTTPStub,
    cacheLifetime: Duration = .seconds(60),
    headers: [String: String] = [:],
    cache: InfoCache = InfoCache(),
    retryLimit: Int = RequestRetries.standard.limit
) -> APITransport {
    let authentication = Connection.Authentication(baseURL: stub.baseURL) { headers }
    let connection = Connection(
        session: stub.session, authentication: authentication, idleTimeout: nil,
        retries: .immediate(limit: retryLimit), retrying: API.retriesStatus)
    return APITransport(connection: connection, cacheLifetime: cacheLifetime, cache: cache)
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
