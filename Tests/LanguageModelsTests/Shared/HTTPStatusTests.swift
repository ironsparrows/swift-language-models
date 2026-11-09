import Testing

@testable import LanguageModels

/// What a status is called, the number it stands for, and which statuses each rule retries.
@Suite("HTTP status", .timeLimit(.minutes(1)))
struct HTTPStatusTests {
    @Test(arguments: [
        (HTTPStatus.badRequest, 400), (.unauthorized, 401), (.paymentRequired, 402), (.forbidden, 403), (.notFound, 404),
        (.requestTimeout, 408), (.conflict, 409), (.preconditionFailed, 412), (.contentTooLarge, 413),
        (.unprocessableContent, 422), (.tooManyRequests, 429), (.internalServerError, 500), (.badGateway, 502),
        (.serviceUnavailable, 503), (.gatewayTimeout, 504), (.originTimeout, 524), (.overloaded, 529),
    ])
    func `a named status and its number stand for each other`(status: HTTPStatus, code: Int) {
        #expect(HTTPStatus(code: code) == status)
        #expect(status.code == code)
    }

    @Test(arguments: [0, 418])
    func `any other number keeps its number`(code: Int) {
        #expect(HTTPStatus(code: code) == .other(code))
        #expect(HTTPStatus(code: code).code == code)
    }

    @Test(arguments: [
        (RetriedStatuses.transient, [408, 409, 429, 500, 501, 504, 524, 529, 599, 600], [0, 307, 400, 401, 403, 404, 422, 499]),
        (.serverErrors, [500, 501, 502, 503, 504, 524, 529, 599], [0, 307, 400, 408, 409, 429, 499, 600]),
        (.rateLimits, [429], [0, 307, 400, 408, 409, 413, 499, 500, 503, 529, 599, 600]),
    ])
    func `a rule retries its statuses and no others`(rule: RetriedStatuses, retried: [Int], others: [Int]) {
        #expect(retried.allSatisfy { rule.contains(HTTPStatus(code: $0)) })
        #expect(!others.contains { rule.contains(HTTPStatus(code: $0)) })
    }
}
