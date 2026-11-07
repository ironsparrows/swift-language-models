import Foundation
import FoundationModels
import LanguageModelsTestSupport
import UniformTypeIdentifiers

@testable import LanguageModels

/// A dialect that adds only what a test gives it, so the format's own behavior shows.
///
/// Its errors are the format's failures themselves, so a test can read what failed.
struct ResponsesTestDialect: ResponsesDialect {
    typealias Model = ResponsesTestModel
    typealias ProviderError = ResponsesFailure<ResponsesTestDialect>
    typealias BodyExtras = JSONValue

    let setup: ResponsesTestModel.Setup

    init(model: ResponsesTestModel, executor: ResponsesTestModel.RequestExecutor) {
        setup = model.setup
    }

    init(_ setup: ResponsesTestModel.Setup = ResponsesTestModel.Setup()) {
        self.setup = setup
    }

    static var name: String { "Test" }

    /// The members a test may leave out.
    static var listedMembers: Set<Responses.Member> { [.temperature, .maxOutputTokens, .topP] }

    var modelID: ResponsesTestModelID { "vendor/model" }

    var baseURL: URL { setup.url }

    var connection: ProviderConnection {
        ProviderConnection(
            session: setup.session, authentication: RequestAuthentication(baseURL: nil) { [:] }, idleTimeout: nil,
            retryPolicy: .exponentialBackoff(
                retries: 0, statuses: { _ in false }, delay: .zero, longestDelay: .zero, longestRetryAfter: .zero,
                retriedErrors: []))
    }

    var instructionsRole: InstructionsRole { setup.instructionsRole }

    func lists(_ member: Responses.Member) -> Bool { setup.lists(member) }

    func body(_ context: BodyContext) throws(LanguageModelError) -> ResponsesBodyPlan<JSONValue> {
        try setup.plan(context)
    }

    func error(for failure: ResponsesFailure<ResponsesTestDialect>) -> MappedError<ResponsesFailure<ResponsesTestDialect>> {
        .provider(failure)
    }
}

/// The id of the test model.
struct ResponsesTestModelID: ProviderVocabulary {
    let rawValue: String
}

/// A model whose requests go through the test dialect.
struct ResponsesTestModel: DetailedLanguageModel {
    /// What the test dialect adds to a request, and where it goes.
    struct Setup: Sendable {
        /// The provider's base URL, such as a stub's.
        var url = URL(fileURLWithPath: "/")

        /// The session that sends the requests.
        var session = URLSession.shared

        /// The dialect's plan for a request's body.
        var plan: @Sendable (BodyContext) throws(LanguageModelError) -> ResponsesBodyPlan<JSONValue> = { _ in ResponsesBodyPlan(extras: [:])
        }

        /// Whether the models list a member that goes out only when they do.
        var lists: @Sendable (Responses.Member) -> Bool = { _ in true }

        /// The role of the instructions' messages.
        var instructionsRole = InstructionsRole.developer
    }

    struct Details: ModelDetails {
        let id: ResponsesTestModelID = "vendor/model"
        let displayName = "Model"
        let capabilities = LanguageModelCapabilities([.guidedGeneration, .toolCalling, .reasoning])
        let reasoning = ModelReasoning.onByDefault
        let contextSize: Int? = 1_000
        let reasoningEfforts: [Efforts.Unsupported] = []
        let defaultReasoningEffort: Efforts.Unsupported? = nil
        let removalDate: Date? = nil
        let dataAttachmentTypes: Set<UTType> = [.image, .pdf, .rtf]
        let dataEntryTypes: Set<UTType> = []
    }

    struct RequestExecutor: DetailedLanguageModelRequestExecutor {
        struct Configuration: Hashable, Sendable {}

        init(configuration: Configuration) {}

        func execute(
            _ request: LanguageModelExecutorGenerationRequest,
            model: ResponsesTestModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws -> DetailedLanguageModelAnswer {
            try await respond(to: request, model: model, streamingInto: channel, as: ResponsesTestDialect.self)
        }
    }

    var setup = Setup()
    let details = Details()
    let fallbacks: [Details] = []

    var executorConfiguration: RequestExecutor.Configuration { .init() }
}

/// The input items of a request body.
func input(_ body: JSONValue) -> [JSONValue] {
    if case .array(let items)? = body["input"] { items } else { [] }
}

/// A streamed response made of the given events, each with its `type` as the event's name.
func events(_ events: JSONValue...) -> StubResponse {
    let lines = events.map { "event: \($0["type"]?.stringValue ?? "")\ndata: \($0.text)\n\n" }
    return .eventStream(Data(lines.joined().utf8))
}

/// A lifecycle event, such as `response.completed`, with the response's members.
func lifecycle(_ type: String, _ response: JSONValue = [:]) -> JSONValue {
    ["type": .string(type), "response": response]
}

/// A text delta of the message at an output index.
func textDelta(_ delta: String, at index: Int = 0) -> JSONValue {
    ["type": "response.output_text.delta", "output_index": .integer(index), "content_index": 0, "delta": .string(delta)]
}

/// The event that adds or ends an output item.
func item(_ type: String, at index: Int, _ item: JSONValue) -> JSONValue {
    ["type": .string(type), "output_index": .integer(index), "item": item]
}
