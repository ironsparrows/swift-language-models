import Foundation
public import FoundationModels
#if canImport(FoundationModels, _version: 2.1.14)
public import UniformTypeIdentifiers
#endif

// MARK: - Model

/// What ``DetailedLanguageModelExecutor`` reads from a model before each request: its details and its fallbacks.
///
/// A provider module's model conforms to ``DetailedLanguageModel``, which refines this protocol. This protocol exists
/// so that a request executor's model has a type the executor can read, since ``DetailedLanguageModel`` names the
/// executor itself.
public protocol DetailedLanguageModelBase: LanguageModel {
    /// The type that describes the model.
    associatedtype Details: ModelDetails

    /// The type that describes the models the provider tries when this one fails.
    associatedtype Fallback: ModelDetails

    /// What the provider reports about this model.
    var details: Details { get }

    /// The models the provider tries, in order, when this one fails. Empty when the provider has no fallbacks.
    var fallbacks: [Fallback] { get }
}

/// A language model that carries what its provider reports about it.
///
/// The model's capabilities, and the kinds of data it accepts and generates, come from its details. Its executor is a
/// ``DetailedLanguageModelExecutor`` of the provider module's ``RequestExecutor``, which checks each request before the
/// request executor sends it, and each answer after.
public protocol DetailedLanguageModel: DetailedLanguageModelBase
where Executor == DetailedLanguageModelExecutor<RequestExecutor> {
    /// The type that sends the model's requests.
    associatedtype RequestExecutor: DetailedLanguageModelRequestExecutor where RequestExecutor.Model == Self
}

// MARK: - Details and capabilities

extension DetailedLanguageModel {
    /// The capabilities that the model's details and each of its fallbacks' list, since any of them may answer.
    ///
    /// A model without fallbacks has its details' capabilities. With fallbacks, only tool calling, guided
    /// generation, reasoning and vision can be kept, the capabilities Foundation Models names.
    public var capabilities: LanguageModelCapabilities {
        guard !fallbacks.isEmpty else { return details.capabilities }
        let named: [LanguageModelCapabilities.Capability] = [.toolCalling, .guidedGeneration, .reasoning, .vision]
        return LanguageModelCapabilities(
            named.filter { capability in
                details.capabilities.contains(capability) && fallbacks.allSatisfy { $0.capabilities.contains(capability) }
            }
        )
    }
}

// FoundationModels 2.1.14 comes with Xcode 27.2, the first SDK with data attachments and data entries.
#if canImport(FoundationModels, _version: 2.1.14)
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
extension DetailedLanguageModel {
    /// Whether the details of the model and of each of its fallbacks list the kind of data as a prompt attachment
    /// they accept.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the kind conforms to one of the `dataAttachmentTypes` of every model a request may reach.
    /// - Throws: Nothing; the method throws only because Foundation Models declares it so.
    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        details.supportsDataAttachmentType(type) && fallbacks.allSatisfy { $0.supportsDataAttachmentType(type) }
    }

    /// Whether the details of the model and of each of its fallbacks list the kind of data as one they generate.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the kind conforms to one of the `dataEntryTypes` of every model a request may reach.
    /// - Throws: Nothing; the method throws only because Foundation Models declares it so.
    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        details.supportsDataEntryType(type) && fallbacks.allSatisfy { $0.supportsDataEntryType(type) }
    }
}
#endif

// MARK: - Executor

/// The executor of every ``DetailedLanguageModel``, which checks each request before the model's request executor
/// sends it, and each answer after.
///
/// Foundation Models creates the executor from the model's `executorConfiguration` and calls it for each answer. For
/// each model the request may reach, the model and then its fallbacks, whose ``ModelDetails/removalDate`` is set, the
/// executor logs an error and, in a debug build, shows a runtime warning, since the provider no longer lists that
/// model and the request may fail. Then it calls the request executor's
/// ``DetailedLanguageModelRequestExecutor/execute(_:model:streamingInto:)``.
///
/// For a request with a schema, the executor checks the answer against the schema's guides, such as a range or a
/// count, since a host may drop or ignore those constraints, and throws `GeneratedContent.ParsingError` when a value
/// breaks one, as Foundation Models does for an answer that doesn't decode.
///
/// A provider module writes only the request executor. ``DetailedLanguageModel`` requires this executor, so no
/// provider module can leave the checks out.
public struct DetailedLanguageModelExecutor<RequestExecutor: DetailedLanguageModelRequestExecutor>: LanguageModelExecutor {
    /// The model the executor answers with.
    public typealias Model = RequestExecutor.Model

