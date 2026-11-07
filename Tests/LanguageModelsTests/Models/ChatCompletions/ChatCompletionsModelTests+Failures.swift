import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Failures")
    struct Failures {
        @Test func `a plain model throws a failure as it is`() async {
            let stub = HTTPStub(.json(#"{"error":{"message":"Bad key."}}"#, status: 401))

            await #expect(throws: RequestFailure<APIErrorBody>.self) {
                _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")
            }
        }

        @Test func `a stream that ends before its end and before a finish reason is cut off`() async {
            let stub = HTTPStub(.eventStream(Data(#"data: {"choices":[{"delta":{"content":"Hi"}}]}\#n\#n"#.utf8)))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .unusableAnswer? = failure?.kind, failure?.message == "The response ended before it was complete." else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
        }

        @Test func `an error event mid-stream fails the answer with its error object`() async {
            let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": "Hi"]]]], ["error": ["message": "Overloaded."]]))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .errorEvent? = failure?.kind, let error = failure?.body else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(error.message == "Overloaded.")
        }

        @Test func `an answer whose finish reason is error fails`() async {
            let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": "Hi"], "finish_reason": "error"]]]))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .failedAnswer? = failure?.kind else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
        }

        @Test func `a failed response's error object names what went wrong`() async {
            let stub = HTTPStub(.json(#"{"error":{"message":"Bad key.","type":"invalid_request_error"}}"#, status: 401))

            let (_, failure) = await respond(stub, to: [prompt(text("Hello"))])

            guard case .rejected? = failure?.kind, let rejection = failure else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(rejection.status == 401)
            #expect(rejection.body?.message == "Bad key.")
        }

        @Test func `a refusal fails the answer as Foundation Models' refusal`() async {
            let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["refusal": "No."], "finish_reason": "stop"]]]))

            let error = await error(of: stub)

            guard case .refusal? = error as? LanguageModelError else {
                Issue.record("The answer ended with \(String(describing: error))")
                return
            }
        }

        @Test func `an event that isn't a chunk throws`() async {
            let stub = HTTPStub(.eventStream(Data("data: [1, 2]\n\n".utf8)))

            let failure = await error(of: stub) as? RequestFailure<APIErrorBody>

            guard case .unreadableEvent? = failure?.kind, failure?.message.hasPrefix("Test sent an event that couldn't be read") == true
            else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
        }
    }
}
