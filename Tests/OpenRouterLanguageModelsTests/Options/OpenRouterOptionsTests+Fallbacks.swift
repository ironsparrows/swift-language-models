import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenRouterLanguageModels

/// A signed reasoning detail, which a provider checks when it comes back.
private let signedDetail: JSONValue = [
    "type": "reasoning.text", "text": "Eggs are light.", "signature": "sig-1", "format": "anthropic-claude-v1",
]

extension OpenRouterOptionsTests {
    @Suite("Fallbacks")
    struct Fallbacks {
        @Test(arguments: [
            ([OpenRouterModelID](), JSONValue?.none),
            (["vendor/fallback"] as [OpenRouterModelID], JSONValue?.some(["vendor/fallback"])),
            (["vendor/fallback", "other/model:free"] as [OpenRouterModelID], JSONValue?.some(["vendor/fallback", "other/model:free"])),
        ])
        func `the request names the model, then lists its fallbacks in order`(ids: [OpenRouterModelID], models: JSONValue?) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            _ = try await LanguageModelSession(model: model(stub, fallbacks: ids.map { fallback($0) })).respond(to: "Hi")

            let body = try body(stub)
            #expect(body["model"] == "vendor/model")
            #expect(body["models"] == models)
        }

        @Test func `catalog models of any effort type follow the model, in their open form`() {
            let model = OpenRouterLanguageModel(
                .anthropicClaudeSonnet4_6, fallbacks: .openaiGpt5Nano, .googleGemini3_1FlashLite, auth: .apiKey { "sk-or-test" })

            #expect(model.fallbacks.map(\.id) == ["openai/gpt-5-nano", "google/gemini-3.1-flash-lite"])
            #expect(model.fallbacks.first == OpenRouterModel(.openaiGpt5Nano))
            #expect(OpenRouterLanguageModel(model).fallbacks == model.fallbacks)
            #expect(Set(model.fallbacks).count == 2)
        }

