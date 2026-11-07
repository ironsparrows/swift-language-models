import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// A model's id, whether its details say it caches only marked prompts, and its fallbacks.
private typealias Route = (
    id: OpenRouterModelID, cachesOnlyMarkedPrompts: Bool, fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>]
)

extension OpenRouterOptionsTests {
    @Suite("Prompt caching")
    struct PromptCaching {
        @Test func `the next request starts with the previous request's messages, byte for byte`() async throws {
            let stub = HTTPStub(
                events(toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#), done("tool_calls")),
                events(text("An egg has 100 kcal."), done()),
                events(text("Rice too."), done())
            )
            let session = LanguageModelSession(model: model(stub), tools: [FoodTool()], instructions: "Answer with tools.")

            _ = try await session.respond(to: "Calories in an egg?")
            _ = try await session.respond(to: "And rice?")

            let messages = try stub.requests.map { try #require(messagesText(in: $0.body)) }
            try #require(messages.count == 3)
            for (earlier, later) in zip(messages, messages.dropFirst()) {
                #expect(later.starts(with: earlier.dropLast() + Array(",".utf8)))
            }
            let sessionIDs = try (0..<3).map { try body(stub, $0)["session_id"]?.stringValue }
            #expect(Set(sessionIDs).count == 1)
            #expect(sessionIDs.first??.isEmpty == false)
        }

        @Test func `no cache control sends no marks, even for Claude`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            let model = model(stub, id: "anthropic/claude-haiku-5.5", cacheControl: nil)
            _ = try await LanguageModelSession(model: model, instructions: "Be brief.").respond(to: "Hi")

            try expectNoMarks(body(stub))
        }

        @Test(
            arguments: [
                ("anthropic/claude-haiku-5.5", true, []),
                ("anthropic/claude-haiku-5.5", false, []),
                ("~anthropic/claude-haiku-latest", false, []),
                ("anthropic/claude-haiku-5.5", false, [fallback("~anthropic/claude-sonnet-latest")]),
                ("qwen/qwen3.7-flash", true, []),
                ("qwen/qwen3.7-flash", true, [fallback("anthropic/claude-haiku-5.5")]),
            ] as [Route])
        func `automatic caching marks a route whose models cache only marked prompts`(
            id: OpenRouterModelID, cachesOnlyMarkedPrompts: Bool, fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>]
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            let model = model(stub, id: id, cachesOnlyMarkedPrompts: cachesOnlyMarkedPrompts, fallbacks: fallbacks)
            _ = try await LanguageModelSession(model: model, instructions: "Be brief.").respond(to: "Hi")

            try expectMarks(["type": "ephemeral"], in: body(stub))
        }

        @Test(
            arguments: [
                ("openai/gpt-5.6-luna", false, []),
                ("google/gemini-3.5-flash", false, []),
                ("qwen/qwen3-235b-a22b", false, []),
                ("anthropic/claude-haiku-5.5", true, [fallback("google/gemini-3.5-flash")]),
                ("qwen/qwen3.7-flash", true, [fallback("qwen/qwen3-235b-a22b")]),
            ] as [Route])
        func `automatic caching leaves a route unmarked when a model in it caches on its own`(
            id: OpenRouterModelID, cachesOnlyMarkedPrompts: Bool, fallbacks: [OpenRouterModel<ContextOptions.ReasoningLevel>]
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            let model = model(stub, id: id, cachesOnlyMarkedPrompts: cachesOnlyMarkedPrompts, fallbacks: fallbacks)
            _ = try await LanguageModelSession(model: model, instructions: "Be brief.").respond(to: "Hi")

            try expectNoMarks(body(stub))
        }

        @Test(arguments: [
            (OpenRouterCacheControl.always, OpenRouterModelID("google/gemini-3.5-flash"), JSONValue.object(["type": "ephemeral"])),
            (.always(timeToLive: .oneHour), "vendor/model", .object(["type": "ephemeral", "ttl": "1h"])),
            (.automatic(timeToLive: .oneHour), "anthropic/claude-haiku-5.5", .object(["type": "ephemeral", "ttl": "1h"])),
        ])
        func `a cache control marks the request and the end of the instructions`(
            cacheControl: OpenRouterCacheControl, id: OpenRouterModelID, marker: JSONValue
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            let model = model(stub, id: id, cacheControl: cacheControl)
            _ = try await LanguageModelSession(model: model, instructions: "Be brief.").respond(to: "Hi")

            let body = try body(stub)
            expectMarks(marker, in: body)
            #expect(messages(body).last?["content"] == "Hi")
        }

        /// Expects the request and the end of its instructions to carry the marker.
        private func expectMarks(_ marker: JSONValue, in body: JSONValue) {
            #expect(body["cache_control"] == marker)
            #expect(messages(body).first?["content"] == [["cache_control": marker, "text": "Be brief.", "type": "text"]])
        }

        /// Expects the request and its instructions to carry no marker.
        private func expectNoMarks(_ body: JSONValue) {
            #expect(body["cache_control"] == nil)
            #expect(messages(body).first?["content"] == "Be brief.")
        }

        /// The bytes of the top-level `messages` array in a request body, from its `[` to its `]`.
        ///
        /// The body is walked as JSON, so the same text inside a string or a nested object doesn't count.
        private func messagesText(in body: Data) -> ArraySlice<UInt8>? {
            let bytes = Array(body)
            let key = Array(#""messages":"#.utf8)
            var depth = 0
            var isInString = false
            var isEscaped = false
            var start: Int?
            for (index, byte) in bytes.enumerated() {
                if isInString {
                    if isEscaped {
                        isEscaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        isEscaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        isInString = false
                    }
                    continue
                }
                switch byte {
                case UInt8(ascii: "\""):
                    if depth == 1, start == nil, bytes[index...].starts(with: key) { start = index + key.count }
                    isInString = true
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 1, let start { return bytes[start...index] }
                default:
                    break
                }
            }
            return nil
        }
    }
}
