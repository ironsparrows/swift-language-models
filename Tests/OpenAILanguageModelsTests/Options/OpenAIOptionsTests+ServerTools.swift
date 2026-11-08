import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenAILanguageModels

/// Each web and file search with its entry in a request's tools.
private let searchToolEntries: [(OpenAIServerTool, JSONValue)] = [
    (.webSearch(), ["type": "web_search"]),
    (
        .webSearch(
            searchContextSize: .high, allowedDomains: ["swift.org"],
            userLocation: OpenAIServerTool.Location(
                city: "Athens", region: "Attica", country: "GR", timeZone: TimeZone(identifier: "Europe/Athens")),
            webAccess: .cachedOnly, listsSources: true),
        [
            "type": "web_search", "filters": ["allowed_domains": ["swift.org"]], "search_context_size": "high",
            "user_location": ["type": "approximate", "city": "Athens", "region": "Attica", "country": "GR", "timezone": "Europe/Athens"],
            "external_web_access": false,
        ]
    ),
    (.webSearch(webAccess: .live), ["type": "web_search", "external_web_access": true]),
    (.fileSearch(vectorStoreIDs: ["vs_1"]), ["type": "file_search", "vector_store_ids": ["vs_1"]]),
    (
        .fileSearch(vectorStoreIDs: ["vs_1", "vs_2"], maximumResults: 5),
        ["type": "file_search", "vector_store_ids": ["vs_1", "vs_2"], "max_num_results": 5]
    ),
]

/// Each server tool with its entry in a request's tools. An image generator goes out only where its images can arrive.
private let serverToolEntries: [(OpenAIServerTool, JSONValue)] =
    imagesArrive ? searchToolEntries + imageToolEntries : searchToolEntries

/// Whether a generated image can arrive: from OS 27.2, with Xcode 27.2's SDK.
private let imagesArrive: Bool = {
    #if canImport(FoundationModels, _version: 2.1.14)
    if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) { return true }
    #endif
    return false
}()

/// Each image generator with its entry in a request's tools.
private let imageToolEntries: [(OpenAIServerTool, JSONValue)] = [
    (.imageGeneration(), ["type": "image_generation"]),
    (
        .imageGeneration(
            model: .gptImage1Mini, quality: .low, complexity: .medium, size: OpenAIImageSize(width: 1536, height: 864),
            format: .webp, compression: 80, background: .opaque, moderation: .low),
        [
            "type": "image_generation", "model": "gpt-image-1-mini", "quality": "low", "complexity": "medium", "size": "1536x864",
            "output_format": "webp", "output_compression": 80, "background": "opaque", "moderation": "low",
        ]
    ),
]

extension OpenAIOptionsTests {
    @Suite("Server tools")
    struct ServerTools {
        @Test(arguments: serverToolEntries)
        func `each server tool becomes its entry in the tools, with only the parameters that are set`(
            tool: OpenAIServerTool,
            entry: JSONValue
        ) async throws {
            let body = try await sentBody { toolModel($0, [tool]) }

            #expect(body["tools"] == [entry])
        }

        @Test func `a server tool's entry names its type first and keeps its parameters in order`() async throws {
            let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
            let tool = OpenAIServerTool.webSearch(searchContextSize: .low, allowedDomains: ["swift.org"])

            _ = try await LanguageModelSession(model: toolModel(stub, [tool])).respond(to: "Hi")

            let request = try #require(stub.requests.first)
            let tools = #""tools":[{"type":"web_search","filters":{"allowed_domains":["swift.org"]},"search_context_size":"low"}]"#
            #expect(String(decoding: request.body, as: UTF8.self).contains(tools))
        }

        @Test func `server tools follow the session's tools, in the order given`() async throws {
            let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
            let model = toolModel(stub, [.fileSearch(vectorStoreIDs: ["vs_1"]), .webSearch()])

            _ = try await LanguageModelSession(model: model, tools: [FoodTool()]).respond(to: "Hi")

            #expect(elements(try body(stub)["tools"]).map { $0["type"] } == ["function", "file_search", "web_search"])
        }

        @Test(arguments: [GenerationOptions.ToolCallingMode?.none, .allowed, .required])
        func `without the session's tools, neither a tool choice nor parallel calls go out, whatever the mode`(
            mode: GenerationOptions.ToolCallingMode?
        ) async throws {
            let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
            let model = toolModel(stub, [.webSearch()], options: OpenAIOptions(parallelToolCalls: .allowed))

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", options: GenerationOptions(toolCallingMode: mode))

            let body = try body(stub)
            #expect(elements(body["tools"]).map { $0["type"] } == ["web_search"])
            #expect(body["tool_choice"] == nil)
            #expect(body["parallel_tool_calls"] == nil)
        }

        @Test func `when tool calls are disallowed, server tools stay out too, with what they'd add and their limit`() async throws {
            let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
            let model = toolModel(stub, [.webSearch(listsSources: true)], options: OpenAIOptions(maximumServerToolCalls: 2))
            let session = LanguageModelSession(model: model, tools: [FoodTool()])

            _ = try await session.respond(to: "Hi", options: GenerationOptions(toolCallingMode: .disallowed))

            let body = try body(stub)
            #expect(body["tools"] == nil)
            #expect(body["include"] == ["reasoning.encrypted_content"])
            #expect(body["max_tool_calls"] == nil)
        }

