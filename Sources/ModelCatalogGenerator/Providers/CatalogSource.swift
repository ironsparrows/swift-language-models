import Foundation

// MARK: - Source

/// A provider whose models and vocabularies the generator reads.
enum CatalogSource: String, Codable, CaseIterable, Sendable {
    case openrouter
    case openai

    /// The provider's name in messages and generated code.
    var displayName: String {
        switch self {
        case .openrouter: "OpenRouter"
        case .openai: "OpenAI"
        }
    }

    /// Where the provider's API lives. `URL(string:)` makes it optional, although it never fails for these addresses.
    var defaultBaseURL: URL? {
        switch self {
        case .openrouter: URL(string: "https://openrouter.ai/api/v1/")
        case .openai: URL(string: "https://api.openai.com/v1/")
        }
    }

    /// The environment variable that holds the API key the provider's list of served models needs, or `nil` when it
    /// needs none.
    private var apiKeyVariable: String? {
        switch self {
        case .openrouter: nil
        case .openai: "OPENAI_API_KEY"
        }
    }

    /// The vocabularies of the provider's API, each rendered as the static members of a type of its own, in the order
    /// their files are made.
    var vocabularies: [CatalogVocabulary] {
        switch self {
        case .openrouter:
            [.inputModalities, .outputModalities, .parameters, .searchContextSizes, .webFetchEngines, .webSearchEngines, .webSearchModes]
        case .openai:
            [.inputModalities, .parameters]
        }
    }

    /// The words of a vocabulary that the provider's module names in its own code, such as the parameters a request
    /// sends. They stay current when the source stops listing them, since a deprecated member would fail CI's build of
    /// the module, which treats warnings as errors.
    func wordsNamedByModule(in vocabulary: CatalogVocabulary) -> Set<String> {
        switch self {
        case .openrouter:
            switch vocabulary {
            case .parameters:
                [
                    "frequency_penalty", "logit_bias", "max_completion_tokens", "max_tokens", "min_p", "parallel_tool_calls",
                    "presence_penalty", "repetition_penalty", "seed", "stop", "structured_outputs", "temperature", "tool_choice",
                    "tools", "top_a", "top_k", "top_p", "verbosity",
                ]
            case .inputModalities: ["audio", "file", "image", "text", "video"]
            case .outputModalities: ["image", "text"]
            case .searchContextSizes, .webFetchEngines, .webSearchEngines, .webSearchModes: []
            }
        case .openai:
            switch vocabulary {
            case .parameters: OpenAIModelList.everyParameter
            case .inputModalities: ["image", "pdf", "text"]
            case .outputModalities, .searchContextSizes, .webFetchEngines, .webSearchEngines, .webSearchModes: []
            }
        }
    }

    /// The effort words that the provider's module, or the core module under it, names in its own code, such as
    /// `none` as `ReasoningLevel.off`. They stay current when the source stops listing them, since a deprecated member
    /// would fail CI's builds of the modules, which treat warnings as errors.
    var effortsNamedByModule: Set<String> {
        switch self {
        case .openrouter, .openai: [EffortRanking.offWord]
        }
    }

    /// The snapshot file, relative to the package root.
    var snapshotPath: String { "Catalogs/\(rawValue).json" }

    /// The schema file, relative to the package root.
    var schemaPath: String { "Catalogs/\(rawValue).schema.json" }

    /// The fields of a document whose words form a vocabulary, so new words get reported.
    private func vocabularyFields(in document: CatalogSource.Documents.Kind) -> Set<String> {
        switch (self, document) {
        case (.openrouter, .modelList):
            [
                "data[].architecture.input_modalities[]",
                "data[].architecture.output_modalities[]",
                "data[].reasoning.supported_efforts[]",
                "data[].supported_parameters[]",
            ]
        case (.openrouter, .apiDescription):
            Set(OpenRouterAPIDescription.wordSchemaNames.map { "components.schemas.\($0).enum[]" })
        case (.openai, .modelList):
            ["models[].modalities.input[]", "models[].modalities.output[]", "models[].reasoning_options[].values[]", "models[].type"]
        case (.openai, .apiDescription):
            ["components.schemas.\(OpenAIAPIDescription.effortSchemaName).anyOf[].enum[]"]
        case (_, .servedModels):
            []
        }
    }

