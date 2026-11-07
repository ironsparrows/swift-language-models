import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ResponsesModelTests {
    @Suite("Failures")
    struct Failures {
        @Test func `a plain model throws a failure as it is`() async {
            let stub = HTTPStub(.json(#"{"error":{"message":"Bad key."}}"#, status: 401))

            await #expect(throws: RequestFailure<APIErrorBody>.self) {
                _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")
            }
        }

        @Test func `a stream that ends before the response completes is cut off, even after a done`() async {
            let stub = HTTPStub(.eventStream(Data("data: \(textDelta("Hi").text)\n\ndata: [DONE]\n\n".utf8)))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .unusableAnswer? = failure?.kind, failure?.message == "The response ended before it was complete." else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
        }

        @Test(
            arguments: [
                ["type": "error", "code": "server_error", "message": "Overloaded.", "param": nil, "sequence_number": 2],
                [
                    "type": "error", "sequence_number": 2,
                    "error": ["type": "server_error", "code": "server_error", "message": "Overloaded."],
                ],
            ] as [JSONValue])
        func `an error event mid-stream fails the answer with its error, flat or nested`(event: JSONValue) async {
            let stub = HTTPStub(events(textDelta("Hi"), event))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .errorEvent? = failure?.kind, let error = failure?.body else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(error.message == "Overloaded.")
            #expect(error.code == "server_error")
        }

        @Test func `a failed response fails the answer with the response's error`() async {
            let stub = HTTPStub(
                events(textDelta("Hi"), lifecycle("response.failed", ["error": ["code": "rate_limit_exceeded", "message": "Slow down."]])))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .failedAnswer? = failure?.kind else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            let error = failure?.body
            #expect(error?.message == "Slow down.")
            #expect(error?.code == "rate_limit_exceeded")
        }

        @Test func `a failed response's error object names what went wrong`() async {
            let stub = HTTPStub(
                .json(#"{"error":{"message":"Bad key.","type":"invalid_request_error","code":"invalid_api_key"}}"#, status: 401))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .rejected? = failure?.kind, let rejection = failure else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(rejection.status == 401)
            #expect(rejection.body?.message == "Bad key.")
        }

        @Test func `a refusal fails the answer as Foundation Models' refusal`() async {
            let refusal: JSONValue = ["type": "response.refusal.delta", "output_index": 0, "content_index": 0, "delta": "I can't."]
            let stub = HTTPStub(events(refusal, lifecycle("response.completed")))

            let (_, error) = await respondThrowing(stub, to: [prompt(text("Hello"))])

            guard case .refusal? = error as? LanguageModelError else {
                Issue.record("The answer ended with \(String(describing: error))")
                return
            }
        }

        @Test func `an answer a content filter stopped fails as a guardrail violation`() async {
            let stub = HTTPStub(
                events(textDelta("Hi"), lifecycle("response.incomplete", ["incomplete_details": ["reason": "content_filter"]])))

            let (_, error) = await respondThrowing(stub, to: [prompt(text("Hello"))])

            guard case .guardrailViolation? = error as? LanguageModelError else {
                Issue.record("The answer ended with \(String(describing: error))")
                return
            }
        }

        @Test func `a failed response without an error object fails the answer all the same`() async {
            let stub = HTTPStub(events(textDelta("Hi"), lifecycle("response.failed", ["status": "failed"])))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .failedAnswer? = failure?.kind, failure?.body == nil else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
        }
    }
}
