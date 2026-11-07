import Foundation
import PackagePlugin

/// Downloads the providers' model lists and regenerates the typed model data, by running `ModelCatalogGenerator`'s
/// `fetch` and then `render`.
@main
struct GenerateModelCatalog: CommandPlugin {
    /// `ModelCatalogGenerator` exited with an error, which it already printed.
    private struct Failure: Error, CustomStringConvertible {
        let arguments: [String]
        let status: Int32

        var description: String {
            "ModelCatalogGenerator \(arguments.first ?? "") exited with status \(status)."
        }
    }

    /// The environment variables the generator gets: the home and temporary folders, the proxy that reaches the
    /// providers, and the API key OpenAI's model list needs. Every other variable, such as an unrelated secret, stays out
    /// of its process.
    private static let environmentVariables: Set<String> = [
        "HOME", "TMPDIR", "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy", "OPENAI_API_KEY",
    ]

    /// Runs `fetch` with the command's arguments and then `render`, or shows the generator's help for `--help` or `-h`.
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "ModelCatalogGenerator")
        guard !arguments.contains("--help"), !arguments.contains("-h") else {
            try await run(tool, ["--help"])
            return
        }
        let packageDirectory = ["--package-directory", context.package.directoryURL.path(percentEncoded: false)]
        try await run(tool, ["fetch"] + packageDirectory + arguments)
        try await run(tool, ["render"] + packageDirectory)
    }

    /// Runs the generator and waits for it to exit without blocking a thread.
    ///
    /// - Throws: The error that kept the process from starting, or ``Failure`` when it exits with an error.
    private func run(_ tool: PluginContext.Tool, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = tool.url
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.filter { Self.environmentVariables.contains($0.key) }
        let (reason, status) = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: (process.terminationReason, process.terminationStatus))
            }
            do {
                try process.run()
            } catch {
                // A process that never started never terminates, so its handler can't resume the continuation too.
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard reason == .exit, status == 0 else {
            throw Failure(arguments: arguments, status: status)
        }
    }
}
