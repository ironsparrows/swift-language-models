import Foundation
import LanguageModelsTestSupport
import Testing

@testable import ModelCatalogGenerator

@Suite("Generator run")
final class GeneratorRunTests {
    private let package = FileManager.default.temporaryDirectory.appending(
        path: "ModelCatalogGeneratorTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    deinit {
        try? FileManager.default.removeItem(at: package)
    }

    @Test func `fetch, render and check run end to end`() async throws {
        let stub = try fixtureStub()

        try await run(.fetch, stub: stub)
        try await run(.render, stub: stub)
        try await run(.check, stub: stub)

        #expect(
            stub.requests.map { $0.request.url?.absoluteString } == [
                "\(stub.baseURL.absoluteString)/models?output_modalities=text",
                "\(stub.baseURL.absoluteString)/openapi.json",
                "\(stub.baseURL.absoluteString)/models.dev.json",
                "\(stub.baseURL.absoluteString)/openapi.json",
                "\(stub.baseURL.absoluteString)/models",
            ])
        #expect(stub.requests.map { $0.request.value(forHTTPHeaderField: "Authorization") } == [nil, nil, nil, nil, "Bearer test-key"])
        for (path, goldenName) in [
            ("Catalogs/openrouter.json", "openrouter.json.golden"), ("Catalogs/openrouter.schema.json", "openrouter.schema.json.golden"),
            ("Catalogs/openai.json", "openai.json.golden"), ("Catalogs/openai.schema.json", "openai.schema.json.golden"),
        ] {
            let written = try String(contentsOf: package.appending(path: path), encoding: .utf8)
            #expect(try golden(goldenName) == written, "\(path)")
        }
    }

    @Test func `render leaves files that are already up to date alone`() async throws {
        let stub = try fixtureStub()
        try await run(.fetch, stub: stub)
        let firstRender = try await run(.render, stub: stub)

        let secondRender = try await run(.render, stub: stub)

        #expect(firstRender.contains("Rendered \(ReasoningLevelTemplate.path)."))
        #expect(secondRender == ["Generated files are up to date."])
    }

    @Test func `check fails when a generated file was edited`() async throws {
        let stub = try fixtureStub()
        try await run(.fetch, stub: stub)
        try await run(.render, stub: stub)
        try Data("// edited\n".utf8).write(to: package.appending(path: ReasoningLevelTemplate.path))

        await #expect(throws: GeneratorError.stale([ReasoningLevelTemplate.path])) {
            try await self.run(.check, stub: stub)
        }
    }

    @Test func `diff writes the changes since a git revision and the release they need`() async throws {
        let stub = try fixtureStub()
        try await run(.fetch, stub: stub)
        try git("init", "--quiet")
        try git("add", "Catalogs")
        try git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "-m", "Catalogs")
        let snapshot = try #require(try CatalogJSON.read(CatalogSnapshot.self, at: "Catalogs/openrouter.json", in: package))
        let deleted = try #require(snapshot.models.first)
        let edited = CatalogSnapshot(
            source: snapshot.source,
            models: Array(snapshot.models.dropFirst()),
            removed: snapshot.removed,
            vocabularies: snapshot.vocabularies,
            efforts: snapshot.efforts
        )
        try Data(CatalogJSON.encoded(edited).utf8).write(to: package.appending(path: "Catalogs/openrouter.json"))

        let log = try await run(.diff, stub: stub, base: "HEAD")

        let report = try #require(try CatalogJSON.read(Generator.Report.self, at: Generator.reportPath, in: package))
        let changelog = try String(contentsOf: package.appending(path: Generator.changelogPath), encoding: .utf8)
        #expect(log == ["The catalogs' changes since HEAD need a major release. See \(Generator.changelogPath)."])
        #expect(report.bump == .major)
        #expect(changelog.contains("- Deletes `\(deleted.id)`."))
    }

    @Test func `diff against a revision without a snapshot adds every model`() async throws {
        let stub = try fixtureStub()
        try await run(.fetch, stub: stub)
        try git("init", "--quiet")
        try git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "--allow-empty", "-m", "Empty")
        let snapshot = try #require(try CatalogJSON.read(CatalogSnapshot.self, at: "Catalogs/openrouter.json", in: package))

        let log = try await run(.diff, stub: stub, base: "HEAD")

        let report = try #require(try CatalogJSON.read(Generator.Report.self, at: Generator.reportPath, in: package))
        let added = snapshot.models.map { model in
            "Adds `\(model.id)`" + (model.expirationDate.map { ", which OpenRouter retires on \($0)" } ?? "") + "."
        }
        #expect(log == ["The catalogs' changes since HEAD need a patch release. See \(Generator.changelogPath)."])
        #expect(report.bump == .patch)
        let openRouter = try #require(report.sources.first { $0.source == .openrouter })
        #expect(openRouter.members.filter { $0.summary.hasPrefix("Adds `") }.map(\.summary) == added)
        #expect(report.sources.allSatisfy { $0.models.isEmpty && $0.api.isEmpty })
    }

    @Test func `diff fails with a usage error for a revision that doesn't exist`() async throws {
        let stub = try fixtureStub()
        try await run(.fetch, stub: stub)
        try git("init", "--quiet")

        let error = await #expect(throws: GeneratorError.self) {
            try await self.run(.diff, stub: stub, base: "nowhere")
        }

        #expect(error?.exitCode == 64)
    }

    @Test(arguments: [Command.Action.render, .check, .clearRemoved])
    func `render, check and clear-removed fail without a snapshot`(action: Command.Action) async {
        await #expect(throws: GeneratorError.fileAccess("Catalogs/openrouter.json is missing. Run `fetch` to create it.")) {
            try await self.run(action, stub: HTTPStub())
        }
    }

    @Test func `clear-removed writes the snapshots without what they mark removed, and render then deletes the members`() async throws {
        let stub = try fixtureStub()
        try await run(.fetch, stub: stub)
        let path = CatalogSource.openrouter.snapshotPath
        let snapshot = try #require(try CatalogJSON.read(CatalogSnapshot.self, at: path, in: package))
        let gone = try #require(snapshot.models.first)
        let withRemoved = CatalogSnapshot(
            source: snapshot.source, models: Array(snapshot.models.dropFirst()),
            removed: [RemovedModel(model: gone, removedOn: "2026-10-01")], vocabularies: snapshot.vocabularies, efforts: snapshot.efforts)
        try Data(try CatalogJSON.encoded(withRemoved).utf8).write(to: package.appending(path: path))
        try await run(.render, stub: stub)
        let removals = package.appending(path: "Sources/OpenRouterLanguageModels/Generated/ModelRemovals+OpenRouter.swift")
        #expect(try String(contentsOf: removals, encoding: .utf8).contains(gone.id))

        let otherSource = try await run(.clearRemoved, stub: stub, sources: [.openai])
        let log = try await run(.clearRemoved, stub: stub)
        try await run(.render, stub: stub)

        let cleared = try #require(try CatalogJSON.read(CatalogSnapshot.self, at: path, in: package))
        #expect(cleared == (try withRemoved.clearingRemoved()))
        #expect(otherSource == ["The catalogs mark nothing removed."])
        #expect(log == ["Cleared \(path). Models deleted: \(gone.id)."])
        #expect(try !String(contentsOf: removals, encoding: .utf8).contains(gone.id))
        try await run(.check, stub: stub)
    }

    @Test func `a snapshot that doesn't decode fails with its path`() async throws {
        try FileManager.default.createDirectory(at: package.appending(path: "Catalogs"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: package.appending(path: "Catalogs/openrouter.json"))

        let error = await #expect(throws: GeneratorError.self) {
            try await self.run(.render, stub: HTTPStub())
        }

        #expect(error?.exitCode == 65)
        #expect(error?.description.hasPrefix("Catalogs/openrouter.json doesn't decode:") == true)
    }

    @Test func `an HTTP error from every source fails the fetch and writes nothing`() async throws {
        let failure = StubResponse.json(#"{"error":{"code":500,"message":"down"}}"#, status: 500)
        let stub = HTTPStub(failure, failure)
        let problems = [
            "OpenRouter returned HTTP 500 instead of a model list.", "OpenAI returned HTTP 500 instead of a model list.",
            "These sources weren't updated: OpenRouter, OpenAI. Fetch them again with `--sources openrouter,openai`.",
        ]

        await #expect(throws: GeneratorError.brokenSource(problems.joined(separator: "\n"))) {
            try await self.run(.fetch, stub: stub)
        }
        #expect(!FileManager.default.fileExists(atPath: package.appending(path: "Catalogs").path(percentEncoded: false)))
    }

    @Test func `a source that fails doesn't hold back the others, which are written before the fetch fails`() async throws {
        let documents = try fixtureDocuments()
        let openAI = try openAIFixtureDocuments()
        let stub = HTTPStub(
            .json(String(decoding: documents.modelList, as: UTF8.self)),
            .json(String(decoding: documents.apiDescription, as: UTF8.self)),
            .json(String(decoding: openAI.modelList, as: UTF8.self)),
            .json(String(decoding: openAI.apiDescription, as: UTF8.self)),
            .json(#"{"error": {"message": "Incorrect API key provided.", "code": "invalid_api_key"}}"#, status: 401)
        )
        var log: [String] = []
        var failure: GeneratorError?

        do {
            try await Generator.run(
                Command(action: .fetch, packageDirectory: package, sources: [.openrouter, .openai]), session: stub.session,
                baseURL: stub.baseURL, environment: ["OPENAI_API_KEY": "test-key"], today: "2026-10-29"
            ) { log.append($0) }
        } catch {
            failure = error
        }

        #expect(
            failure
                == .brokenSource(
                    "OpenAI returned HTTP 401 instead of a list of served models.\n"
                        + "These sources weren't updated: OpenAI. Fetch them again with `--sources openai`."
                ))
        let written = try String(contentsOf: package.appending(path: "Catalogs/openrouter.json"), encoding: .utf8)
        #expect(try golden("openrouter.json.golden") == written)
        #expect(!FileManager.default.fileExists(atPath: package.appending(path: "Catalogs/openai.json").path(percentEncoded: false)))
        #expect(log.first?.hasSuffix(" OpenRouter models into Catalogs/openrouter.json.") == true)
    }

    @Test func `models that can't become code fail the fetch and write nothing`() async throws {
        let documents = try fixtureDocuments()
        let modelList = String(decoding: documents.modelList, as: UTF8.self)
            .replacing(#""id": "typesafe/jev-router""#, with: #""id": "~/-""#)
        let stub = try fixtureStub(openRouterModelList: modelList)
        let problem = "These OpenRouter models get no Swift name: ~/-."

        let error = await #expect(throws: GeneratorError.brokenSource("The fetched models can't become code: \(problem)")) {
            try await self.run(.fetch, stub: stub)
        }

        #expect(error?.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: package.appending(path: "Catalogs").path(percentEncoded: false)))
    }

    @Test func `a network failure is tried once more`() async throws {
        let stub = HTTPStub(.json(String(decoding: try fixtureDocuments().modelList, as: UTF8.self)))

        let error = await #expect(throws: GeneratorError.self) {
            try await CatalogSource.openrouter.documents(using: stub.session, baseURL: stub.baseURL, retryDelay: .zero)
        }

        #expect(error?.exitCode == 2)
        #expect(error?.description.hasPrefix("OpenRouter couldn't be reached:") == true)

        #expect(stub.requests.compactMap { $0.request.url?.lastPathComponent } == ["models", "openapi.json", "openapi.json"])
    }

    /// The fixtures of every source, in the order a fetch of both reads them.
    ///
    /// - Parameter openRouterModelList: OpenRouter's model list, or `nil` for the fixture's.
    /// - Returns: A stub that answers with each document in turn.
    /// - Throws: An error when a fixture can't be read.
    private func fixtureStub(openRouterModelList: String? = nil) throws -> HTTPStub {
        let documents = try fixtureDocuments()
        let openAI = try openAIFixtureDocuments()
        return HTTPStub(
            .json(openRouterModelList ?? String(decoding: documents.modelList, as: UTF8.self)),
            .json(String(decoding: documents.apiDescription, as: UTF8.self)),
            .json(String(decoding: openAI.modelList, as: UTF8.self)),
            .json(String(decoding: openAI.apiDescription, as: UTF8.self)),
            .json(String(decoding: openAI.servedModels ?? Data(), as: UTF8.self))
        )
    }

    /// Runs a subcommand against the stub and returns what it logged.
    @discardableResult
    private func run(
        _ action: Command.Action,
        stub: HTTPStub,
        base: String? = nil,
        sources: [CatalogSource] = [.openrouter, .openai]
    ) async throws -> [String] {
        let command = Command(action: action, packageDirectory: package, sources: sources, base: base)
        var log: [String] = []
        try await Generator.run(
            command, session: stub.session, baseURL: stub.baseURL, environment: ["OPENAI_API_KEY": "test-key"], today: "2026-10-29"
        ) { log.append($0) }
        return log
    }

    /// Runs git in the temporary package.
    private func git(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git", "-C", package.path(percentEncoded: false)] + arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " "))")
    }
}
