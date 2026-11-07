import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Connection failures")
    struct ConnectionFailures {
        /// What a failed connection surfaces as.
        enum Outcome: Sendable {
            case urlError(URLError.Code)
            case timeout
            case cancellation

            func matches(_ error: (any Error)?) -> Bool {
                switch self {
                case .urlError(let code):
                    return (error as? URLError)?.code == code
                case .timeout:
                    guard case .timeout? = error as? LanguageModelError else { return false }
                    return true
                case .cancellation:
                    return error is CancellationError
                }
            }
        }

        @Test(arguments: [
            (URLError.Code.notConnectedToInternet, Outcome.urlError(.notConnectedToInternet)),
            (.cannotFindHost, .urlError(.cannotFindHost)),
            (.cannotConnectToHost, .urlError(.cannotConnectToHost)),
            (.secureConnectionFailed, .urlError(.secureConnectionFailed)),
            (.timedOut, .timeout),
            (.cancelled, .cancellation),
        ])
        func `a connection that fails before a response throws the matching error`(code: URLError.Code, outcome: Outcome)
            async throws
        {
            // A failed connection is retried twice, so it fails three times; a cancellation isn't retried.
            let failure = StubResponse.failure(URLError(code))
            let stub = HTTPStub(failure, failure, failure, events(text("Hi"), done()))

            let error = await #expect(throws: (any Error).self) { try await respond(stub) }

            #expect(outcome.matches(error), "Got \(String(describing: error))")
            #expect(stub.requests.count == (code == .cancelled ? 1 : 3))
        }

        @Test func `an error that the API key closure throws passes through as it is, before any request`() async throws {
            struct KeychainLocked: Error {}
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, efforts: [Efforts.Unsupported](), auth: .apiKey { throw KeychainLocked() })

            await #expect(throws: KeychainLocked.self) { try await LanguageModelSession(model: model).respond(to: "Hi") }
            #expect(stub.requests.isEmpty)
        }

        @Test func `a URLError that the API key closure throws passes through, as a failed connection's does`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, efforts: [Efforts.Unsupported](), auth: .apiKey { throw URLError(.notConnectedToInternet) })

            let error = await #expect(throws: (any Error).self) { try await LanguageModelSession(model: model).respond(to: "Hi") }

            #expect(Outcome.urlError(.notConnectedToInternet).matches(error), "Got \(String(describing: error))")
        }

        @Test(arguments: [(URLError.Code.networkConnectionLost, Outcome.urlError(.networkConnectionLost)), (.timedOut, .timeout)])
        func `a connection that drops mid-stream throws the matching error`(code: URLError.Code, outcome: Outcome) async throws {
            let stub = HTTPStub(unfinishedEvents(text("Hel"), text("lo")).droppingConnection(with: URLError(code)))

            let error = await #expect(throws: (any Error).self) { try await respond(stub) }

            #expect(outcome.matches(error), "Got \(String(describing: error))")
        }
    }
}