    /// What the request executor needs to send requests.
    public typealias Configuration = RequestExecutor.Configuration

    private let requestExecutor: RequestExecutor

    /// Creates an executor and its request executor.
    ///
    /// - Parameter configuration: What the request executor needs to send requests.
    /// - Throws: What the request executor's initializer throws.
    public init(configuration: Configuration) throws {
        requestExecutor = try RequestExecutor(configuration: configuration)
    }

    /// Reports each model the request may reach that its provider stopped listing, sends the request, and checks the
    /// answer against the schema's guides.
    ///
    /// - Parameters:
    ///   - request: The transcript, tools, schema and options to send.
    ///   - model: The model to answer with.
    ///   - channel: Where the answer's events go.
    /// - Throws: What the request executor throws, and `GeneratedContent.ParsingError` when a value of the answer
    ///   breaks a guide of the request's schema.
    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        model.removedModels.report(for: request)
        let answer = try await requestExecutor.execute(request, model: model, streamingInto: channel)
        if let schema = request.schema {
            try GuideViolations.check(answer.responseText, against: schema, request: request.id)
        }
    }
}

/// Sends a provider's requests: the part of a ``DetailedLanguageModel``'s executor that a provider module writes.
///
/// The model's executor is always a ``DetailedLanguageModelExecutor`` of its request executor, which this module owns.
/// Foundation Models calls the executor, which checks each request before it calls
/// ``execute(_:model:streamingInto:)``, and the answer it returns, so every provider module gets the same checks.
public protocol DetailedLanguageModelRequestExecutor: Sendable {
    /// What the request executor needs to send requests, such as a base URL. It holds no secrets: keep those, such as
    /// an API key closure, on the model.
    associatedtype Configuration: Hashable, Sendable

    /// The model the request executor sends requests for, a ``DetailedLanguageModel`` whose
    /// ``DetailedLanguageModel/RequestExecutor`` is this type.
    associatedtype Model: DetailedLanguageModelBase

    /// Creates a request executor, which the model's executor does from the model's `executorConfiguration`.
    ///
    /// - Parameter configuration: What the request executor needs to send requests.
    /// - Throws: An error when the configuration can't send requests.
    init(configuration: Configuration) throws

    /// Sends one request to the provider and streams its answer.
    ///
    /// - Parameters:
    ///   - request: The transcript, tools, schema and options to send.
    ///   - model: The model to answer with.
    ///   - channel: Where the answer's events go.
    /// - Returns: The answer's response text, which the model's executor checks against the request's schema, or empty
    ///   text when the answer ends in tool calls.
    /// - Throws: `LanguageModelError` for failures Foundation Models has a case for, and an error of the provider
    ///   module's own for the rest.
    func execute(
        _ request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws -> DetailedLanguageModelAnswer
}

/// What a request executor reports of an answer it streamed, which the model's executor checks.
///
/// ``DetailedLanguageModelRequestExecutor/execute(_:model:streamingInto:)`` returns it once the answer's events are
/// sent. For a request with a schema, ``DetailedLanguageModelExecutor`` checks the response's text against the
/// schema's guides, since a host may drop or ignore constraints such as a guide's minimum.
public struct DetailedLanguageModelAnswer: Sendable {
    /// The text of the answer's response entry, as the request executor sent it, or empty when the answer ended in
    /// tool calls.
    public var responseText: String

    /// Creates the report of an answer.
    ///
    /// - Parameter responseText: The text of the answer's response entry, as the request executor sent it, or empty
    ///   when the answer ended in tool calls.
    public init(responseText: String) {
        self.responseText = responseText
    }
}
