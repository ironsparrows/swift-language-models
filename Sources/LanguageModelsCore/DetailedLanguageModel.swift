import Foundation
public import FoundationModels
#if canImport(FoundationModels, _version: 2.1.14)
public import UniformTypeIdentifiers
#endif

// MARK: - Model

/// A language model that carries what its provider reports about it.
///
/// The model's capabilities, and the kinds of data it accepts and generates, come from its details. Its executor is the
/// provider module's own. In a provider module of your own, the executor calls ``reportRemovedModels(for:)`` before it
/// sends a request and ``checkGuides(ofResponseText:for:)`` once the answer is over.
public protocol DetailedLanguageModel: LanguageModel {
    /// The type that describes the model.
    associatedtype Details: ModelDetails

    /// The type that describes the models the provider tries when this one fails.
    associatedtype Fallback: ModelDetails

    /// What the provider reports about this model.
    var details: Details { get }

    /// The models the provider tries, in order, when this one fails. Empty when the provider has no fallbacks.
    var fallbacks: [Fallback] { get }
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

// MARK: - What an executor calls

extension DetailedLanguageModel {
    /// Logs an error and, in a debug build, shows a runtime warning for each model the request may reach that its
    /// provider stopped listing, since the request may fail: the model, then its fallbacks, each whose
    /// ``ModelDetails/removalDate`` is set.
    ///
    /// In a provider module of your own, the executor calls this first, before it sends the request.
    ///
    /// - Parameter request: The request, whose id names it in the log.
    public func reportRemovedModels(for request: LanguageModelExecutorGenerationRequest) {
        removedModels.report(for: request)
    }

    /// Checks an answer's text against the guides of the request's schema, such as a range or a count, since a host may
    /// drop or ignore those constraints. A request without a schema passes.
    ///
    /// In a provider module of your own, the executor calls this last, once it has sent the answer's events.
    ///
    /// - Parameters:
    ///   - text: The text of the answer's response entry, as the executor sent it, or empty when the answer ended in tool
    ///     calls.
    ///   - request: The request.
    /// - Throws: `GeneratedContent.ParsingError` when a value breaks a guide, as Foundation Models throws for an answer
    ///   that doesn't decode, or when an object or array answer isn't complete JSON.
    public func checkGuides(ofResponseText text: String, for request: LanguageModelExecutorGenerationRequest) throws {
        if let schema = request.schema {
            try GuideViolations.check(text, against: schema, request: request.id)
        }
    }
}