    /// Downloads the documents a fetch reads, one after the other.
    ///
    /// A request that fails without a response, as a network failure does, is sent once more after a pause.
    ///
    /// - Parameters:
    ///   - session: The session that sends the requests.
    ///   - baseURL: Where every document lives, such as a test server, in place of the provider's own addresses.
    ///   - environment: The environment variables, which hold the API key a source's list of served models needs.
    ///   - retryDelay: The pause before a failed request is sent again.
    /// - Returns: The response bodies.
    /// - Throws: ``GeneratorError/brokenSource(_:)`` for a network failure, an HTTP error, or a missing API key.
    func documents(
        using session: URLSession,
        baseURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        retryDelay: Duration = .seconds(2)
    ) async throws(GeneratorError) -> CatalogSource.Documents {
        guard let base = baseURL ?? defaultBaseURL else {
            throw .brokenSource("\(displayName) has an invalid base URL.")
        }
        let location = DocumentLocation(base: base, isOverridden: baseURL != nil)
        var headers: [String: String] = [:]
        if let variable = apiKeyVariable {
            guard let key = environment[variable], !key.isEmpty else {
                throw .brokenSource("\(displayName)'s model list needs an API key: set \(variable) to fetch it.")
            }
            headers["Authorization"] = "Bearer \(key)"
        }
        let modelList = try await download(.modelList, from: location, using: session, retryDelay: retryDelay)
        let apiDescription = try await download(.apiDescription, from: location, using: session, retryDelay: retryDelay)
        let servedModels: Data? =
            switch self {
            case .openrouter: nil
            case .openai: try await download(.servedModels, from: location, headers: headers, using: session, retryDelay: retryDelay)
            }
        return CatalogSource.Documents(modelList: modelList, apiDescription: apiDescription, servedModels: servedModels)
    }

    /// The models and vocabularies the documents describe.
    ///
    /// - Parameters:
    ///   - documents: The response bodies.
    ///   - today: The day of the fetch, in UTC, before which a model's shutdown has passed.
    /// - Returns: The models, which a snapshot sorts, the words of each vocabulary and the efforts.
    /// - Throws: ``GeneratorError/brokenSource(_:)`` when a document doesn't decode.
    func catalog(from documents: CatalogSource.Documents, today: CatalogDay) throws(GeneratorError) -> FetchedCatalog {
        switch self {
        case .openrouter:
            let (vocabularies, efforts) = try reading(.apiDescription, "doesn't decode") {
                let description = try OpenRouterAPIDescription.decoded(from: documents.apiDescription)
                return (try description.vocabularies(), try description.efforts())
            }
            let models = try reading(.modelList, "doesn't decode") {
                try OpenRouterModelsResponse.decoded(from: documents.modelList).catalogModels(everyEffort: efforts)
            }
            return FetchedCatalog(models: models, vocabularies: vocabularies, efforts: efforts)
        case .openai:
            let description = try reading(.apiDescription, "doesn't decode") {
                try OpenAIAPIDescription.decoded(from: documents.apiDescription)
            }
            let (listedIDs, efforts) = try reading(.apiDescription, "doesn't decode") {
                (try description.listedModelIDs(), try description.efforts())
            }
            let descriptions = try reading(.modelList, "doesn't decode") { try ModelsDevCatalog.decoded(from: documents.modelList) }
            let served = try reading(.servedModels, "doesn't decode") {
                try OpenAIModelList.decoded(from: documents.servedModels ?? Data())
            }
            let undescribed = served.undescribedModelIDs(describedBy: descriptions, today: today)
            // The API description's lists don't decide which models the catalog lists, but a model they list takes a text
            // API, so the catalog would list it: its entry has to decode.
            let listedUndescribed = undescribed.intersection(listedIDs).sorted()
            guard listedUndescribed.isEmpty else {
                throw .brokenSource(
                    "\(displayName) returned \(CatalogSource.Documents.Kind.modelList) whose entries for these models, which its API "
                        + "description lists, don't decode: \(listedUndescribed.joined(separator: ", ")).")
            }
            return FetchedCatalog(
                models: served.catalogModels(
                    describedBy: descriptions, everyEffort: efforts, defaultEffort: description.defaultEffort, today: today),
                vocabularies: [:],
                efforts: efforts,
                skippedEntryIDs: descriptions.undecodedIDs,
                undescribedModelIDs: undescribed
            )
        }
    }

