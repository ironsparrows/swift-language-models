import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import OpenAICompatibleLanguageModels
import Testing

// What every preset's live suite shares: the checks each runs on its provider, the trait that cancels a test the
// provider couldn't serve right now, the pause a free tier's limits need, and the gate of the local servers' suites.
//
// The remote suites run with their provider's key in the environment, such as `GEMINI_API_KEY`. The local servers'
// suites run only with `LIVE_LOCAL_SERVERS=1` in the environment and their server reachable, so a test run on a Mac with
// Ollama open stays offline unless it asks.

/// A limit for answers of a sentence or two.
let shortAnswer = GenerationOptions(maximumResponseTokens: 400)

/// Asks for the temperature in Lisbon, then in Porto on a later turn, so whatever the first answer sends back on later
/// turns, such as its reasoning or signatures, goes back once.
///
/// - Returns: The session after both answers, each of which used the tool's output.
func answerTwoTurnsWithTool(
    _ model: OpenAICompatibleLanguageModel,
    contextOptions: ContextOptions = ContextOptions(),
    options: GenerationOptions = GenerationOptions(maximumResponseTokens: 1_500)
) async throws -> LanguageModelSession {
    let session = LanguageModelSession(model: model, tools: [WeatherTool()])
    // A failed answer keeps what it wrote, so the attached transcript shows the turn that failed.
    session.transcriptErrorHandlingPolicy = .preserveTranscript
    let first: LanguageModelSession.Response<String>
    let second: LanguageModelSession.Response<String>
    do {
        first = try await session.respond(
            to: "What's the temperature in Lisbon? Use the tool.", options: options, contextOptions: contextOptions)
        second = try await session.respond(to: "And in Porto? Use the tool.", options: options, contextOptions: contextOptions)
    } catch {
        record(session.transcript, named: "failed-transcript.txt")
        throw error
    }
    #expect(first.content.contains("17"))
    #expect(second.content.contains("17"))
    #expect(Set(try session.transcript.weatherCities()).isSuperset(of: ["Lisbon", "Porto"]))
    return session
}

/// Sends two or three requests, each in a session of its own after the same long instructions, stopping at the first
/// after the first that reads any of them from the provider's cache. The instructions start with a new id, so no earlier
/// request cached them, though a server may read a few tokens of its own chat template from its cache.
///
/// - Parameters:
///   - model: The model to send them to.
///   - copies: Copies of a sentence of about ten tokens in the instructions.
///   - contextOptions: The requests' context options.
/// - Returns: Each request's input tokens, and how many of them it read from the cache.
/// - Throws: The error of a request that failed.
func cachedInputs(
    _ model: OpenAICompatibleLanguageModel,
    copies: Int,
    contextOptions: ContextOptions = ContextOptions()
) async throws -> [(cached: Int, input: Int)] {
    let instructions = "Run \(UUID().uuidString). " + String(repeating: "Answer in one short sentence, and stay polite. ", count: copies)
    var inputs: [(cached: Int, input: Int)] = []
    for attempt in 1...3 {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: "Say hello.", options: GenerationOptions(maximumResponseTokens: 300), contextOptions: contextOptions)
        inputs.append((response.usage.input.cachedTokenCount, response.usage.input.totalTokenCount))
        if attempt > 1, response.usage.input.cachedTokenCount > 0 { break }
        if attempt < 3 { try await Task.sleep(for: .seconds(2)) }
    }
    record(inputs, named: "cached.txt")
    return inputs
}

/// Why a provider couldn't serve a request right now, when that, rather than the request, made it fail: a rate limit,
/// a timeout, or the provider failing or overloaded.
private func isUnavailable(_ error: any Error) -> Bool {
    switch error {
    case let error as LanguageModelError:
        switch error {
        case .rateLimited, .timeout: true
        default: false
        }
    case let error as OpenAICompatibleError:
        error.status.map { [500, 502, 503, 504].contains($0) } == true
    default:
        false
    }
}

/// A trait that cancels a test when its provider couldn't serve it right now, attaching the error, instead of failing it.
struct SkipsUnavailableProvider: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    // Testing declares the requirement without nonisolated(nonsending), so both the method and its closure run
    // concurrently.
    @concurrent func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable @concurrent () async throws -> Void
    ) async throws {
        do {
            try await function()
        } catch {
            guard isUnavailable(error) else { throw error }
            Attachment.record(String(reflecting: error), named: "unavailable-error.txt")
            try Test.cancel("The provider was briefly unavailable: \(error)")
        }
    }
}

/// A trait that waits before each test, for a free tier that allows few requests a minute.
struct Paced: TestTrait, SuiteTrait, TestScoping {
    /// How long to wait before each test.
    let interval: Duration

    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    @concurrent func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable @concurrent () async throws -> Void
    ) async throws {
        try await Task.sleep(for: interval)
        try await function()
    }
}

extension Trait where Self == SkipsUnavailableProvider {
    /// Cancels a test when its provider couldn't serve it right now, instead of failing it.
    static var skipsUnavailableProvider: Self { Self() }
}

extension Trait where Self == Paced {
    /// Waits before each test, for a free tier that allows few requests a minute.
    static func paced(_ interval: Duration) -> Self { Self(interval: interval) }
}

// MARK: - Local servers

/// A server on this Mac or nearby that a local suite runs against.
enum LocalServer {
    /// Whether the environment asks for the local servers' live tests, with `LIVE_LOCAL_SERVERS=1`.
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["LIVE_LOCAL_SERVERS"] == "1"
    }

    /// The ids of the models a server lists, or `nil` when it doesn't answer within two seconds.
    static func models(at url: URL) async -> [String]? {
        var request = URLRequest(url: url.appending(path: "models"), timeoutInterval: 2)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let list = try? JSONDecoder().decode(ModelList.self, from: data)
        else { return nil }
        return list.data.map(\.id)
    }

    /// Whether the local suites were asked for and the server lists every one of the models.
    static func isReady(at url: URL, with models: [String] = []) async -> Bool {
        guard isRequested, let listed = await self.models(at: url) else { return false }
        return models.allSatisfy(listed.contains) && !listed.isEmpty
    }

    /// The first model a server lists that isn't an embedding model.
    static func firstModel(at url: URL) async throws -> String {
        let model = await models(at: url)?.first { !$0.localizedCaseInsensitiveContains("embed") }
        return try #require(model, "The server at \(url) lists no model that answers prompts.")
    }

    private struct ModelList: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }
}

extension Trait where Self == ConditionTrait {
    /// Runs the suite only when the environment asks for the local servers' live tests.
    static var requiresLocalServersRequested: Self {
        .enabled(if: LocalServer.isRequested, "Set LIVE_LOCAL_SERVERS=1 to run the local servers' live tests")
    }
}