        @Test func `a web search that lists its sources asks for them after the encrypted reasoning`() async throws {
            let reasoning = try await sentBody { toolModel($0, [.webSearch(listsSources: true), .fileSearch(vectorStoreIDs: ["vs_1"])]) }
            let plain = try await sentBody { stub -> OpenAILanguageModel<Efforts.Unsupported> in
                model(
                    stub, details(id: "gpt-plain", parameters: plainParameters, reasoning: .unsupported),
                    serverTools: [.webSearch(listsSources: true)])
            }

            #expect(reasoning["include"] == ["reasoning.encrypted_content", "web_search_call.action.sources"])
            #expect(plain["include"] == ["web_search_call.action.sources"])
        }

        @Test func `two web searches that list their sources ask for them once`() async throws {
            let body = try await sentBody {
                toolModel($0, [.webSearch(listsSources: true), .webSearch(allowedDomains: ["swift.org"], listsSources: true)])
            }

            #expect(body["include"] == ["reasoning.encrypted_content", "web_search_call.action.sources"])
        }

        @Test func `the most server tool calls go as max_tool_calls`() async throws {
            let body = try await sentBody { toolModel($0, [.webSearch()], options: OpenAIOptions(maximumServerToolCalls: 2)) }

            #expect(body["max_tool_calls"] == 2)
        }

        @Test func `server tools are refused before any request when the model doesn't take tools`() async throws {
            let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
            let languageModel = model(
                stub, details(parameters: reasoningParameters.subtracting([.tools]), efforts: [Efforts.Unsupported]()),
                serverTools: [.webSearch()])

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: languageModel).respond(to: "Hi")
            }

            guard case .unsupportedCapability(let unsupported) = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(unsupported.capability == .toolCalling)
            #expect(stub.requests.isEmpty)
        }

        @Test func `a model without tools still answers when tool calls are disallowed, since no server tool goes out`() async throws {
            let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))
            let languageModel = model(
                stub, details(parameters: reasoningParameters.subtracting([.tools]), efforts: [Efforts.Unsupported]()),
                serverTools: [.webSearch()])

            let response = try await LanguageModelSession(model: languageModel).respond(
                to: "Hi", options: GenerationOptions(toolCallingMode: .disallowed))

            #expect(response.content == "Hi.")
            #expect(try body(stub)["tools"] == nil)
        }

        @Test func `the public initializer keeps the server tools, and so does the open form`() {
            let model = OpenAILanguageModel(.gpt6Luna, serverTools: [.webSearch(), .imageGeneration()], auth: .apiKey { "sk-test" })

            #expect(model.serverTools == [.webSearch(), .imageGeneration()])
            #expect(OpenAILanguageModel(model).serverTools == model.serverTools)
        }

        @Test func `server tools that a request sends the same way are equal`() {
            #expect(OpenAIServerTool.webSearch(listsSources: false) == .webSearch())
            #expect(OpenAIServerTool.webSearch(listsSources: true) != .webSearch())
            #expect(OpenAIServerTool.imageGeneration(format: .png) != .imageGeneration())
        }

        #if canImport(FoundationModels, _version: 2.1.14)
        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `the model generates images of its image tool's format, and nothing without one`() async throws {
            let auth = OpenAIAuthentication.apiKey { "sk-test" }
            let plain = OpenAILanguageModel(.gpt6Luna, auth: auth)
            let png = OpenAILanguageModel(.gpt6Luna, serverTools: [.webSearch(), .imageGeneration()], auth: auth)
            let webp = OpenAILanguageModel(.gpt6Luna, serverTools: [.imageGeneration(format: .webp)], auth: auth)

            #expect(try await plain.supportsDataEntryType(.png) == false)
            #expect(try await png.supportsDataEntryType(.png))
            #expect(try await png.supportsDataEntryType(.jpeg) == false)
            #expect(try await webp.supportsDataEntryType(.webP))
            #expect(try await webp.supportsDataEntryType(.png) == false)
        }
        #endif

        @Test(.disabled(if: imagesArrive, "Images can arrive here: OS 27.2, with Xcode 27.2's SDK"))
        func `image generation is refused before any request where no image could arrive`() async throws {
            let stub = HTTPStub(responseStream([created()], [textDelta("Hi."), completed()]))

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: toolModel(stub, [.imageGeneration()])).respond(to: "Hi")
            }

            guard case .unsupportedCapability(let unsupported) = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(unsupported.capability == .toolCalling)
            #expect(stub.requests.isEmpty)
        }
    }
}

/// A model that reasons, with these server tools, served by a stub.
private func toolModel(
    _ stub: HTTPStub,
    _ serverTools: [OpenAIServerTool],
    options: OpenAIOptions = OpenAIOptions()
) -> OpenAILanguageModel<ContextOptions.ReasoningLevel> {
    model(stub, details(efforts: [.max, .xhigh, .high, .medium, .low, .off]), serverTools: serverTools, options: options)
}

/// The elements of a list.
private func elements(_ value: JSONValue?) -> [JSONValue] {
    if case .array(let elements)? = value { elements } else { [] }
}
