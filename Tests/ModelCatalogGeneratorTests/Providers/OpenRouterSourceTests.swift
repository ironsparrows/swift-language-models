import Foundation
import LanguageModelsTestSupport
import Testing

@testable import ModelCatalogGenerator

@Suite("OpenRouter source")
struct OpenRouterSourceTests {
    private static let everyEffort = ["max", "high", "medium", "low", "none"]

    @Test func `a model that doesn't list its efforts gets none`() throws {
        let model = try catalogModel(reasoning: #"{"mandatory": false, "default_effort": "high"}"#)

        #expect(model.reasoningEfforts.isEmpty)
        #expect(model.defaultReasoningEffort == nil)
    }

    @Test func `a model that accepts every effort lists them all`() throws {
        let model = try catalogModel(reasoning: #"{"mandatory": false, "supported_efforts": null, "default_effort": "medium"}"#)

        #expect(model.reasoningEfforts == Self.everyEffort)
        #expect(model.defaultReasoningEffort == "medium")
    }

    @Test func `a model whose reasoning is mandatory never takes none`() throws {
        let model = try catalogModel(reasoning: #"{"mandatory": true, "supported_efforts": ["high", "none"], "default_effort": "none"}"#)

        #expect(model.reasoningEfforts == ["high"])
        #expect(model.defaultReasoningEffort == nil)
        #expect(model.reasoning == .mandatory)
    }

    @Test(arguments: [
        (#"{"default_enabled": true}"# as String?, #"["reasoning"]"#, CatalogReasoning.optional(enabledByDefault: true)),
        (#"{"mandatory": false}"#, #"["reasoning"]"#, .optional(enabledByDefault: false)),
        (#"{"default_enabled": true}"#, #"["tools"]"#, .unsupported),
        (nil, #"["tools"]"#, .unsupported),
    ])
    func `a model that isn't made to reason reasons only through the reasoning parameter`(
        reasoning: String?,
        parameters: String,
        expected: CatalogReasoning
    ) throws {
        #expect(try catalogModel(reasoning: reasoning, parameters: parameters).reasoning == expected)
    }

    @Test func `a default effort the model doesn't list is dropped`() throws {
        let model = try catalogModel(reasoning: #"{"mandatory": false, "supported_efforts": ["high", "low"], "default_effort": "medium"}"#)

        #expect(model.defaultReasoningEffort == nil)
    }

    @Test(arguments: [
        (#"["/api/v1/chat/completions", "/api/v1/images"]"#, ["image", "text"]),
        (#"["/api/v1/chat/completions", "/api/v1/responses"]"#, ["text"]),
    ])
    func `images stay among a model's outputs only when OpenRouter serves it on its images path`(
        endpoints: String,
        expected: [String]
    ) throws {
        #expect(try catalogModel(outputs: #"["text", "image"]"#, endpoints: endpoints).outputModalities == expected)
    }

    @Test func `a model that doesn't list the paths that serve it fails to decode`() {
        #expect(throws: DecodingError.self) { try catalogModel(endpoints: nil) }
    }

    @Test(arguments: [
        [("vendor/model", "/api/v1/chat/completions")],
        [("vendor/model", "/api/v1/chat/completions"), ("vendor/model:batch", "/api/v1/images")],
    ])
    func `a model list that serves none of the catalog's image models on the images path fails the fetch`(
        models: [(id: String, path: String)]
    ) throws {
        let entries = models.map { model in
            #"{"id": "\#(model.id)", "name": "Model", "created": 0, "endpoints": ["\#(model.path)"], "#
                + #""architecture": {"input_modalities": ["text"], "output_modalities": ["text", "image"]}}"#
        }
        let documents = CatalogSource.Documents(
            modelList: Data(#"{"data": [\#(entries.joined(separator: ", "))]}"#.utf8),
            apiDescription: try Bundle.module.fixture("openrouter-openapi.json"))

        #expect(
            throws: GeneratorError.brokenSource(
                "OpenRouter's model list serves none of the models that list images on its images path, so it no longer tells "
                    + "which models return images.")
        ) {
            _ = try CatalogSource.openrouter.catalog(from: documents, today: "2026-10-29")
        }
    }

    @Test func `an alias keeps the id of the model it points to`() throws {
        let model = try catalogModel(fields: #""alias_target": {"name": "Vendor: Model 2", "slug": "vendor/model-2"}"#)

        #expect(model.aliasTarget == "vendor/model-2")
    }

    @Test(arguments: [#""knowledge_cutoff": "2026-02-30""#, #""expiration_date": "2026-12-31T00:00:00Z""#])
    func `a day that isn't real fails to decode`(field: String) {
        #expect(throws: DecodingError.self) {
            try catalogModel(fields: field)
        }
    }

    @Test(arguments: [
        ("anthropic/claude-sonnet-4.6", nil as String?, true),
        ("~anthropic/claude-haiku-latest", nil, true),
        ("qwen/qwen3.7-flash", #""input_cache_write": "0.000000375""#, true),
        ("qwen/qwen3-235b-a22b", nil, false),
        ("qwen/qwen3.7-flash", #""input_cache_write": "-1""#, false),
        ("google/gemini-3.5-flash", #""input_cache_write": "0.0000001875""#, false),
    ])
    func `Claude, and the Qwen models with a cache write price, cache only marked prompts`(
        id: String,
        cacheWrite: String?,
        cachesOnlyMarkedPrompts: Bool
    ) throws {
        let pricing = [#""prompt": "0.0000003", "completion": "0.0000012""#, cacheWrite].compactMap(\.self)
        let model = try catalogModel(id: id, fields: #""pricing": {\#(pricing.joined(separator: ", "))}"#)

        #expect(model.cachesOnlyMarkedPrompts == cachesOnlyMarkedPrompts)
    }

    @Test func `a model that works only through the Batch API is left out`() throws {
        let fields =
            #""architecture": {"input_modalities": ["text"], "output_modalities": ["text"]}, "endpoints": ["/api/v1/chat/completions"]"#
        let json = #"""
            {"data": [
                {"id": "vendor/model", "name": "Model", "created": 0, \#(fields)},
                {"id": "vendor/model:batch", "name": "Model (batch)", "created": 0, \#(fields)}
            ]}
            """#

        let models = try OpenRouterModelsResponse.decoded(from: Data(json.utf8)).catalogModels(everyEffort: Self.everyEffort)

        #expect(models.map(\.id) == ["vendor/model"])
    }

    @Test func `words a model lists twice are kept once`() throws {
        let model = try catalogModel(
            reasoning: #"{"mandatory": false, "supported_efforts": ["high", "low", "high"]}"#,
            parameters: #"["tools", "reasoning", "tools"]"#
        )

        #expect(model.reasoningEfforts == ["high", "low"])
        #expect(model.supportedParameters == ["reasoning", "tools"])
    }

    @Test func `the API description gives the vocabularies, summaries and efforts`() throws {
        let description = try OpenRouterAPIDescription.decoded(
            from: Data(
                #"""
                {"components": {"schemas": {
                    "Parameter": {"enum": ["seed", "tool_choice", "verbosity"]},
                    "InputModality": {"enum": ["text", "image"]},
                    "OutputModality": {"enum": ["text"]},
                    "ReasoningEffort": {"enum": ["high", "low", null]},
                    "SearchQualityLevel": {"enum": ["low", "high"]},
                    "WebFetchEngineEnum": {"enum": ["auto", "openrouter"]},
                    "WebSearchEngineEnum": {"enum": ["exa", "auto"]},
                    "WebSearchMode": {"enum": ["deep-lite"]},
                    "ChatRequest": {"properties": {
                        "seed": {"description": "Random seed\n  for outputs"},
                        "tool_choice": {"$ref": "#/components/schemas/ChatToolChoice"}
                    }},
                    "ChatToolChoice": {"description": "Which tool to call?"},
                    "Order": {"enum": [1, 2]}
                }}}
                """#.utf8
            )
        )

        #expect(try description.efforts() == ["high", "low"])
        #expect(
            try description.vocabularies() == [
                .inputModalities: [CatalogWord("text"), CatalogWord("image")],
                .outputModalities: [CatalogWord("text")],
                .parameters: [
                    CatalogWord("seed", summary: "Random seed for outputs."),
                    CatalogWord("tool_choice", summary: "Which tool to call?"),
                    CatalogWord("verbosity"),
                ],
                .searchContextSizes: [CatalogWord("low"), CatalogWord("high")],
                .webFetchEngines: [CatalogWord("auto"), CatalogWord("openrouter")],
                .webSearchEngines: [CatalogWord("exa"), CatalogWord("auto")],
                .webSearchModes: [CatalogWord("deep-lite")],
            ]
        )
    }

    @Test func `an API description that lists a word twice keeps it once`() throws {
        let description = try OpenRouterAPIDescription.decoded(
            from: Data(#"{"components": {"schemas": {"ReasoningEffort": {"enum": ["high", "low", "high", null]}}}}"#.utf8)
        )

        #expect(try description.efforts() == ["high", "low"])
    }

    @Test func `an API description without a vocabulary fails`() throws {
        let documents = CatalogSource.Documents(
            modelList: try fixtureDocuments().modelList, apiDescription: Data(#"{"components": {"schemas": {}}}"#.utf8))

        let error = #expect(throws: GeneratorError.self) {
            try CatalogSource.openrouter.catalog(from: documents, today: "2026-10-29")
        }

        #expect(error?.exitCode == 2)
        #expect(error?.description.contains("doesn't decode: it has no words for the") == true)
    }

    @Test(arguments: [
        (CatalogSource.Documents.Kind.modelList, "https://openrouter.ai/api/v1/models?output_modalities=text" as String?),
        (.apiDescription, "https://openrouter.ai/openapi.json"),
        (.servedModels, nil),
    ])
    func `without a server standing in, each document comes from its real address`(document: CatalogSource.Documents.Kind, address: String?)
        throws
    {
        let location = CatalogSource.DocumentLocation(base: try #require(CatalogSource.openrouter.defaultBaseURL), isOverridden: false)

        #expect(CatalogSource.openrouter.url(of: document, location: location)?.absoluteString == address)
    }

    private func catalogModel(
        id: String = "vendor/model",
        reasoning: String? = nil,
        parameters: String = #"["reasoning"]"#,
        outputs: String = #"["text"]"#,
        endpoints: String? = #"["/api/v1/chat/completions"]"#,
        fields: String? = nil
    ) throws -> CatalogModel {
        let model = [
            #""id": "\#(id)", "name": "Model", "created": 0"#,
            #""architecture": {"input_modalities": ["text"], "output_modalities": \#(outputs)}"#,
            endpoints.map { #""endpoints": \#($0)"# },
            #""supported_parameters": \#(parameters)"#,
            reasoning.map { #""reasoning": \#($0)"# },
            fields,
        ]
        let json = #"{"data": [{\#(model.compactMap(\.self).joined(separator: ", "))}]}"#
        let response = try OpenRouterModelsResponse.decoded(from: Data(json.utf8))
        return try #require(response.catalogModels(everyEffort: Self.everyEffort).first)
    }
}
