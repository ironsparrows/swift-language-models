import Foundation

/// What the generator was asked to do.
struct Command: Equatable {
    /// The generator's subcommands.
    enum Action: String, CaseIterable {
        case fetch
        case render
        case check
        case diff
        case clearRemoved = "clear-removed"

        /// What the subcommand does, for the usage text.
        var summary: String {
            switch self {
            case .fetch: "Download the providers' model lists into Catalogs/."
            case .render: "Turn the catalogs into Swift sources."
            case .check: "Exit with code 1 when the Swift sources don't match the catalogs."
            case .diff: "Write the catalogs' changes since --base, and the release they need, to .build/catalog/."
            case .clearRemoved: "Drop what the catalogs mark removed, for a major release. Run render after it."
            }
        }
    }

    static let usage = """
        USAGE: ModelCatalogGenerator <\(Action.allCases.map(\.rawValue).joined(separator: " | "))> [options]

        SUBCOMMANDS:
        \(Action.allCases.map { "  \($0.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0))\($0.summary)" }.joined(separator: "\n"))

        OPTIONS:
          --base <git-ref>             The version to compare the catalogs with, for diff.
          --package-directory <path>   The package root (default: the current directory).
          --sources <names>            Comma-separated sources to fetch or clear (default: all). Sources: \
        \(CatalogSource.allCases.map(\.rawValue).joined(separator: ", ")).
          -h, --help                   Show this help.
        """

    let action: Action
    let packageDirectory: URL
    let sources: [CatalogSource]
    /// The git ref that `diff` compares the catalogs with.
    let base: String?

    init(action: Action, packageDirectory: URL, sources: [CatalogSource], base: String? = nil) {
        self.action = action
        self.packageDirectory = packageDirectory
        self.sources = sources
        self.base = base
    }

    /// Parses the arguments after the executable name.
    ///
    /// - Parameters:
    ///   - arguments: The command-line arguments, without the executable name.
    ///   - currentDirectory: The directory used when `--package-directory` is missing.
    /// - Returns: The command, or `nil` when help was requested.
    /// - Throws: ``GeneratorError/usage(_:)`` for arguments the generator doesn't accept.
    static func parse(_ arguments: [String], currentDirectory: URL) throws(GeneratorError) -> Command? {
        guard !arguments.contains(where: { $0 == "--help" || $0 == "-h" }) else { return nil }
        guard let first = arguments.first else { throw .usage("Missing subcommand.") }
        guard let action = Action(rawValue: first) else { throw .usage("Unknown subcommand '\(first)'.") }

        var packageDirectory = currentDirectory
        var sources = CatalogSource.allCases
        var base: String?
        var remaining = arguments.dropFirst()
        while let option = remaining.popFirst() {
            guard let value = remaining.popFirst() else { throw .usage("Missing value for '\(option)'.") }
            switch option {
            case "--package-directory":
                packageDirectory = URL(filePath: value, directoryHint: .isDirectory, relativeTo: currentDirectory)
            case "--sources":
                sources = try value.split(separator: ",").map { name throws(GeneratorError) in
                    guard let source = CatalogSource(rawValue: String(name)) else {
                        throw .usage("Unknown source '\(name)'.")
                    }
                    return source
                }
                guard !sources.isEmpty else { throw .usage("'--sources' names no source.") }
            case "--base" where action == .diff:
                base = value
            default:
                throw .usage("Unknown option '\(option)'.")
            }
        }
        if action == .diff, base == nil { throw .usage("'diff' needs '--base <git-ref>'.") }
        return Command(action: action, packageDirectory: packageDirectory.standardizedFileURL, sources: sources, base: base)
    }
}
