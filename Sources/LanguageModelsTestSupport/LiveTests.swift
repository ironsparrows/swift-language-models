import Foundation
package import FoundationModels
package import Testing

// MARK: - Live fixtures

// What every provider's live tests share: tools whose answers a model can't know, a plan with the schema features
// providers differ on, and readers of a session's transcript.

/// A tool whose answer the model can't know, so an answer with it shows the tool ran.
package struct WeatherTool: Tool {
    package init() {}

    package let name = "getWeather"
    package let description = "Gets the current temperature in a city, in degrees Celsius."

    @Generable
    package struct Arguments {
        @Guide(description: "The city's name.")
        package var city: String
    }

    package func call(arguments: Arguments) async throws -> String {
        "It is 17 degrees in \(arguments.city)."
    }
}

/// A plan with the schema features providers differ on: a nested type, an enum, an exact count, ranges and an
/// optional property.
@Generable
package struct Trip {
    @Guide(description: "The city to visit.")
    package var city: String

    package var season: Season

    @Guide(description: "Three things to do.", .count(3))
    package var activities: [Activity]

    @Guide(description: "How many days to stay.", .range(1...14))
    package var days: Int

    package var note: String?
}

@Generable
package enum Season {
    case spring, summer, autumn, winter
}

@Generable
package struct Activity {
    package var name: String

    @Guide(description: "How many hours it takes.", .range(1...12))
    package var hours: Int
}

extension Transcript {
    /// Every tool call in the transcript, in order.
    package var toolCalls: [Transcript.ToolCall] {
        flatMap { entry -> [Transcript.ToolCall] in
            if case .toolCalls(let calls) = entry { Array(calls) } else { [] }
        }
    }

    /// The cities of every weather tool call in the transcript, in order.
    package func weatherCities() throws -> [String] {
        try toolCalls.filter { $0.toolName == "getWeather" }.map { try $0.arguments.value(String.self, forProperty: "city") }
    }
}

/// The last answer among the entries.
package func lastAnswer(in entries: some Sequence<Transcript.Entry>) -> Transcript.Response? {
    entries.compactMap { entry in if case .response(let answer) = entry { answer } else { nil } }.last
}

/// The reasoning entries among the entries, in order.
package func reasoningEntries(in entries: some Sequence<Transcript.Entry>) -> [Transcript.Reasoning] {
    entries.compactMap { entry in if case .reasoning(let reasoning) = entry { reasoning } else { nil } }
}

/// Attaches a value to the test's results, for reading what a provider returned.
package func record(_ value: Any, named name: String) {
    Attachment.record(String(describing: value), named: name)
}

/// A weather tool that ends the answer with ``ToolCallInterruption`` when it's called, so a test sees the first call
/// and no more.
package struct InterruptingWeatherTool: Tool {
    package init() {}

    package let name = "getWeather"
    package let description = "Gets the current temperature in a city, in degrees Celsius."

    @Generable
    package struct Arguments {
        @Guide(description: "The city's name.")
        package var city: String
    }

    package func call(arguments: Arguments) async throws -> String {
        throw ToolCallInterruption()
    }
}

/// The error that ``InterruptingWeatherTool`` throws.
package struct ToolCallInterruption: Error {
    package init() {}
}

/// Sends a prompt and stops at the first call of an ``InterruptingWeatherTool``, since a required tool choice stays on
/// for every round, and a model that honors it never stops calling tools.
///
/// The session keeps the transcript of the answer that the tool ended, so a test can read the call; by default a
/// failed answer is reverted.
///
/// - Returns: The response, or `nil` when the model called the tool.
package func respondUntilToolCall(
    _ session: LanguageModelSession,
    to prompt: String,
    options: GenerationOptions
) async throws -> LanguageModelSession.Response<String>? {
    session.transcriptErrorHandlingPolicy = .preserveTranscript
    do {
        return try await session.respond(to: prompt, options: options)
    } catch let error as LanguageModelSession.ToolCallError where error.underlyingError is ToolCallInterruption {
        return nil
    }
}

// MARK: - API key trait

/// A trait that runs a test only when an environment variable holds an API key, and binds that key to
/// ``current`` while the test runs.
package struct APIKeyTrait: TestTrait, SuiteTrait, TestScoping {
    /// The key that the trait read for the running test, or `nil` outside such a test.
    ///
    /// Read it while the test runs, for example when building a model, and capture the value: Foundation Models may
    /// call a model's key closure from a task of its own, where this value isn't bound.
    @TaskLocal package static var current: String?

    /// The environment variable that holds the key, such as `OPENROUTER_API_KEY`.
    let variable: String

    package var isRecursive: Bool { true }

    /// The key, or `nil` when the variable is missing or empty.
    private var key: String? {
        ProcessInfo.processInfo.environment[variable].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Why a test without the key doesn't run.
    private var missingKeyReason: Comment { "Set \(variable) to run this test" }

    package func prepare(for test: Test) async throws {
        // A condition trait's skip, so a suite without the key shows as skipped rather than as cancelled tests.
        try await ConditionTrait.enabled(if: key != nil, missingKeyReason).prepare(for: test)
    }

    package func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    // Testing declares the requirement without nonisolated(nonsending), so both the method and its closure run
    // concurrently.
    @concurrent package func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable @concurrent () async throws -> Void
    ) async throws {
        guard let key else { try Test.cancel(missingKeyReason) }
        try await Self.$current.withValue(key) { try await function() }
    }
}

extension Trait where Self == APIKeyTrait {
    /// Runs the test only when an environment variable holds an API key, with the key in ``APIKeyTrait/current``.
    ///
    /// - Parameter variable: The environment variable, such as `OPENROUTER_API_KEY`.
    /// - Returns: A trait that skips the test when the variable is missing or empty.
    package static func requiresAPIKey(_ variable: String) -> Self {
        Self(variable: variable)
    }
}

// MARK: - Tags

extension Tag {
    /// Tests that call a provider's live API.
    @Tag package static var live: Self

    /// Tests that sweep many of a provider's models through its live API, which run only when asked for.
    @Tag package static var liveSweep: Self
}