        @Test(arguments: [
            (OpenRouterRouting.Variant.nitro, JSONValue.array(["vendor/fallback:nitro", "other/model:free:nitro"])),
            (.floor, JSONValue.array(["vendor/fallback:floor", "other/model:free:floor"])),
        ])
        func `a variant suffixes the model and every fallback`(variant: OpenRouterRouting.Variant, models: JSONValue) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, fallbacks: [fallback(), fallback("other/model:free")], routing: OpenRouterRouting(variant: variant))

            _ = try await LanguageModelSession(model: model).respond(to: "Hi")

            let body = try body(stub)
            #expect(body["model"] == .string("vendor/model:\(variant.rawValue)"))
            #expect(body["models"] == models)
        }

        @Test(arguments: [
            (chatParameters.union([.frequencyPenalty, .verbosity]), JSONValue?.some(0.5), JSONValue?.some("high")),
            (chatParameters.union([.verbosity]), nil, "high"),
            (chatParameters, nil, nil),
        ])
        func `a setting is sent only when every model lists its parameter`(
            fallbackParameters: Set<OpenRouterParameter>,
            frequencyPenalty: JSONValue?,
            verbosity: JSONValue?
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let options = OpenRouterOptions(frequencyPenalty: 0.5, verbosity: .high)
            let parameters = chatParameters.union([.frequencyPenalty, .verbosity])
            let model = model(stub, parameters: parameters, fallbacks: [fallback(parameters: fallbackParameters)], options: options)

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", options: GenerationOptions(temperature: 0.5))

            let body = try body(stub)
            #expect(body["frequency_penalty"] == frequencyPenalty)
            #expect(body["verbosity"] == verbosity)
            #expect(body["temperature"] == 0.5)
        }

        @Test func `the token limit goes out as asked`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, fallbacks: [fallback(), fallback("other/model")])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", options: GenerationOptions(maximumResponseTokens: 100_000))

            #expect(try body(stub)["max_tokens"] == 100_000)
        }

        @Test(arguments: [(true, true, true), (true, false, false), (false, true, false)])
        func `the shared details cache only marked prompts only when the model and every fallback do`(
            modelCaches: Bool,
            fallbackCaches: Bool,
            sharedCaches: Bool
        ) {
            let fallbacks = [fallback(cachesOnlyMarkedPrompts: true), fallback("other/model", cachesOnlyMarkedPrompts: fallbackCaches)]

            let model = model(HTTPStub(), cachesOnlyMarkedPrompts: modelCaches, fallbacks: fallbacks)

            #expect(model.sharedDetails.cachesOnlyMarkedPrompts == sharedCaches)
        }

        @Test func `a schema goes as structured outputs when every model takes them`() async throws {
            let stub = HTTPStub(events(text(#"{"name":"Soup"}"#), done()))
            let model = model(stub, fallbacks: [fallback(parameters: chatParameters)])

            _ = try await LanguageModelSession(model: model).respond(to: "A dinner idea.", generating: Dish.self)

            #expect(try body(stub)["response_format"]?["type"] == "json_schema")
        }

        @Test(arguments: [Set<OpenRouterParameter>([.tools, .maxTokens]), chatParameters.subtracting([.structuredOutputs])])
        func `a schema is refused before any request when a fallback doesn't take structured outputs`(
            fallbackParameters: Set<OpenRouterParameter>
        ) async throws {
            let stub = HTTPStub(events(text(#"{"name":"Soup"}"#), done()))
            let model = model(stub, fallbacks: [fallback(parameters: fallbackParameters)])

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model).respond(to: "A dinner idea.", generating: Dish.self)
            }

            guard case .unsupportedCapability = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(stub.requests.isEmpty)
        }

        @Test(arguments: [
            (OpenRouterModelID("anthropic/claude-haiku-5.5"), true),
            ("~anthropic/claude-haiku-latest", true),
            ("google/gemini-3.1-flash-lite", false),
        ])
        func `a schema is written for Anthropic when a fallback is Anthropic's`(id: OpenRouterModelID, isRewritten: Bool) async throws {
            let stub = HTTPStub(events(text(#"{"name":"Soup","servings":2}"#), done()))
            let model = model(stub, id: "openai/gpt-5", fallbacks: [fallback(id)])

            _ = try await LanguageModelSession(model: model).respond(to: "A dinner idea.", generating: Serving.self)

            let servings = try #require(try body(stub)["response_format"]?["json_schema"]?["schema"]?["properties"]?["servings"])
            #expect(servings["maximum"] == (isRewritten ? nil : 12))
            #expect(servings["description"] == (isRewritten ? "{maximum: 12, minimum: 1}" : nil))
        }

        @Test func `tools are refused before any request when a fallback doesn't take them`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, fallbacks: [fallback(), fallback("other/model", parameters: chatParameters.subtracting([.tools]))])

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model, tools: [FoodTool()]).respond(to: "Hi")
            }

            guard case .unsupportedCapability = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(stub.requests.isEmpty)
            #expect(!model.capabilities.contains(.toolCalling))
        }

        @Test(arguments: [
            ([ContextOptions.ReasoningLevel.medium, .low], ContextOptions.ReasoningLevel.deep, JSONValue?.some(["effort": "medium"])),
            ([.high, .medium, .low], .custom("max"), JSONValue?.some(["effort": "high"])),
            ([], .deep, JSONValue?.some(["enabled": true])),
            ([], .off, JSONValue?.some(["enabled": false])),
            ([.xhigh], .light, JSONValue?.some(["enabled": true])),
        ])
        func `a reasoning level becomes the nearest effort every model accepts, or just turns reasoning on or off`(
            efforts: [ContextOptions.ReasoningLevel],
            level: ContextOptions.ReasoningLevel,
            reasoning: JSONValue?
        ) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model: OpenRouterLanguageModel<HighMediumLow> = model(
                stub, efforts: [.high, .medium, .low], fallbacks: [fallback(efforts: efforts)])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: level))

            #expect(try body(stub)["reasoning"] == reasoning)
        }

        @Test func `reasoning isn't turned off when a fallback always reasons`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, fallbacks: [fallback(reasoning: .mandatory)])

            _ = try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: .off))

            #expect(try body(stub)["reasoning"] == nil)
        }

        @Test func `a reasoning level is refused before any request when a fallback doesn't reason`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let model = model(stub, fallbacks: [fallback(reasoning: .unsupported)])

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model).respond(to: "Hi", contextOptions: ContextOptions(reasoningLevel: .deep))
            }

            guard case .unsupportedCapability = error else {
                Issue.record("Expected an unsupported capability, got \(error)")
                return
            }
            #expect(stub.requests.isEmpty)
            #expect(!model.capabilities.contains(.reasoning))
        }

        #if canImport(FoundationModels, _version: 2.1.14)
        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `attachments, vision and data kinds are those every model takes, while the details stay the model's`() async throws {
            var model = OpenRouterLanguageModel(.anthropicClaudeSonnet4_6, auth: .apiKey { "sk-or-test" })
            #expect(try await model.supportsDataAttachmentType(.pdf))

            model.fallbacks = [fallback(inputs: [.text, .image])]

            #expect(model.capabilities.contains(.vision))
            #expect(try await model.supportsDataAttachmentType(.png))
            #expect(try await model.supportsDataAttachmentType(.pdf))
            #expect(try await !model.supportsDataEntryType(.png))

            model.options.pdfEngine = .native

            #expect(try await !model.supportsDataAttachmentType(.pdf))
            #expect(model.details.dataAttachmentTypes.contains(.pdf))

            model.fallbacks.append(fallback("other/model", inputs: [.text]))

            #expect(!model.capabilities.contains(.vision))
            #expect(try await !model.supportsDataAttachmentType(.png))
        }
        #endif

        @Test func `a context too long for the models is reported with the smallest context size`() async throws {
            let streamError: JSONValue = ["error": ["code": 400, "message": "Input exceeds the context window."]]
            let stub = HTTPStub(events(text("Hi"), streamError))
            let model = model(stub, fallbacks: [fallback(contextSize: 32_000), fallback("other/model", contextSize: 128_000)])

            let error = try await #require(throws: LanguageModelError.self) {
                try await LanguageModelSession(model: model).respond(to: "Hi")
            }

            guard case .contextSizeExceeded(let info) = error else {
                Issue.record("Expected an oversized context, got \(error)")
                return
            }
            #expect(info.contextSize == 32_000)
        }

        @Test func `a router among the fallbacks gets its settings`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let options = OpenRouterOptions(autoRouter: OpenRouterOptions.AutoRouter(allowedModels: ["anthropic/*"]))
            let model = model(stub, fallbacks: [fallback("openrouter/auto"), fallback("openrouter/auto")], options: options)

            _ = try await LanguageModelSession(model: model).respond(to: "Hi")

            #expect(
                try body(stub)["plugins"] == [
                    ["id": "context-compression", "enabled": false], ["id": "auto-router", "allowed_models": ["anthropic/*"]],
                ])
        }

        @Test(arguments: [
            (OpenRouterModelID("vendor/fallback"), "vendor/model", true),
            ("vendor/fallback", "vendor/model-2026-10-01", true),
            ("vendor/fallback", "elsewhere/routed-model", true),
            ("vendor/fallback", "vendor/fallback", false),
            ("vendor/fallback", "vendor/fallback-2026-10-01", false),
            ("vendor/fallback:free", "vendor/fallback", false),
            ("vendor/model-mini", "vendor/model-mini-2026-10-01", false),
        ])
        func `reasoning goes back on later turns only when the model, not a fallback, wrote it`(
            fallbackID: OpenRouterModelID,
            answeringModel: String,
            isReplayed: Bool
        ) async throws {
            let stub = HTTPStub(
                events(from: answeringModel, reasoning(signedDetail), text("About 70 kcal."), done()),
                events(text("Yes."), done())
            )
            let session = LanguageModelSession(model: model(stub, fallbacks: [fallback(fallbackID)]))

            let first = try await session.respond(to: "Calories in an egg?")
            _ = try await session.respond(to: "Sure?")

            let reasoningEntry = first.transcriptEntries.compactMap { entry in
                if case .reasoning(let reasoning) = entry { reasoning } else { nil }
            }.first
            #expect(reasoningEntry.flatMap { metadataString($0.metadata, LanguageModelMetadataKey.model) } == answeringModel)
            let assistant = try #require(try assistantMessages(stub, 1).first)
            #expect(assistant["content"] == "About 70 kcal.")
            #expect(assistant["reasoning_details"] == (isReplayed ? [signedDetail] : nil))
            #expect(assistant["reasoning"] == (isReplayed ? "Eggs are light." : nil))
        }
    }
}

/// A dish, for a schema without constraints.
@Generable
private struct Dish {
    var name: String
}

/// A dish with a serving count, whose range Anthropic's structured outputs reject.
@Generable
private struct Serving {
    var name: String

    @Guide(.range(1...12))
    var servings: Int
}
