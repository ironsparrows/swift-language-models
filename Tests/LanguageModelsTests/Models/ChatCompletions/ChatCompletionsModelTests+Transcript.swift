import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Transcript")
    struct TranscriptTests {
        @Test func `instructions, prompts, answers and tool outputs become system, user, assistant and tool messages`() throws {
            let call = Transcript.ToolCall(id: "call_1", toolName: "lookUp", arguments: GeneratedContent(properties: ["word": "egg"]))
            let entries: [Transcript.Entry] = [
                .instructions(Transcript.Instructions(segments: [text("Be brief.")], toolDefinitions: [])),
                prompt(text("Define egg.")),
                .response(Transcript.Response(assetIDs: [], segments: [text("Looking it up.")])),
                .toolCalls(Transcript.ToolCalls([call])),
                .toolOutput(Transcript.ToolOutput(id: "call_1", toolName: "lookUp", segments: [text("egg:"), text("an oval")])),
            ]

            let sent = messages(try ChatCompletionsSentRequest(generationRequest(entries)).body)

            #expect(
                sent == [
                    ["role": "system", "content": "Be brief."],
                    ["role": "user", "content": "Define egg."],
                    [
                        "role": "assistant", "content": "Looking it up.",
                        "tool_calls": [
                            ["id": "call_1", "type": "function", "function": ["name": "lookUp", "arguments": #"{"word":"egg"}"#]]
                        ],
                    ],
                    ["role": "tool", "tool_call_id": "call_1", "content": "egg:\nan oval"],
                ])
        }

        @Test func `the provider's own reasoning goes back after the content, in its order, and another provider's doesn't`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.reasoningMember = "reasoning"
            let first = Transcript.Reasoning(metadata: ["reasoningOrigin": "test"], segments: [text("Think. ")])
            let second = Transcript.Reasoning(metadata: ["reasoningOrigin": "test"], segments: [text("Again.")])
            let other = Transcript.Reasoning(metadata: ["reasoningOrigin": "other"], segments: [text("Other.")])
            let entries: [Transcript.Entry] = [
                prompt(text("Hi")), .reasoning(first), .reasoning(other), .reasoning(second),
                .response(Transcript.Response(assetIDs: [], segments: [text("Hello.")])),
            ]

            let assistant = messages(try ChatCompletionsSentRequest(generationRequest(entries), model: model).body).last

            #expect(keys(assistant) == ["role", "content", "reasoning"])
            #expect(assistant?["reasoning"] == "Think. Again.")
        }

        @Test func `each answer's reasoning goes back on its own message, even when another answer had the same`() throws {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            model.exchange.reasoningMember = "reasoning"
            let reasoning = Transcript.Reasoning(metadata: ["reasoningOrigin": "test"], segments: [text("Think.")])
            let entries: [Transcript.Entry] = [
                prompt(text("One?")), .reasoning(reasoning), .response(Transcript.Response(assetIDs: [], segments: [text("One.")])),
                prompt(text("Two?")), .reasoning(reasoning), .response(Transcript.Response(assetIDs: [], segments: [text("Two.")])),
            ]

            let sent = messages(try ChatCompletionsSentRequest(generationRequest(entries), model: model).body)

            let assistants = sent.filter { $0["role"] == "assistant" }
            #expect(assistants.map { $0["content"] } == ["One.", "Two."])
            #expect(assistants.map { $0["reasoning"] } == ["Think.", "Think."])
        }

        @Test func `the exchange's members go on every answer's message and on each of its calls, whether or not reasoning goes back`()
            throws
        {
            var model = ChatCompletions.Model<ChatCompletionsTestExchange>.test()
            // A signature that goes back with the answer's own reasoning goes on its first call, and a placeholder takes its
            // place on the first call of an answer whose reasoning doesn't go back, which also gets a member of its own.
            model.exchange.answerMembers = { answer in
                let signature = answer.reasoning.first?.entry.signature.map { String(decoding: $0, as: UTF8.self) }
                return ChatCompletions.ReplayMembers(
                    message: answer.reasoning.isEmpty ? ["reasoning_content": " "] : [:],
                    toolCalls: answer.toolCalls.isEmpty ? [] : [["signature": .string(signature ?? "placeholder")]])
            }
            let own = Transcript.Reasoning(metadata: ["reasoningOrigin": "test"], segments: [], signature: Data("signed".utf8))
            let other = Transcript.Reasoning(metadata: ["reasoningOrigin": "other"], segments: [text("Other.")])
            let calls = ["call_1", "call_2", "call_3"].map { id in
                Transcript.ToolCall(id: id, toolName: "lookUp", arguments: GeneratedContent(properties: ["word": "egg"]))
            }
            let entries: [Transcript.Entry] = [
                prompt(text("Define egg.")), .reasoning(other), .toolCalls(Transcript.ToolCalls(calls.prefix(2))),
                .toolOutput(Transcript.ToolOutput(id: "call_1", toolName: "lookUp", segments: [text("egg")])),
                .toolOutput(Transcript.ToolOutput(id: "call_2", toolName: "lookUp", segments: [text("egg")])),
                .reasoning(own), .toolCalls(Transcript.ToolCalls([calls[2]])),
                .toolOutput(Transcript.ToolOutput(id: "call_3", toolName: "lookUp", segments: [text("egg")])),
                .response(Transcript.Response(assetIDs: [], segments: [text("An oval.")])),
                // An answer with nothing to send back, which a member alone doesn't send.
                prompt(text("And rice?")), .response(Transcript.Response(assetIDs: [], segments: [])),
            ]

            let assistants = messages(try ChatCompletionsSentRequest(generationRequest(entries), model: model).body)
                .filter { $0["role"] == "assistant" }

            try #require(assistants.count == 3)
            #expect(assistants[0]["reasoning_content"] == " ")
            #expect(assistants[0]["tool_calls"]?[0]?["signature"] == "placeholder")
            #expect(keys(assistants[0]["tool_calls"]?[0]) == ["id", "type", "function", "signature"])
            #expect(keys(assistants[0]["tool_calls"]?[1]) == ["id", "type", "function"])
            #expect(assistants[1]["reasoning_content"] == nil)
            #expect(assistants[1]["tool_calls"]?[0]?["signature"] == "signed")
            #expect(assistants[2] == ["role": "assistant", "content": "An oval.", "reasoning_content": " "])
        }

        @Test func `an answer with nothing to send back has no message`() throws {
            let entries: [Transcript.Entry] = [prompt(text("Hi")), .response(Transcript.Response(assetIDs: [], segments: []))]

            let sent = messages(try ChatCompletionsSentRequest(generationRequest(entries)).body)

            #expect(sent.count == 1)
        }

        @Test func `instructions take only text`() {
            let image = Transcript.ImageAttachment(imageURL: URL(fileURLWithPath: "/dev/null"))
            let entries: [Transcript.Entry] = [
                .instructions(Transcript.Instructions(segments: [.attachment(.init(content: .image(image)))], toolDefinitions: []))
            ]

            #expect(throws: LanguageModelError.self) {
                try ChatCompletionsSentRequest(generationRequest(entries))
            }
        }

        @Test func `the next request starts with the previous request's messages, byte for byte`() async throws {
            let stub = HTTPStub(
                chatCompletionsEvents(
                    toolCallChunk(0, id: "call_1", name: "lookUp", arguments: #"{"word":"egg"}"#), finishChunk("tool_calls")),
                chatCompletionsEvents(textChunk("An egg has 100 kcal.", finishReason: "stop")),
                chatCompletionsEvents(textChunk("Rice too.", finishReason: "stop")))
            let session = LanguageModelSession(model: plainModel(stub), tools: [LookUpTool()], instructions: "Answer with tools.")

            _ = try await session.respond(to: "Calories in an egg?")
            _ = try await session.respond(to: "And rice?")

            let messages = try stub.requests.map { try #require(messagesText(in: $0.body)) }
            try #require(messages.count == 3)
            for (earlier, later) in zip(messages, messages.dropFirst()) {
                #expect(later.starts(with: earlier.dropLast() + Array(",".utf8)))
            }
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
