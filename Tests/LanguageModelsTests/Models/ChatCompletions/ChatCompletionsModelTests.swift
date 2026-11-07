import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

@Suite("Chat Completions model")
struct ChatCompletionsModelTests {
    @Test func `a request goes to chat/completions with the provider's headers, and its answer streams back`() async throws {
        let stub = HTTPStub(
            chatCompletionsEvents(["choices": [["delta": ["content": "Hi"]]]], ["choices": [["delta": [:], "finish_reason": "stop"]]]))

        let (answer, failure) = await respond(stub, to: [prompt(text("Hello"))])

        if let failure { Issue.record("The answer failed: \(failure)") }
        #expect(answer?.responseText == "Hi")
        let sent = try #require(stub.requests.first)
        #expect(sent.request.url?.path == "/chat/completions")
        #expect(sent.request.value(forHTTPHeaderField: "X-Test") == "yes")
        #expect(
            String(decoding: sent.body, as: UTF8.self)
                == #"{"model":"vendor/model","messages":[{"role":"user","content":"Hello"}],"stream":true}"#)
    }

    @Test func `a plain model answers in a session with no provider`() async throws {
        let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]]]))

        let response = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")

        #expect(response.content == "Hi")
        #expect(stub.requests.first?.request.url?.path == "/chat/completions")
    }

    @Test func `a plain model throws a failure as it is`() async {
        let stub = HTTPStub(.json(#"{"error":{"message":"Bad key."}}"#, status: 401))

        await #expect(throws: RequestFailure<APIErrorBody>.self) {
            _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Hello")
        }
    }

    @Test func `a plain model holds an answer to its schema's guides`() async {
        let stub = HTTPStub(chatCompletionsEvents(["choices": [["delta": ["content": #"{"stars":9}"#], "finish_reason": "stop"]]]))

        await #expect(throws: GeneratedContent.ParsingError.self) {
            _ = try await LanguageModelSession(model: plainModel(stub)).respond(to: "Rate it.", generating: Rating.self)
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

    @Test func `a host that rejects a constraint of the schema gets the portable schema once`() async throws {
        let rejection = #"{"error":{"message":"Keyword 'maximum' is not supported for type 'integer'"}}"#
        let stub = HTTPStub(
            .json(rejection, status: 400),
            chatCompletionsEvents(["choices": [["delta": ["content": #"{"stars":4}"#], "finish_reason": "stop"]]]))

        let (answer, failure) = await respond(stub, to: [prompt(text("Rate it."))], schema: Rating.generationSchema)

        if let failure { Issue.record("The answer failed: \(failure)") }
        #expect(answer?.responseText == #"{"stars":4}"#)
        let bodies = try stub.requests.map { try JSONValue(json: $0.body) }
        #expect(bodies.count == 2)
        #expect(bodies.first?["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == 5)
        #expect(bodies.last?["response_format"]?["json_schema"]?["schema"]?["properties"]?["stars"]?["maximum"] == nil)
    }

    @Test func `the provider's own members of each chunk add reasoning and the host`() async throws {
        let stub = HTTPStub(
            chatCompletionsEvents(
                ["host": "Vendor", "choices": [["delta": ["reasoning": "Think."]]]],
                ["choices": [["delta": ["content": "Hi"], "finish_reason": "stop"]]]))

        let (answer, failure) = await respond(stub, to: [prompt(text("Hello"))])

        if let failure { Issue.record("The answer failed: \(failure)") }
        #expect(answer?.responseText == "Hi")
    }
}

/// A model of the plain format, sending to a stub.
private func plainModel(_ stub: HTTPStub) -> ChatCompletions.Model<ChatCompletions.PlainExchange> {
    var model = ChatCompletions.Model(name: "vendor/model", url: stub.baseURL)
    model.connection = Connection(
        session: stub.session, authentication: .unauthenticated, idleTimeout: nil, retries: .disabled, retrying: { _ in false })
    return model
}

/// Runs one exchange of the test model with a stub, reading the channel's events without looking at them, since a channel
/// waits for its reader.
///
/// - Returns: The answer, or the failure it ended in.
private func respond(
    _ stub: HTTPStub,
    to entries: [Transcript.Entry],
    schema: GenerationSchema? = nil
) async -> (DetailedLanguageModelAnswer?, RequestFailure<APIErrorBody>?) {
    let model = ChatCompletions.Model<ChatCompletionsTestExchange>.test(url: stub.baseURL, session: stub.session)
    let channel = LanguageModelExecutorGenerationChannel()
    let reader = Task { for try await _ in channel {} }
    defer { reader.cancel() }
    do {
        let text = try await model.run(generationRequest(entries, schema: schema), streamingInto: channel)
        return (DetailedLanguageModelAnswer(responseText: text), nil)
    } catch let failure as RequestFailure<APIErrorBody> {
        return (nil, failure)
    } catch {
        Issue.record("The model threw \(error)")
        return (nil, nil)
    }
}
