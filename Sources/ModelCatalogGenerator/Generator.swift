import Foundation

// MARK: - Generator

/// The `ModelCatalogGenerator` command-line tool.
@main
enum Generator {
    /// What a fetch got from one source, before anything is written.
    private struct Fetch {
        let snapshot: CatalogSnapshot
        let schema: CatalogSchema
        let previousSchema: CatalogSchema?
        /// The ids of the model list's entries that don't decode, which the fetch skipped.
        let skippedEntryIDs: [String]
    }

    static func main() async {
        do {
            let currentDirectory = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
            guard let command = try Command.parse(Array(CommandLine.arguments.dropFirst()), currentDirectory: currentDirectory)
            else {
                print(Command.usage)
                return
            }
            try await run(command)
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("error: \(error)\n".utf8))
            exit(error.exitCode)
        }
    }

    /// Runs one subcommand.
    ///
    /// - Parameters:
    ///   - command: The parsed command.
    ///   - session: The session for `fetch`.
    ///   - baseURL: Where every source's documents live, replacing each source's own addresses.
    ///   - environment: The environment variables, which hold the API keys some sources' model lists need.
    ///   - today: The day recorded for removed models.
    ///   - log: Where progress messages go.
    /// - Throws: The ``GeneratorError`` that ended the run.
    static func run(
        _ command: Command,
        session: URLSession = URLSession(configuration: .ephemeral),
        baseURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        today: CatalogDay = CatalogDay(containing: .now),
        log: (String) -> Void = { print($0) }
    ) async throws(GeneratorError) {
        let packageDirectory = command.packageDirectory
        switch command.action {
        case .fetch:
            try await fetch(
                command.sources, into: packageDirectory, session: session, baseURL: baseURL, environment: environment, today: today,
                log: log)
        case .render:
            var changed = false
            for file in try generatedFiles(in: packageDirectory) {
                guard try write(file, in: packageDirectory) else { continue }
                log("Rendered \(file.path).")
                changed = true
            }
            if !changed { log("Generated files are up to date.") }
        case .check:
            let stale = try generatedFiles(in: packageDirectory).filter { file in
                (try? String(contentsOf: packageDirectory.appending(path: file.path), encoding: .utf8)) != file.contents
            }
            guard stale.isEmpty else { throw .stale(stale.map(\.path)) }
            log("Generated files match the catalogs.")
        case .diff:
            let base = try Generator.GitRevision(command.base ?? "HEAD", in: packageDirectory)
            let changes = try changes(since: base, in: packageDirectory)
            _ = try write(GeneratedFile(path: changelogPath, contents: changes.changelog), in: packageDirectory)
            _ = try write(GeneratedFile(path: reportPath, contents: try CatalogJSON.encoded(Report(changes))), in: packageDirectory)
            let release = changes.bump == .none ? "no release" : "a \(changes.bump.rawValue) release"
            log("The catalogs' changes since \(base.ref) need \(release). See \(changelogPath).")
        }
    }

    /// The Markdown changelog that `diff` writes, relative to the package root.
    static let changelogPath = ".build/catalog/CHANGELOG.md"

    /// The JSON report that `diff` writes, relative to the package root.
    static let reportPath = ".build/catalog/report.json"

    /// What `diff` reports to a workflow: the release, and each source's changes.
    struct Report: Codable, Equatable {
        let bump: CatalogChanges.Bump
        let sources: [CatalogChanges]

        init(_ changes: [CatalogChanges]) {
            bump = changes.bump
            sources = changes
        }
    }

    /// Each source's changes between a revision and the package's files.
    private static func changes(since base: Generator.GitRevision, in packageDirectory: URL) throws(GeneratorError) -> [CatalogChanges] {
        func atBase<Value: Decodable>(_ type: Value.Type, _ path: String) throws(GeneratorError) -> Value? {
            guard let data = try base.contents(of: path) else { return nil }
            return try CatalogJSON.decode(type, from: data, path: "\(path) at \(base.ref)")
        }
        var changes: [CatalogChanges] = []
        for source in CatalogSource.allCases {
            guard let snapshot = try CatalogJSON.read(CatalogSnapshot.self, at: source.snapshotPath, in: packageDirectory) else {
                continue
            }
            changes.append(
                CatalogChanges(
                    from: try atBase(CatalogSnapshot.self, source.snapshotPath),
                    to: snapshot,
                    oldSchema: try atBase(CatalogSchema.self, source.schemaPath),
                    newSchema: try CatalogJSON.read(CatalogSchema.self, at: source.schemaPath, in: packageDirectory)
                )
            )
        }
        return changes
    }

    /// Updates the sources' snapshots and schemas, and reports how each source's API changed shape.
    ///
    /// Each source is fetched on its own, so one that fails or looks broken doesn't hold back the others: the run
    /// writes the sources that succeeded, then fails naming the others, whose files stay as they were. The new
    /// snapshots are rendered in memory first, with the package's snapshots of the sources that failed, so nothing is
    /// written unless every file can be made and the models can become code.
    ///
    /// - Throws: ``GeneratorError/brokenSource(_:)`` with each failed source's problem, after the others are written.
    private static func fetch(
        _ sources: [CatalogSource],
        into packageDirectory: URL,
        session: URLSession,
        baseURL: URL?,
        environment: [String: String],
        today: CatalogDay,
        log: (String) -> Void
    ) async throws(GeneratorError) {
        var fetches: [Fetch] = []
        var failures: [(source: CatalogSource, problem: String)] = []
        for source in sources {
            do {
                fetches.append(
                    try await fetch(
                        source, into: packageDirectory, session: session, baseURL: baseURL, environment: environment, today: today)
                )
            } catch .brokenSource(let problem) {
                failures.append((source, problem))
            }
        }
        if !fetches.isEmpty {
            let snapshots = try merged(fetches, in: packageDirectory)
            _ = try asBrokenSource { () throws(GeneratorError) in try CatalogRenderer.files(for: snapshots) }
            for file in try catalogFiles(of: fetches) {
                _ = try write(file, in: packageDirectory)
            }
            report(fetches, log: log)
        }
        guard failures.isEmpty else {
            let names = failures.map(\.source.displayName).joined(separator: ", ")
            let option = "--sources \(failures.map(\.source.rawValue).joined(separator: ","))"
            let summary = "These sources weren't updated: \(names). Fetch them again with `\(option)`."
            throw .brokenSource((failures.map(\.problem) + [summary]).joined(separator: "\n"))
        }
    }

    /// Downloads one source's documents and updates its snapshot, without writing anything.
    private static func fetch(
        _ source: CatalogSource,
        into packageDirectory: URL,
        session: URLSession,
        baseURL: URL?,
        environment: [String: String],
        today: CatalogDay
    ) async throws(GeneratorError) -> Fetch {
        let documents = try await source.documents(using: session, baseURL: baseURL, environment: environment)
        let catalog = try source.catalog(from: documents, today: today)
        let previous = try CatalogJSON.read(CatalogSnapshot.self, at: source.snapshotPath, in: packageDirectory)
        let snapshot = try asBrokenSource { () throws(GeneratorError) in
            try CatalogSnapshot.updated(source: source, fetched: catalog, previous: previous, today: today)
        }
        return Fetch(
            snapshot: snapshot,
            schema: try source.schema(of: documents),
            previousSchema: try CatalogJSON.read(CatalogSchema.self, at: source.schemaPath, in: packageDirectory),
            skippedEntryIDs: catalog.skippedEntryIDs
        )
    }

    /// Every source's snapshot: the fetched one where there is one, and otherwise the one in the package, if any.
    private static func merged(_ fetches: [Fetch], in packageDirectory: URL) throws(GeneratorError) -> [CatalogSnapshot] {
        var snapshots: [CatalogSnapshot] = []
        for source in CatalogSource.allCases {
            if let fetch = fetches.first(where: { $0.snapshot.source == source }) {
                snapshots.append(fetch.snapshot)
            } else if let snapshot = try CatalogJSON.read(CatalogSnapshot.self, at: source.snapshotPath, in: packageDirectory) {
                snapshots.append(snapshot)
            }
        }
        return snapshots
    }

    /// The snapshot and schema files of the fetched sources.
    private static func catalogFiles(of fetches: [Fetch]) throws(GeneratorError) -> [GeneratedFile] {
        var files: [GeneratedFile] = []
        for fetch in fetches {
            let source = fetch.snapshot.source
            files.append(GeneratedFile(path: source.snapshotPath, contents: try CatalogJSON.encoded(fetch.snapshot)))
            files.append(GeneratedFile(path: source.schemaPath, contents: try CatalogJSON.encoded(fetch.schema)))
        }
        return files
    }

    /// Logs how many models each source has, the model list's entries it skipped, and how its API changed shape since
    /// the previous fetch.
    private static func report(_ fetches: [Fetch], log: (String) -> Void) {
        for fetch in fetches {
            let source = fetch.snapshot.source
            log("Fetched \(fetch.snapshot.models.count) \(source.displayName) models into \(source.snapshotPath).")
            if !fetch.skippedEntryIDs.isEmpty {
                let ids = fetch.skippedEntryIDs.joined(separator: ", ")
                log("Skipped the entries of \(source.displayName)'s model list that don't decode: \(ids).")
            }
            let changes = fetch.previousSchema.map(fetch.schema.changes(since:)) ?? []
            if !changes.isEmpty {
                log("\(source.displayName)'s API changed shape:")
                for change in changes { log("  \(change)") }
            }
        }
    }

    /// Runs a step on fetched data, so data that can't become code fails the fetch as a broken source.
    private static func asBrokenSource<Value>(_ step: () throws(GeneratorError) -> Value) throws(GeneratorError) -> Value {
        do {
            return try step()
        } catch .invalidCatalog(let message) {
            throw .brokenSource("The fetched models can't become code: \(message)")
        }
    }

    /// The generated files for every source's snapshot.
    ///
    /// - Throws: ``GeneratorError/fileAccess(_:)`` when a source has no snapshot yet.
    private static func generatedFiles(in packageDirectory: URL) throws(GeneratorError) -> [GeneratedFile] {
        let snapshots = try CatalogSource.allCases.map { (source) throws(GeneratorError) in
            guard let snapshot = try CatalogJSON.read(CatalogSnapshot.self, at: source.snapshotPath, in: packageDirectory) else {
                throw .fileAccess("\(source.snapshotPath) is missing. Run `fetch` to create it.")
            }
            return snapshot
        }
        return try CatalogRenderer.files(for: snapshots)
    }

    /// Writes a file unless it already holds the contents, so an unchanged file keeps its modification date.
    ///
    /// - Returns: Whether the file changed.
    private static func write(_ file: GeneratedFile, in packageDirectory: URL) throws(GeneratorError) -> Bool {
        let url = packageDirectory.appending(path: file.path)
        let data = Data(file.contents.utf8)
        guard (try? Data(contentsOf: url)) != data else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw .fileAccess("Couldn't write \(file.path): \(error.localizedDescription)")
        }
        return true
    }
}

