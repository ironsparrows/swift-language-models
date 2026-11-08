import Foundation
import LanguageModelsTestSupport
import Testing

@testable import ModelCatalogGenerator

@Suite("OpenAI source")
struct OpenAISourceTests {
    @Test func `the catalog lists the served models that models.dev describes as text models, and none shut down`() throws {
        let snapshot = try openAIFixtureSnapshot()

        #expect(snapshot.models.map(\.id) == ["gpt-4o", "gpt-4o-2024-11-20", "gpt-6-astra", "gpt-6-luna", "o3"])
    }

    @Test func `a dated snapshot that models.dev doesn't list takes its model's description and name, with its day`() throws {
        let models = try openAIFixtureSnapshot().models
        let snapshot = try #require(models.first { $0.id == "gpt-4o-2024-11-20" })
        let model = try #require(models.first { $0.id == "gpt-4o" })

        #expect(snapshot.displayName == "GPT-4o (2024-11-20)")
        #expect(snapshot.supportedParameters == model.supportedParameters)
        #expect(snapshot.releasedAt != model.releasedAt)
    }

    @Test func `a model that takes none reasons until a request turns it off, and one that doesn't always reasons`() throws {
        let models = try openAIFixtureSnapshot().models

        #expect(models.first { $0.id == "gpt-6-luna" }?.reasoning == .optional(enabledByDefault: true))
        #expect(models.first { $0.id == "gpt-6-astra" }?.reasoning == .mandatory)
        #expect(models.first { $0.id == "gpt-4o" }?.reasoning == .unsupported)
        #expect(models.first { $0.id == "o3" }?.reasoningEfforts == ["high", "medium", "low"])
    }

    @Test func `the efforts come from the API description, highest first`() throws {
        #expect(try openAIFixtureSnapshot().efforts.map(\.word) == ["max", "xhigh", "high", "medium", "low", "minimal", "none"])
    }

    @Test func `a model whose shutdown day is today is still listed, with the day as its expiration`() throws {
        let catalog = try CatalogSource.openai.catalog(from: openAIFixtureDocuments(), today: "2026-10-23")

        #expect(catalog.models.first { $0.id == "o4-mini" }?.expirationDate == "2026-10-23")
    }

