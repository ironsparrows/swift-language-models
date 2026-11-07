import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// A `url_citation` annotation as OpenRouter streams it.
private func citation(
    _ url: String?,
    title: String? = nil,
    content: String? = nil,
    start: Int? = nil,
    end: Int? = nil
) -> JSONValue {
    let fields: JSONValue = [
        "url": url.map(JSONValue.string), "title": title.map(JSONValue.string), "content": content.map(JSONValue.string),
        "start_index": start.map(JSONValue.integer), "end_index": end.map(JSONValue.integer),
    ]
    return ["type": "url_citation", "url_citation": fields]
}

/// A chunk of annotations.
private func annotations(_ annotations: JSONValue...) -> JSONValue {
    chunk(["annotations": .array(annotations)])
}

/// The response entries of a transcript.
private func responses(_ entries: some Sequence<Transcript.Entry>) -> [Transcript.Response] {
    entries.compactMap { entry in
        if case .response(let response) = entry { response } else { nil }
    }
}

/// Each server tool with its entry in a request's tools.
private let serverToolEntries: [(OpenRouterServerTool, JSONValue)] = [
    (.webSearch(), ["type": "openrouter:web_search"]),
    (
        .webSearch(
            engine: .exa, mode: .deepLite, maximumResults: 3, maximumTotalResults: 9, maximumSearches: 2, searchContextSize: .high,
            allowedDomains: ["arxiv.org"], excludedDomains: ["reddit.com"]),
        [
            "type": "openrouter:web_search",
            "parameters": [
                "engine": "exa", "mode": "deep-lite", "max_results": 3, "max_total_results": 9, "max_uses": 2,
                "search_context_size": "high", "allowed_domains": ["arxiv.org"], "excluded_domains": ["reddit.com"],
            ],
        ]
    ),
    (.webSearch(allowedDomains: []), ["type": "openrouter:web_search", "parameters": ["allowed_domains": []]]),
    (.webFetch(), ["type": "openrouter:web_fetch"]),
    (
        .webFetch(
            engine: .openRouter, maximumFetches: 4, maximumContentTokens: 50_000, allowedDomains: ["docs.example.com"],
            excludedDomains: ["internal.example.com"]),
        [
            "type": "openrouter:web_fetch",
            "parameters": [
                "engine": "openrouter", "max_uses": 4, "max_content_tokens": 50_000, "allowed_domains": ["docs.example.com"],
                "blocked_domains": ["internal.example.com"],
            ],
        ]
    ),
    (.datetime(), ["type": "openrouter:datetime"]),
    (
        .datetime(timeZone: TimeZone(identifier: "America/New_York")),
        ["type": "openrouter:datetime", "parameters": ["timezone": "America/New_York"]]
    ),
    (.advisor(), ["type": "openrouter:advisor"]),
    (
        .advisor(
            model: "~anthropic/claude-opus-latest", name: "reviewer", instructions: "Find the flaws.", forwardsTranscript: true,
            maximumResponseTokens: 2_048, reasoningLevel: .deep, maximumReasoningTokens: 1_024, temperature: 0.5),
        [
            "type": "openrouter:advisor",
            "parameters": [
                "name": "reviewer", "model": "~anthropic/claude-opus-latest", "instructions": "Find the flaws.",
                "max_completion_tokens": 2_048, "reasoning": ["effort": "high", "max_tokens": 1_024], "temperature": 0.5,
                "forward_transcript": true,
            ],
        ]
    ),
    (.advisor(reasoningLevel: .xhigh), ["type": "openrouter:advisor", "parameters": ["reasoning": ["effort": "xhigh"]]]),
    (.advisor(reasoningLevel: .custom("extreme")), ["type": "openrouter:advisor"]),
    (.subagent(), ["type": "openrouter:subagent"]),
    (
        .subagent(
            model: "~anthropic/claude-haiku-latest", name: "summarizer", instructions: "Be brief.",
            tools: [.webSearch(maximumResults: 3), .datetime()], maximumToolCalls: 5, maximumResponseTokens: 512, reasoningLevel: .off,
            maximumReasoningTokens: 256, temperature: 0.2),
        [
            "type": "openrouter:subagent",
            "parameters": [
                "name": "summarizer", "model": "~anthropic/claude-haiku-latest", "instructions": "Be brief.",
                "max_completion_tokens": 512, "reasoning": ["effort": "none", "max_tokens": 256], "temperature": 0.2,
                "tools": [["type": "openrouter:web_search", "parameters": ["max_results": 3]], ["type": "openrouter:datetime"]],
                "max_tool_calls": 5,
            ],
        ]
    ),
]