// MARK: - Git revision

extension Generator {
    /// The package's files as a git commit has them.
    struct GitRevision {
        let ref: String
        let packageDirectory: URL

        /// A revision of the package's repository.
        ///
        /// - Throws: ``GeneratorError/usage(_:)`` when `ref` names no commit, and ``GeneratorError/fileAccess(_:)``
        ///   when git can't run.
        init(_ ref: String, in packageDirectory: URL) throws(GeneratorError) {
            self.ref = ref
            self.packageDirectory = packageDirectory
            guard try git("rev-parse", "--verify", "--quiet", "\(ref)^{commit}").status == 0 else {
                throw .usage("'\(ref)' names no commit of the repository at \(packageDirectory.path(percentEncoded: false)).")
            }
        }

        /// A file's contents at the revision.
        ///
        /// - Parameter path: The file, relative to the package root.
        /// - Returns: The contents, or `nil` when the revision has no such file.
        /// - Throws: ``GeneratorError/fileAccess(_:)`` when git can't run or can't read the file.
        func contents(of path: String) throws(GeneratorError) -> Data? {
            guard try git("cat-file", "-e", "\(ref):./\(path)").status == 0 else { return nil }
            let show = try git("show", "\(ref):./\(path)")
            guard show.status == 0 else { throw .fileAccess("Couldn't read \(path) at \(ref).") }
            return show.output
        }

