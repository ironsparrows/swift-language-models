import InlineSnapshotTesting
import Testing

@testable import LanguageModelsTestSupport

@Suite("Exact exchange")
struct ExactExchangeTests {
    @Test func `a request without its headers or its body shows in the text`() {
        var exchange = ExactExchange()
        exchange.bodies = ["{}", "[]"]
        exchange.headers = [[]]

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            {}

            request 2
            <no headers recorded>
            []
            """
        }

        exchange.bodies = []

        assertInlineSnapshot(of: exchange, as: .exchange) {
            """
            request 1
            <no body recorded>
            """
        }
    }
}
