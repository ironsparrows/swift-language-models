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

            let failure = await respond(stub, to: [prompt(text("Hello"))])

            guard case .unusableAnswer? = failure?.kind, failure?.message == "The response ended before it was complete." else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
        }

        @Test func `an error event mid-stream fails the answer with its error object`() async {
            let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": "Hi"]]]], ["error": ["message": "Overloaded."]]))

            let failure = await respond(stub, to: [prompt(text("Hello"))])

            guard case .errorEvent? = failure?.kind, let error = failure?.body else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(error.message == "Overloaded.")
        }

        @Test(arguments: [true, false])
        func `a chunk whose type is error fails the answer with the error in its own members`(endsWithDone: Bool) async {
            let error: JSONValue = ["type": "error", "message": "Overloaded.", "code": "server_error"]
            let lines = [textChunk("Hi"), error].map { "data: \($0.text)\n\n" } + (endsWithDone ? ["data: [DONE]\n\n"] : [])
            let stub = HTTPStub(.eventStream(Data(lines.joined().utf8)))

            let failure = await respond(stub, to: [prompt(text("Hello"))])

            guard case .errorEvent? = failure?.kind, let body = failure?.body else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(body.message == "Overloaded.")
            #expect(body.code == "server_error")
        }

        @Test(
            arguments: [
                // A required call the model didn't make, after its text, with no finish reason, as Groq sends it.
                (
                    #"{"error":{"message":"Tool choice is required, but model did not call a tool","type":"invalid_request_error","code":"tool_use_failed","failed_generation":"","status_code":400}}"#,
                    "Tool choice is required, but model did not call a tool", "tool_use_failed"
                ),
                // A prompt longer than the context, as LM Studio is reported to send it.
                (
                    #"{"error":{"message":"Input does not fit in context length. The input has 31430 tokens, but the context length only supports 30000 tokens."},"message":"Input does not fit in context length. The input has 31430 tokens, but the context length only supports 30000 tokens."}"#,
                    "Input does not fit in context length. The input has 31430 tokens, but the context length only supports 30000 tokens.",
                    nil
                ),
                (#"{"message":"Overloaded.","code":"server_error"}"#, "Overloaded.", "server_error"),
                ("Overloaded.", "Overloaded.", nil),
                (#""Overloaded.""#, "Overloaded.", nil),
                (#"{"error":"Overloaded."}"#, "Overloaded.", nil),
                (#"{"detail":"Overloaded."}"#, #"{"detail":"Overloaded."}"#, nil),
                // An error without a message keeps its other members.
                (
                    #"{"type":"error","code":"rate_limit_exceeded"}"#, #"{"type":"error","code":"rate_limit_exceeded"}"#,
                    "rate_limit_exceeded"
                ),
                (#"{"error":{"code":503}}"#, #"{"code":503}"#, 503),
                // A message longer than 1,000 characters is cut there.
                (String(repeating: "x", count: 1_500), String(repeating: "x", count: 1_000), nil),
            ] as [(String, String, JSONValue?)])
        func `an event named error fails the answer with the provider's error, whatever its data holds`(
            data: String, message: String, code: JSONValue?
        ) async {
            let chunk =
                #"{"id":"chatcmpl-00000000-0000-4000-8000-000000000001","object":"chat.completion.chunk","created":1794205505,"model":"openai/gpt-oss-20b","system_fingerprint":"fp_8d13edce1d","choices":[{"index":0,"delta":{"content":"?"},"logprobs":null,"finish_reason":null}]}"#
            let stub = HTTPStub(.eventStream(Data("data: \(chunk)\n\nevent: error\ndata: \(data)\n\n".utf8)))

            let failure = await respond(stub, to: [prompt(text("Hello"))])

            guard case .errorEvent? = failure?.kind, let body = failure?.body else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(body.message == message)
            #expect(body.code == code)
        }

        @Test(
            arguments: [
                (
                    #"{"type":"error","code":"rate_limit_exceeded"}"#, #"{"type":"error","code":"rate_limit_exceeded"}"#,
                    "rate_limit_exceeded"
                ),
                (#"{"error":{"code":503}}"#, #"{"code":503}"#, 503),
                (#"{"error":"Overloaded."}"#, "Overloaded.", nil),
            ] as [(String, String, JSONValue?)])
        func `an error chunk whose error has no message fails the answer with its text as the message`(
            data: String, message: String, code: JSONValue?
        ) async {
            let stub = HTTPStub(.eventStream(Data("data: \(textChunk("Hi").text)\n\ndata: \(data)\n\n".utf8)))

            let failure = await respond(stub, to: [prompt(text("Hello"))])

            guard case .errorEvent? = failure?.kind, let body = failure?.body else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(body.message == message)
            #expect(body.code == code)
        }

        @Test func `an answer whose finish reason is error fails`() async {
            let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": "Hi"], "finish_reason": "error"]]]))

            let failure = await respond(stub, to: [prompt(text("Hello"))])

            guard case .failedAnswer? = failure?.kind else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
        }

        @Test func `a failed response's error object names what went wrong`() async {
            let stub = HTTPStub(.json(#"{"error":{"message":"Bad key.","type":"invalid_request_error"}}"#, status: 401))

            let failure = await respond(stub, to: [prompt(text("Hello"))])

            guard case .rejected? = failure?.kind, let rejection = failure else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(rejection.status == .unauthorized)
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

        @Test(arguments: [
            (
                toolCallChunk(0, id: "call_1", name: "lookUp", arguments: #"{"word":"eg"#), "tool_calls",
                "The model sent arguments for lookUp that aren't a whole JSON object."
            ),
            (toolCallChunk(0, id: "call_1", arguments: #"{"word":"egg"}"#), "tool_calls", "The model sent a tool call without its name."),
            (
                toolCallChunk(0, id: "call_1", name: "lookUp", arguments: #"{"word":"eg"#), "length",
                "The answer reached its token limit inside a tool call."
            ),
        ])
        func `a call that can't run fails the answer before any tool runs`(fragment: JSONValue, finishReason: String, message: String) async
        {
            let stub = HTTPStub(
                chatCompletionsEvents(fragment, finishChunk(finishReason)), chatCompletionsEvents(textChunk("Done.", finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()])

            let failure = await #expect(throws: RequestFailure<APIErrorBody>.self) {
                try await session.respond(to: "Define egg.")
            }

            guard case .unusableAnswer? = failure?.kind else {
                Issue.record("The answer ended with \(String(describing: failure))")
                return
            }
            #expect(failure?.message == message)
            #expect(stub.requests.count == 1)
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
