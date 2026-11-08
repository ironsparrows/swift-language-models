import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing

@testable import LanguageModels

extension ChatCompletionsModelTests {
    /// A stream however the network cuts it: in two at every byte, and a byte at a time.
    @Suite("Split points")
    struct SplitPoints {
        @Test(arguments: StreamFixture.allCases.flatMap { fixture in (1..<fixture.bytes.count).map { (fixture, $0) } })
        func `a stream cut in two at any byte reads as it does whole`(fixture: StreamFixture, offset: Int) async throws {
            try await fixture.expectAnswer(delivered: [fixture.bytes.prefix(offset), fixture.bytes.dropFirst(offset)])
        }

        @Test(arguments: StreamFixture.allCases)
        func `a stream delivered a byte at a time reads as it does whole`(fixture: StreamFixture) async throws {
            try await fixture.expectAnswer(delivered: fixture.bytes.map { Data([$0]) })
        }
    }
}

/// A stream whose answer must not depend on where its bytes are cut.
enum StreamFixture: CaseIterable {
    /// Text with a two-byte and a four-byte character, and U+2028, which JSON may carry unescaped.
    case text

    /// A tool call whose arguments arrive in two fragments.
    case toolCall

    /// A reasoning block at the start of the answer's text, then the answer, with each tag cut across events.
    case taggedReasoning

    /// Text whose lines end in a carriage return and a line feed.
    case carriageReturns

    private static let wideText = "café 😀\u{2028}!"

    var bytes: Data {
        let events: [String] =
            switch self {
            case .text:
                [#"{"choices":[{"delta":{"content":"\#(Self.wideText)"},"finish_reason":"stop"}]}"#, "[DONE]"]
            case .toolCall:
                [
                    #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"lookUp","arguments":"{\"wo"}}]}}]}"#,
                    #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"rd\":\"egg\"}"}}]},"finish_reason":"tool_calls"}]}"#,
                    "[DONE]",
                ]
            case .taggedReasoning:
                [
                    #"{"choices":[{"delta":{"content":"<thi"}}]}"#, #"{"choices":[{"delta":{"content":"nk>Pl"}}]}"#,
                    #"{"choices":[{"delta":{"content":"an.</th"}}]}"#, #"{"choices":[{"delta":{"content":"ink>Hel"}}]}"#,
                    #"{"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}"#, "[DONE]",
                ]
            case .carriageReturns:
                [#"{"choices":[{"delta":{"content":"Hello"},"finish_reason":"stop"}]}"#, "[DONE]"]
            }
        let lineEnd = self == .carriageReturns ? "\r\n" : "\n"
        return Data(events.map { "data: \($0)\(lineEnd)\(lineEnd)" }.joined().utf8)
    }

    /// Runs the stream through a session, delivered in the given pieces, and checks what it ends as.
    func expectAnswer(delivered pieces: [Data]) async throws {
        let stream = StubResponse(headers: ["Content-Type": "text/event-stream"], chunks: pieces)
        let stub = HTTPStub(stream, chatCompletionsEvents(["choices": [["delta": ["content": "Done"], "finish_reason": "stop"]]]))
        let model = ChatCompletionsModelTests.plainModel(stub)

        let response = try await LanguageModelSession(model: model, tools: [LookUpTool()]).respond(to: "Hello")

        switch self {
        case .text:
            #expect(response.content == Self.wideText)
        case .toolCall:
            #expect(response.content == "Done")
            let followUp = try JSONValue(json: try #require(stub.requests.last).body)
            let call = try #require(messages(followUp).first { $0["tool_calls"] != nil })
            #expect(call["tool_calls"]?[0]?["function"]?["arguments"] == #"{"word":"egg"}"#)
        case .taggedReasoning:
            #expect(response.content == "Hello")
            let reasoning = response.transcriptEntries.compactMap { entry -> [Transcript.Segment]? in
                guard case .reasoning(let reasoning) = entry else { return nil }
                return Array(reasoning.segments)
            }
            #expect(reasoning.count == 1)
            guard case .text(let plan)? = reasoning.first?.first else {
                Issue.record("The reasoning is \(reasoning)")
                return
            }
            #expect(plan.content == "Plan.")
        case .carriageReturns:
            #expect(response.content == "Hello")
        }
    }
}