    @Test func `fetching OpenAI's models without an API key fails before any request`() async {
        let stub = HTTPStub()

        await #expect(throws: GeneratorError.brokenSource("OpenAI's model list needs an API key: set OPENAI_API_KEY to fetch it.")) {
            _ = try await CatalogSource.openai.documents(using: stub.session, baseURL: stub.baseURL, environment: [:])
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func `an HTTP error from OpenAI's list of served models fails the fetch`() async throws {
        let fixture = try openAIFixtureDocuments()
        let stub = HTTPStub(
            .json(String(decoding: fixture.modelList, as: UTF8.self)),
            .json(String(decoding: fixture.apiDescription, as: UTF8.self)),
            .json(#"{"error": {"message": "Incorrect API key provided.", "code": "invalid_api_key"}}"#, status: 401)
        )

        await #expect(throws: GeneratorError.brokenSource("OpenAI returned HTTP 401 instead of a list of served models.")) {
            _ = try await CatalogSource.openai.documents(
                using: stub.session, baseURL: stub.baseURL, environment: ["OPENAI_API_KEY": "test-key"], retryDelay: .zero)
        }
        #expect(stub.requests.last?.request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test(arguments: [
        (CatalogSource.Documents.Kind.modelList, "https://models.dev/api.json"),
        (.apiDescription, "https://raw.githubusercontent.com/openai/openai-openapi/main/openapi.json"),
        (.servedModels, "https://api.openai.com/v1/models"),
    ])
    func `without a server standing in, each document comes from its real address`(document: CatalogSource.Documents.Kind, address: String)
        throws
    {
        let location = CatalogSource.DocumentLocation(base: try #require(CatalogSource.openai.defaultBaseURL), isOverridden: false)

        #expect(CatalogSource.openai.url(of: document, location: location)?.absoluteString == address)
    }

    @Test(arguments: OpenAIAPIDescription.modelIDSchemaNames + [OpenAIAPIDescription.effortSchemaName])
    func `an API description without a schema the catalog reads fails`(schema: String) throws {
        let documents = try editedFixture(schemas: { $0[schema] = nil })

        let error = #expect(throws: GeneratorError.self) {
            try CatalogSource.openai.catalog(from: documents, today: "2026-10-29")
        }

        #expect(error?.exitCode == 2)
        #expect(
            error?.description == "OpenAI returned an API description that doesn't decode: \(MissingSchema(name: schema).description)")
    }

    @Test func `models.dev without OpenAI's models fails`() throws {
        var documents = try openAIFixtureDocuments()
        documents = CatalogSource.Documents(
            modelList: Data(#"{"anthropic": {"models": {}}}"#.utf8), apiDescription: documents.apiDescription,
            servedModels: documents.servedModels)

        let error = #expect(throws: GeneratorError.self) {
            try CatalogSource.openai.catalog(from: documents, today: "2026-10-29")
        }

        #expect(error?.exitCode == 2)
        #expect(error?.description.hasPrefix("OpenAI returned a model list that doesn't decode:") == true)
    }

    @Test(arguments: ["2027-02-30", "2027-01-14T00:00:00Z", "soon"])
    func `a shutdown day that isn't a real day fails, rather than losing the model's expiration`(shutdownDate: String) throws {
        let documents = try editedFixture(servedModels: { models in
            for index in models.indices where models[index]["id"] as? String == "gpt-4o" {
                models[index]["shutdown_date"] = shutdownDate
            }
        })

        let error = #expect(throws: GeneratorError.self) {
            try CatalogSource.openai.catalog(from: documents, today: "2026-10-29")
        }

        #expect(error?.exitCode == 2)
        #expect(error?.description.hasPrefix("OpenAI returned a list of served models that doesn't decode:") == true)
    }

    @Test func `a model OpenAI serves and models.dev describes is listed though the API description doesn't list it`() throws {
        let catalog = try CatalogSource.openai.catalog(from: editedFixture(addingServedModel: Self.unlistedModel), today: "2026-10-29")

        let model = try #require(catalog.models.first { $0.id == Self.unlistedModel })
        #expect(model.supportedParameters.contains("tools"))
    }

    @Test func `a models.dev entry that doesn't decode is skipped, and the others are read`() throws {
        let documents = try editedFixture(addingServedModel: Self.unlistedModel) { entries in
            entries[Self.unlistedModel] = ["name": Self.unlistedModel]
            entries["gpt-image-9"] = ["name": "gpt-image-9", "modalities": ["output": ["image"]]]
        }

        let catalog = try CatalogSource.openai.catalog(from: documents, today: "2026-10-29")

        #expect(catalog.models.map(\.id) == ["gpt-4o", "gpt-4o-2024-11-20", "gpt-6-astra", "gpt-6-luna", "o3"])
        #expect(catalog.skippedEntryIDs == [Self.unlistedModel, "gpt-image-9"])
        #expect(catalog.undescribedModelIDs == [Self.unlistedModel])
    }

    @Test func `a model the API description lists whose entry doesn't decode fails the fetch`() throws {
        let documents = try editedFixture { $0["gpt-6-luna"] = ["name": "GPT-6 Luna"] }

        let error = #expect(throws: GeneratorError.self) {
            try CatalogSource.openai.catalog(from: documents, today: "2026-10-29")
        }

        #expect(
            error
                == .brokenSource(
                    "OpenAI returned a model list whose entries for these models, which its API description lists, don't decode: gpt-6-luna."
                ))
    }

    @Test func `a listed model whose entry stops decoding fails the fetch, rather than being removed`() throws {
        let listed = try CatalogSource.openai.catalog(from: editedFixture(addingServedModel: Self.unlistedModel), today: "2026-10-29")
        let previous = try CatalogSnapshot.updated(source: .openai, fetched: listed, previous: nil, today: "2026-10-29")
        let documents = try editedFixture(addingServedModel: Self.unlistedModel) { $0[Self.unlistedModel] = ["name": Self.unlistedModel] }

        #expect(throws: GeneratorError.brokenSource("OpenAI's entries for these listed models don't decode: \(Self.unlistedModel).")) {
            try CatalogSnapshot.updated(
                source: .openai, fetched: CatalogSource.openai.catalog(from: documents, today: "2026-10-30"), previous: previous,
                today: "2026-10-30")
        }
    }

    @Test(arguments: [
        "gpt-4o-search-preview", "gpt-4o-mini-search-preview-2025-03-11", "gpt-5-search-api", "gpt-4o-audio-preview", "gpt-audio-mini",
        "gpt-3.5-turbo-instruct", "gpt-realtime", "gpt-4o-mini-transcribe", "gpt-4o-mini-tts",
    ])
    func `a model that works only with another endpoint is left out, even when models.dev describes it as a text model`(id: String)
        throws
    {
        let documents = try editedFixture(
            addingServedModel: id,
            entries: { $0[id] = ["name": id, "modalities": ["input": ["text"], "output": ["text"]]] },
            schemas: { schemas in
                schemas["ModelIdsShared"] = ["anyOf": [["type": "string", "enum": ["gpt-6-luna", id]]]]
            }
        )

        let catalog = try CatalogSource.openai.catalog(from: documents, today: "2026-10-29")

        #expect(!catalog.models.map(\.id).contains(id))
        #expect(catalog.models.map(\.id).contains("gpt-6-luna"))
    }

    @Test(arguments: ["gpt-4o", "gpt-5.3-codex", "gpt-5.4-pro-2026-03-05", "o3-deep-research", "computer-use-preview", "gpt-6-luna"])
    func `a model of the Responses API isn't taken for one that works only with another endpoint`(id: String) {
        #expect(!OpenAIModelList.worksOnlyWithOtherEndpoints(id))
    }

    /// A model the fixture's API description doesn't list.
    private static let unlistedModel = "gpt-6-nova"

    /// The OpenAI fixture with its documents edited.
    ///
    /// - Parameters:
    ///   - servedModel: A model to add to the served models, with an entry like `gpt-4o`'s named by its id, which
    ///     `entries` can change.
    ///   - entries: Changes models.dev's OpenAI entries, by id.
    ///   - servedModels: Changes the served models.
    ///   - schemas: Changes the API description's schemas, by name.
    /// - Returns: The documents.
    /// - Throws: An error when a fixture can't be read or edited.
    private func editedFixture(
        addingServedModel servedModel: String? = nil,
        entries: (inout [String: Any]) -> Void = { _ in },
        servedModels: (inout [[String: Any]]) -> Void = { _ in },
        schemas: (inout [String: Any]) -> Void = { _ in }
    ) throws -> CatalogSource.Documents {
        let fixture = try openAIFixtureDocuments()
        func edited(_ data: Data, at path: [String], _ edit: (inout Any) -> Void) throws -> Data {
            func descend(into value: inout Any, at path: ArraySlice<String>) {
                guard let key = path.first else { return edit(&value) }
                var object = value as? [String: Any] ?? [:]
                var child = object[key] ?? [String: Any]()
                descend(into: &child, at: path.dropFirst())
                object[key] = child
                value = object
            }
            var json = try JSONSerialization.jsonObject(with: data)
            descend(into: &json, at: path[...])
            return try JSONSerialization.data(withJSONObject: json)
        }
        return CatalogSource.Documents(
            modelList: try edited(fixture.modelList, at: ["openai", "models"]) { value in
                var models = value as? [String: Any] ?? [:]
                if let servedModel {
                    models[servedModel] = (models["gpt-4o"] as? [String: Any] ?? [:]).merging(["name": servedModel]) { $1 }
                }
                entries(&models)
                value = models
            },
            apiDescription: try edited(fixture.apiDescription, at: ["components", "schemas"]) { value in
                var all = value as? [String: Any] ?? [:]
                schemas(&all)
                value = all
            },
            servedModels: try edited(fixture.servedModels ?? Data(), at: ["data"]) { value in
                var models = value as? [[String: Any]] ?? []
                if let servedModel {
                    models.append(["id": servedModel, "object": "model", "created": 1_760_000_000, "owned_by": "system"])
                }
                servedModels(&models)
                value = models
            }
        )
    }
}