    /// The shape of the documents: the fields of the model list and of the list of served models, and the vocabulary
    /// words of every document.
    ///
    /// - Parameter documents: The response bodies.
    /// - Returns: The schema.
    /// - Throws: ``GeneratorError/brokenSource(_:)`` when a document isn't JSON.
    func schema(of documents: CatalogSource.Documents) throws(GeneratorError) -> CatalogSchema {
        let modelList = try reading(.modelList, "isn't JSON") {
            // models.dev keys OpenAI's models by id, so the shape reads them as a list, which doesn't name each id.
            let shape =
                switch self {
                case .openrouter: documents.modelList
                case .openai: try ModelsDevCatalog.shapeDocument(of: documents.modelList)
                }
            return try CatalogSchema(json: shape, vocabularyFields: vocabularyFields(in: .modelList))
        }
        let apiDescription = try reading(.apiDescription, "isn't JSON") {
            try CatalogSchema(json: documents.apiDescription, vocabularyFields: vocabularyFields(in: .apiDescription))
        }
        // The served models' fields, such as `data[].shutdown_date`, never share a path with the model list's, whose
        // shape starts at `models[]`.
        let servedModels = try documents.servedModels.map { (data) throws(GeneratorError) in
            try reading(.servedModels, "isn't JSON") {
                try CatalogSchema(json: data, vocabularyFields: vocabularyFields(in: .servedModels))
            }
        }
        return CatalogSchema(
            fields: Set(modelList.fields).union(servedModels?.fields ?? []).sorted(),
            values: modelList.values.merging(apiDescription.values) { $1 }.merging(servedModels?.values ?? [:]) { $1 }
        )
    }

    /// Where a source's documents live: the provider's API, or a server that stands in for every document's address.
    struct DocumentLocation {
        let base: URL
        let isOverridden: Bool
    }

    /// Where a document lives.
    func url(of document: CatalogSource.Documents.Kind, location: DocumentLocation) -> URL? {
        let base = location.base
        return switch (self, document) {
        case (.openrouter, .modelList):
            // OpenRouter lists only models that generate text unless asked otherwise; asking keeps that if the
            // default changes.
            base.appending(path: "models")
                .appending(queryItems: [URLQueryItem(name: "output_modalities", value: CatalogModel.textModality)])
        case (.openrouter, .apiDescription):
            URL(string: "/openapi.json", relativeTo: base)?.absoluteURL
        case (.openai, .modelList):
            location.isOverridden ? base.appending(path: "models.dev.json") : URL(string: "https://models.dev/api.json")
        case (.openai, .apiDescription):
            location.isOverridden
                ? base.appending(path: "openapi.json")
                : URL(string: "https://raw.githubusercontent.com/openai/openai-openapi/main/openapi.json")
        case (.openai, .servedModels):
            base.appending(path: "models")
        case (.openrouter, .servedModels):
            nil
        }
    }

    /// Downloads one document, sending the request once more after a pause when it fails without a response.
    ///
    /// - Throws: ``GeneratorError/brokenSource(_:)`` when the source has no address for the document, the request fails
    ///   again, or the status isn't a success.
    private func download(
        _ document: CatalogSource.Documents.Kind,
        from location: DocumentLocation,
        headers: [String: String] = [:],
        using session: URLSession,
        retryDelay: Duration
    ) async throws(GeneratorError) -> Data {
        guard let url = url(of: document, location: location) else {
            throw .brokenSource("\(displayName) has no address for \(document).")
        }
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let data: Data
        let response: URLResponse
        do {
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                try await Task.sleep(for: retryDelay)
                (data, response) = try await session.data(for: request)
            }
        } catch {
            throw .brokenSource("\(displayName) couldn't be reached: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode
        guard let status, (200..<300).contains(status) else {
            throw .brokenSource("\(displayName) returned HTTP \(status?.description ?? "without a status") instead of \(document).")
        }
        return data
    }

    /// Runs a step that reads a document, turning its error into ``GeneratorError/brokenSource(_:)``.
    private func reading<Value>(
        _ document: CatalogSource.Documents.Kind,
        _ problem: String,
        _ step: () throws -> Value
    ) throws(GeneratorError) -> Value {
        do {
            return try step()
        } catch {
            throw .brokenSource("\(displayName) returned \(document) that \(problem): \(error)")
        }
    }
}

// MARK: - Documents

extension CatalogSource {
    /// The documents a fetch reads from a source.
    struct Documents: Sendable {
        /// A document a fetch reads.
        enum Kind: Sendable, CustomStringConvertible {
            /// The list that describes the source's models, which for OpenAI is models.dev's.
            case modelList
            /// The source's OpenAPI description, which lists the whole vocabularies and describes their words.
            case apiDescription
            /// The list of the models the provider still serves, for a source whose model list also describes models
            /// the provider stopped serving.
            case servedModels

            var description: String {
                switch self {
                case .modelList: "a model list"
                case .apiDescription: "an API description"
                case .servedModels: "a list of served models"
                }
            }
        }

        let modelList: Data
        let apiDescription: Data
        /// The served models, for a source that has a list of them.
        private(set) var servedModels: Data?
    }
}