        /// Runs git in the package directory and returns its exit status and standard output.
        private func git(_ arguments: String...) throws(GeneratorError) -> (status: Int32, output: Data) {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = ["git", "-C", packageDirectory.path(percentEncoded: false)] + arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw .fileAccess("Couldn't run git: \(error.localizedDescription)")
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, data)
        }
    }
}

// MARK: - Errors

/// A failure that ends a generator run.
enum GeneratorError: Error, Equatable, CustomStringConvertible {
    /// The command line couldn't be parsed.
    case usage(String)

    /// A source failed or returned data that looks broken, so nothing was written.
    case brokenSource(String)

    /// The generated files differ from the ones in the package.
    case stale([String])

    /// The catalogs can't become code, for example because two words get the same Swift name, or a catalog file
    /// doesn't decode.
    case invalidCatalog(String)

    /// A file in the package is missing, or couldn't be read or written.
    case fileAccess(String)

    /// The process exit code for the failure.
    var exitCode: Int32 {
        switch self {
        case .usage: 64
        case .brokenSource: 2
        case .stale: 1
        case .invalidCatalog: 65
        case .fileAccess: 74
        }
    }

    var description: String {
        switch self {
        case .usage(let message): "\(message)\n\n\(Command.usage)"
        case .stale(let paths): "Generated files are out of date: \(paths.joined(separator: ", ")). Run `render`."
        case .brokenSource(let message), .invalidCatalog(let message), .fileAccess(let message): message
        }
    }
}
