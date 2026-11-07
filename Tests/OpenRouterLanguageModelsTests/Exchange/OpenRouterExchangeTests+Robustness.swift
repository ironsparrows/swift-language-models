import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

extension OpenRouterExchangeTests {
    @Suite("Robustness")
    struct Robustness {
        @Test(arguments: ["\u{2028}", "\u{2029}", "\u{85}"])
        func `a Unicode line break inside an answer doesn't split its event`(separator: String) async throws {
            let stub = HTTPStub(events(text("a\(separator)b"), done()))

            #expect(try await respond(stub) == "a\(separator)b")
        }

        @Test func `an empty data line is skipped`() async throws {
            let stream = "data: \n\ndata: \(String(decoding: text("Hi").data, as: UTF8.self))\n\ndata: [DONE]\n\n"
            let stub = HTTPStub(.eventStream(Data(stream.utf8)))

            #expect(try await respond(stub) == "Hi")
        }

        @Test func `an event that isn't a chunk throws`() async throws {
            let stub = HTTPStub(.eventStream(Data("data: {not json\n\n".utf8)))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.code == .invalidResponse)
        }

        @Test func `events after DONE are ignored`() async throws {
            let answer = String(decoding: text("Hi").data, as: UTF8.self)
            let afterDone = String(decoding: text(" there").data, as: UTF8.self)
            let stream = "data: \(answer)\n\ndata: [DONE]\n\ndata: \(afterDone)\n\n"
            let stub = HTTPStub(.eventStream(Data(stream.utf8)))

            #expect(try await respond(stub) == "Hi")
        }

        @Test func `a stream cut off before it finished throws`() async throws {
            let stub = HTTPStub(unfinishedEvents(text("Hel")))

            let error = try await #require(throws: OpenRouterError.self) { try await respond(stub) }

            #expect(error.code == .invalidResponse)
        }

        @Test func `a stream that ends with a finish reason but no DONE is complete`() async throws {
            let stub = HTTPStub(unfinishedEvents(text("Hello"), done()))

            #expect(try await respond(stub) == "Hello")
        }

        @Test func `two calls with the same id both run`() async throws {
            let stub = HTTPStub(
                events(
                    toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    toolCall(1, id: "call_1", name: "lookUpFood", arguments: #"{"food":"rice"}"#),
                    done("tool_calls")
                ),
                events(text("Done."), done())
            )

            _ = try await LanguageModelSession(model: model(stub), tools: [FoodTool()]).respond(to: "Egg and rice?")

            let outputs = messages(try body(stub, 1)).filter { $0["role"] == "tool" }
            #expect(outputs.map(\.["content"]) == ["egg: 100 kcal", "rice: 100 kcal"])
            #expect(Set(outputs.compactMap { $0["tool_call_id"]?.stringValue }).count == 2)
        }

        @Test func `calls without an index start a new call when their id changes`() async throws {
            let stub = HTTPStub(
                events(
                    toolCall(nil, id: "call_a", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    toolCall(nil, id: "call_b", name: "lookUpFood", arguments: #"{"food":"rice"}"#),
                    done("tool_calls")
                ),
                events(text("Done."), done())
            )

            _ = try await LanguageModelSession(model: model(stub), tools: [FoodTool()]).respond(to: "Egg and rice?")

            let outputs = messages(try body(stub, 1)).filter { $0["role"] == "tool" }
            #expect(outputs.map(\.["tool_call_id"]) == ["call_a", "call_b"])
        }

        @Test func `a session with tools and no instructions sends no empty system message`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            _ = try await LanguageModelSession(model: model(stub), tools: [FoodTool()]).respond(to: "Hi")

            #expect(messages(try body(stub)).map(\.["role"]) == ["user"])
        }

        @Test func `a schema left out of the prompt goes only in the response format`() async throws {
            let stub = HTTPStub(events(text(#"{"name":"Soup"}"#), done()))
            let session = LanguageModelSession(model: model(stub, parameters: [.structuredOutputs]))

            _ = try await session.respond(to: "A dish.", generating: Dish.self, includeSchemaInPrompt: false)

            let body = try body(stub)
            #expect(body["response_format"]?["type"] == "json_schema")
            #expect(messages(body).last?["content"] == "A dish.")
        }

        @Test func `an earlier prompt keeps its schema text when a later request leaves its schema out`() async throws {
            let stub = HTTPStub(events(text(#"{"name":"Soup"}"#), done()), events(text(#"{"name":"Stew"}"#), done()))
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "A dish.", generating: Dish.self)
            _ = try await session.respond(to: "Another.", generating: Dish.self, includeSchemaInPrompt: false)

            let first = try #require(messages(try body(stub, 0)).last)
            let replayed = try #require(messages(try body(stub, 1)).first { $0["role"] == "user" })
            #expect(replayed == first)
        }

        @Test func `an empty reasoning list goes back on the next turn`() async throws {
            let stub = HTTPStub(events(chunk(["reasoning_details": []]), text("Hi"), done()), events(text("Again."), done()))
            let session = LanguageModelSession(model: model(stub))

            _ = try await session.respond(to: "Hi")
            _ = try await session.respond(to: "Again?")

            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["reasoning_details"] == [])
            #expect(assistant["reasoning"] == nil)
        }

        @Test func `metadata within OpenRouter's limits is passed through, sorted`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            var metadata: [String: any ConvertibleToGeneratedContent] = ["b": "2", "a": "1", "count": 3]
            metadata[String(repeating: "k", count: 65)] = "too long a key"
            metadata["long"] = String(repeating: "v", count: 513)

            _ = try await LanguageModelSession(model: model(stub)).respond(to: "Hi", metadata: metadata)

            #expect(try body(stub)["metadata"] == ["a": "1", "b": "2"])
        }

        @Test func `metadata past 16 pairs is cut to the first 16 by key`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            // Three-digit numbers, so the keys sort as their numbers do.
            let keys = (100..<120).map { "key\($0)" }
            let metadata = Dictionary(uniqueKeysWithValues: keys.map { ($0, "value") })

            _ = try await LanguageModelSession(model: model(stub)).respond(to: "Hi", metadata: metadata)

            let sent = try #require(try body(stub)["metadata"])
            guard case .object(let object) = sent else {
                Issue.record("The metadata isn't an object: \(sent)")
                return
            }
            #expect(object.members.map(\.key) == Array(keys.prefix(16)))
        }

        @Test func `a request without metadata sends none`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            try await respond(stub)

            #expect(try body(stub)["metadata"] == nil)
        }

        @Test func `a 402 for too many requests in flight is a rate limit`() async throws {
            let body = #"{"error":{"code":402,"message":"Too many in flight","metadata":{"limit_source":"openrouter_in_flight_budget"}}}"#
            let stub = HTTPStub(.json(body, status: 402, headers: ["Retry-After": "2"]))

            let error = try await #require(throws: LanguageModelError.self) { try await respond(stub) }

            guard case .rateLimited(let info) = error else {
                Issue.record("Expected a rate limit, got \(error)")
                return
            }
            #expect(info.resetDate != nil)
        }
    }
}

@Generable
private struct Dish {
    var name: String
}