extension OpenRouterOptionsTests {
    @Suite("Server tools")
    struct ServerTools {
        @Test(arguments: serverToolEntries)
        func `each server tool becomes its entry in the tools, with only the parameters that are set`(
            tool: OpenRouterServerTool,
            entry: JSONValue
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            _ = try await LanguageModelSession(model: model(stub, serverTools: [tool])).respond(to: "Hi")

            #expect(elements(try body(stub)["tools"]) == [entry])
        }

        @Test func `a server tool's entry names its type first and keeps its parameters in order`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let tool = OpenRouterServerTool.webSearch(engine: .parallel, mode: .turbo, maximumResults: 5, searchContextSize: .low)

            _ = try await LanguageModelSession(model: model(stub, serverTools: [tool])).respond(to: "Hi")

            let request = try #require(stub.requests.first)
            let tools =
                #""tools":[{"type":"openrouter:web_search","parameters":{"engine":"parallel","mode":"turbo","max_results":5,"#
                + #""search_context_size":"low"}}]"#
            #expect(String(decoding: request.body, as: UTF8.self).contains(tools))
        }

        @Test func `server tools follow the session's tools, in the order given`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, serverTools: [.datetime(), .webSearch()])

            _ = try await LanguageModelSession(model: model, tools: [FoodTool()]).respond(to: "Hi")

            let tools = elements(try body(stub)["tools"])
            #expect(tools.map { $0["type"] } == ["function", "openrouter:datetime", "openrouter:web_search"])
            #expect(tools.first?["function"]?["name"] == "lookUpFood")
        }

        @Test(arguments: [GenerationOptions.ToolCallingMode?.none, .allowed, .required])
        func `without the session's tools, no tool choice or parallel calls go out, whatever the mode`(
            mode: GenerationOptions.ToolCallingMode?
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, parameters: chatParameters.union([.parallelToolCalls]), serverTools: [.webSearch()])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", options: GenerationOptions(toolCallingMode: mode))

            let body = try body(stub)
            #expect(elements(body["tools"]).map { $0["type"] } == ["openrouter:web_search"])
            #expect(body["tool_choice"] == nil)
            #expect(body["parallel_tool_calls"] == nil)
        }

        @Test(arguments: [(GenerationOptions.ToolCallingMode.allowed, JSONValue.string("auto")), (.required, "required")])
        func `with the session's tools, the tool choice is theirs, next to the server tools`(
            mode: GenerationOptions.ToolCallingMode,
            choice: JSONValue
        ) async throws {
            let stub = HTTPStub(
                events(toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#), done("tool_calls")),
                events(text("An egg has 100 kcal."), done())
            )
            let model = model(stub, parameters: chatParameters.union([.parallelToolCalls]), serverTools: [.webSearch()])
            let session = LanguageModelSession(model: model, tools: [FoodTool()])

            _ = try await session.respond(to: "Calories in an egg?", options: GenerationOptions(toolCallingMode: mode))

            for index in 0..<2 {
                let body = try body(stub, index)
                #expect(elements(body["tools"]).map { $0["type"] } == ["function", "openrouter:web_search"])
                #expect(body["tool_choice"] == choice)
                #expect(body["parallel_tool_calls"] == nil)
            }
        }

        @Test func `when tool calls are disallowed, server tools stay out too`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let session = LanguageModelSession(model: model(stub, serverTools: [.webSearch(), .datetime()]), tools: [FoodTool()])

            _ = try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: .disallowed))

            let body = try body(stub)
            #expect(body["tools"] == nil)
            #expect(body["tool_choice"] == nil)
            #expect(body["provider"] == nil)
        }

        @Test(arguments: [(OpenRouterRouting.Requirement.automatic, JSONValue.bool(true)), (.notRequired, false)])
        func `server tools alone ask for hosts that take every parameter, unless the routing says otherwise`(
            parameterSupport: OpenRouterRouting.Requirement,
            required: JSONValue
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let routing = OpenRouterRouting(parameterSupport: parameterSupport)

            _ = try await LanguageModelSession(model: model(stub, serverTools: [.datetime()], routing: routing)).respond(to: "Hi")

            #expect(try body(stub)["provider"]?["require_parameters"] == required)
        }

        @Test(arguments: [
            (chatParameters.subtracting([.tools]), chatParameters),
            (chatParameters, chatParameters.subtracting([.tools])),
        ])
        func `server tools are refused before any request when the model or a fallback doesn't take tools`(
            parameters: Set<OpenRouterParameter>,
            fallbackParameters: Set<OpenRouterParameter>
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(
                stub, parameters: parameters, fallbacks: [fallback(parameters: fallbackParameters)], serverTools: [.webSearch()])

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model).respond(to: "Hi")
            }

            guard case .unsupportedCapability(let unsupported) = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(unsupported.capability == .toolCalling)
            #expect(stub.requests.isEmpty)
        }

        @Test func `a model without tools still answers when tool calls are disallowed, since no server tool goes out`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, parameters: chatParameters.subtracting([.tools]), serverTools: [.webSearch()])

            let response = try await LanguageModelSession(model: model).respond(
                to: "Hi", options: GenerationOptions(toolCallingMode: .disallowed))

            #expect(response.content == "Hi")
            #expect(try body(stub)["tools"] == nil)
        }

        @Test func `the public initializer keeps the server tools, and so does the open form`() {
            let model = OpenRouterLanguageModel(
                fallback("openai/gpt-5-mini"), serverTools: [.webSearch(engine: .exa), .datetime()], auth: .apiKey { "sk-or-test" })

            #expect(model.serverTools == [.webSearch(engine: .exa), .datetime()])
            #expect(OpenRouterLanguageModel(model).serverTools == model.serverTools)
        }

        @Test func `cited pages become the response entry's citations, once each, and don't go back to OpenRouter`() async throws {
            let full = citation(
                "https://swift.org/blog/swift-6.4", title: "Swift 6.4 Released", content: "Swift 6.4 is now available.\n[...]\nMore.",
                start: 0, end: 18)
            let stub = HTTPStub(
                events(
                    text("Swift 6.4 is out. "),
                    annotations(full, ["type": "file", "file": ["hash": "abc", "name": "notes.pdf"]]),
                    text("It ships with Xcode 27.2."),
                    annotations(full, citation("https://developer.apple.com/xcode/"), citation(nil, title: "No address")),
                    done()
                ),
                events(text("Yes."), done())
            )
            let session = LanguageModelSession(model: model(stub, serverTools: [.webSearch()]))

            let response = try await session.respond(to: "What's new in Swift?")
            _ = try await session.respond(to: "Sure?")

            let answer = try #require(responses(response.transcriptEntries).last)
            #expect(
                answer.openRouter.citations == [
                    Citation(
                        url: try #require(URL(string: "https://swift.org/blog/swift-6.4")), title: "Swift 6.4 Released",
                        excerpt: "Swift 6.4 is now available.\n[...]\nMore.", startOffset: 0, endOffset: 18),
                    Citation(
                        url: try #require(URL(string: "https://developer.apple.com/xcode/")), title: nil, excerpt: nil, startOffset: nil,
                        endOffset: nil),
                ]
            )
            guard case .array(let stored)? = answer.metadata[LanguageModelMetadataKey.citations]?.kind else {
                Issue.record("The citations aren't a list in the metadata.")
                return
            }
            #expect(stored.count == 2)
            #expect(metadataString(answer.metadata, LanguageModelMetadataKey.model) == "vendor/model")
            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant == ["content": "Swift 6.4 is out. It ships with Xcode 27.2.", "role": "assistant"])
        }

        @Test func `citations stay on the response entry when the answer ends in tool calls`() async throws {
            let stub = HTTPStub(
                events(
                    text("Eggs are light, says the USDA. "),
                    annotations(citation("https://fdc.nal.usda.gov/", title: "FoodData Central")),
                    toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food":"egg"}"#),
                    done("tool_calls")
                ),
                events(text("An egg has 100 kcal."), done())
            )
            let session = LanguageModelSession(model: model(stub, serverTools: [.webSearch()]), tools: [FoodTool()])

            let response = try await session.respond(to: "Calories in an egg?")

            let answers = responses(response.transcriptEntries)
            try #require(answers.count == 2)
            #expect(answers[0].openRouter.citations.map(\.title) == ["FoodData Central"])
            #expect(answers[1].openRouter.citations.isEmpty)
        }

        @Test(arguments: [OpenRouterServerTool.advisor(model: "openai/gpt-4.1-nano"), .subagent(model: "openai/gpt-4.1-nano")])
        func `a call to another model reaches the session only as the answer and its count, with nothing to send back`(
            tool: OpenRouterServerTool
        ) async throws {
            // On chat completions, OpenRouter streams only the answer the other model informed, and counts the call.
            let usage: JSONValue = [
                "prompt_tokens": 490, "completion_tokens": 40, "total_tokens": 530, "cost": 0.000_09,
                "server_tool_use_details": ["tool_calls_requested": 1, "tool_calls_executed": 1],
            ]
            let stub = HTTPStub(
                events(text("17 × 23 is indeed 391."), chunk([:], finishReason: "stop", usage: usage)),
                events(text("Yes."), done())
            )
            let session = LanguageModelSession(model: model(stub, serverTools: [tool]))

            let first = try await session.respond(to: "Is 17 × 23 391?")
            _ = try await session.respond(to: "Sure?")

            #expect(first.content == "17 × 23 is indeed 391.")
            #expect(metadataNumber(first.usage.metadata, OpenRouterMetadataKey.requestedServerToolCallCount) == 1)
            #expect(metadataNumber(first.usage.metadata, OpenRouterMetadataKey.executedServerToolCallCount) == 1)
            #expect(!session.transcript.contains { if case .toolCalls = $0 { true } else { false } })
            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant == ["content": "17 × 23 is indeed 391.", "role": "assistant"])
            #expect(!messages(try body(stub, 1)).contains { $0["role"] == "tool" })
        }

        @Test func `equal server tools are equal and hash alike, and a reasoning level tells two apart`() {
            let advisor = OpenRouterServerTool.advisor(model: "openai/gpt-5-mini", reasoningLevel: .deep)

            #expect(advisor == .advisor(model: "openai/gpt-5-mini", reasoningLevel: .deep))
            #expect(advisor.hashValue == OpenRouterServerTool.advisor(model: "openai/gpt-5-mini", reasoningLevel: .deep).hashValue)
            #expect(advisor != .advisor(model: "openai/gpt-5-mini", reasoningLevel: .light))
            #expect(Set([advisor, advisor, .datetime()]).count == 2)
        }

        @Test(arguments: [
            (OpenRouterServerTool.webSearch(maximumResults: 3), OpenRouterServerTool.webSearch(maximumResults: 4)),
            (.webSearch(allowedDomains: ["arxiv.org"]), .webSearch(excludedDomains: ["arxiv.org"])),
            (.webFetch(engine: .exa), .webFetch(engine: .openRouter)),
            (.datetime(), .datetime(timeZone: .gmt)),
            (.advisor(name: "reviewer"), .advisor(name: "critic")),
            (.subagent(tools: [.webSearch()]), .subagent(tools: [.webSearch(maximumResults: 3)])),
            (.webSearch(), .webFetch()),
        ])
        func `any parameter a request sends tells two server tools apart, in equality and in a set`(
            tool: OpenRouterServerTool,
            other: OpenRouterServerTool
        ) {
            #expect(tool != other)
            #expect(Set([tool, other, tool]).count == 2)
        }

        @Test func `server tools that a request sends the same way are equal`() {
            let unlisted = OpenRouterServerTool.advisor(reasoningLevel: .custom("extreme"))

            #expect(unlisted == .advisor())
            #expect(unlisted.hashValue == OpenRouterServerTool.advisor().hashValue)
        }

        @Test func `a server tool's call reaches the session only as reasoning details, which go back on the next turn`() async throws {
            let record: JSONValue = [
                "type": "reasoning.server_tool_call", "tool_name": "openrouter:web_search", "tool_call_id": "call_srv_1",
                "arguments": #"{"query":"Swift 6.4"}"#, "result": #"{"status":"ok"}"#,
            ]
            let stub = HTTPStub(events(reasoning(record), text("Swift 6.4 is out."), done()), events(text("Yes."), done()))
            let session = LanguageModelSession(model: model(stub, serverTools: [.webSearch()]))

            let first = try await session.respond(to: "What's new in Swift?")
            _ = try await session.respond(to: "Sure?")

            #expect(first.content == "Swift 6.4 is out.")
            #expect(!first.transcriptEntries.contains { if case .toolCalls = $0 { true } else { false } })
            let messages = messages(try body(stub, 1))
            #expect(!messages.contains { $0["role"] == "tool" })
            let assistant = try #require(messages.first { $0["role"] == "assistant" })
            #expect(assistant["reasoning_details"] == [record])
            #expect(assistant["tool_calls"] == nil)
            #expect(assistant["content"] == "Swift 6.4 is out.")
        }
    }
}
