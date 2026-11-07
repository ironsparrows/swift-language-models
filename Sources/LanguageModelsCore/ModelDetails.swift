public import Foundation
public import FoundationModels
public import UniformTypeIdentifiers

/// What a provider reports about one of its models.
///
/// The identifier is the provider's model id, in a ``ProviderVocabulary`` type of the provider's own, so one
/// provider's id can't be passed where another's belongs. Values the provider doesn't report are `nil`.
public protocol ModelDetails: Identifiable, Sendable where ID: ProviderVocabulary {
    /// The reasoning levels this model accepts.
    associatedtype Effort: ModelEffort

    /// The model's human-readable name.
    var displayName: String { get }

    /// What the model supports, such as tool calling, image input or reasoning.
    var capabilities: LanguageModelCapabilities { get }

    /// Whether and when the model reasons.
    var reasoning: ModelReasoning { get }

    /// The size of the model's context window, in tokens.
    var contextSize: Int? { get }

    /// The reasoning levels the model accepts, highest first.
    ///
    /// Empty when the model's reasoning level can't be chosen, which includes a model that doesn't reason.
    var reasoningEfforts: [Effort] { get }

    /// The level the provider uses when a request doesn't set one.
    var defaultReasoningEffort: Effort? { get }

    /// The day the provider stopped listing the model, as the provider module's catalog records it, or `nil` for a
    /// model the catalog doesn't record as removed.
    ///
    /// A request that may reach such a model, as its model or a fallback, may fail, so it logs an error and, in a
    /// debug build, shows a runtime warning.
    var removalDate: Date? { get }

    /// The kinds of data the model accepts as prompt attachments, such as images or PDF documents.
    ///
    /// A kind that conforms to one of these, such as PNG to image, is accepted too.
    var dataAttachmentTypes: Set<UTType> { get }

    /// The kinds of data the model generates besides text, such as images.
    ///
    /// A kind that conforms to one of these is generated too.
    var dataEntryTypes: Set<UTType> { get }
}

extension ModelDetails {
    /// Whether the model accepts prompt attachments of the given kind.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the kind conforms to one of ``dataAttachmentTypes``.
    public func supportsDataAttachmentType(_ type: UTType) -> Bool {
        dataAttachmentTypes.contains { type.conforms(to: $0) }
    }

    /// Whether the model generates data of the given kind.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the kind conforms to one of ``dataEntryTypes``.
    public func supportsDataEntryType(_ type: UTType) -> Bool {
        dataEntryTypes.contains { type.conforms(to: $0) }
    }
}
