public import Foundation
public import FoundationModels
public import UniformTypeIdentifiers
import os

// MARK: - Details

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

// MARK: - Reasoning

/// Whether and when a model reasons, and whether a request can turn its reasoning off.
public struct ModelReasoning: Sendable, Hashable {
    /// The model doesn't reason.
    public static let unsupported = Self(.unsupported)

    /// The model reasons only when a request asks it to.
    public static let offByDefault = Self(.offByDefault)

    /// The model reasons unless a request turns reasoning off.
    public static let onByDefault = Self(.onByDefault)

    /// The model always reasons, so a request can't turn reasoning off.
    public static let mandatory = Self(.mandatory)

    private enum Mode: Hashable {
        case unsupported, offByDefault, onByDefault, mandatory
    }

    private let mode: Mode

    private init(_ mode: Mode) {
        self.mode = mode
    }

    /// Whether the model reasons at all.
    public var isSupported: Bool {
        switch mode {
        case .unsupported: false
        case .offByDefault, .onByDefault, .mandatory: true
        }
    }

    /// Whether the model reasons when a request doesn't set a reasoning level.
    public var isEnabledByDefault: Bool {
        switch mode {
        case .unsupported, .offByDefault: false
        case .onByDefault, .mandatory: true
        }
    }

    /// Whether a request can turn the model's reasoning off.
    public var canBeTurnedOff: Bool {
        switch mode {
        case .unsupported, .mandatory: false
        case .offByDefault, .onByDefault: true
        }
    }
}

// MARK: - Shared by two models

extension ModelReasoning {
    /// The reasoning two models share, such as a model and its fallback: none when either doesn't reason, always when
    /// either always reasons, and by default only when both reason by default.
    package func sharing(_ other: Self) -> Self {
        if !isSupported || !other.isSupported { return .unsupported }
        if !canBeTurnedOff || !other.canBeTurnedOff { return .mandatory }
        return isEnabledByDefault && other.isEnabledByDefault ? .onByDefault : .offByDefault
    }
}

extension Optional where Wrapped: Comparable {
    /// The smaller of two limits that two models share, such as their context sizes, or the one that's known.
    package func smallerLimit(_ other: Self) -> Self {
        switch (self, other) {
        case (let limit?, let other?): Swift.min(limit, other)
        case (let limit?, nil): limit
        case (nil, let other): other
        }
    }
}

// MARK: - Removed models

/// The models a provider stopped listing, which its catalog keeps as deprecated members, each with the day it left.
///
/// The model catalog generator writes one for each provider module, as a static member such as
/// `ModelRemovals.vendor`, which the module's details read for their ``ModelDetails/removalDate``.
package struct ModelRemovals: Sendable {
    /// Midnight UTC at the start of the day the provider stopped listing each model, by id.
    package let dates: [String: Date]

    /// Creates the removals of a provider's catalog.
    ///
    /// - Parameter dates: Midnight UTC at the start of the day the provider stopped listing each model, by id.
    package init(_ dates: [String: Date]) {
        self.dates = dates
    }

    /// The day the provider stopped listing a model.
    ///
    /// - Parameter id: The model's id, as the provider's API spells it.
    /// - Returns: The day, or `nil` while the provider lists the model.
    package func removalDate(of id: String) -> Date? {
        dates[id]
    }
}

extension ModelRemovals {
    /// A model a request may reach, as its model or a fallback, that its provider stopped listing, so the request may
    /// fail, to report before the request is sent.
    package struct Report: Equatable, Sendable {
        /// The model's id.
        let id: String
        /// Midnight UTC at the start of the day the provider stopped listing the model.
        let removedOn: Date

        /// The log message and runtime warning, which name the model and the day.
        var message: String {
            let day = removedOn.formatted(.iso8601.year().month().day())
            return "The request names \(id), which its provider stopped listing on \(day), so it may fail. Choose another model."
        }

        /// Logs the model at the error level, and shows a runtime warning in a debug build.
        ///
        /// - Parameter request: The start of the request's id, which names the request in the log.
        fileprivate func report(request: String) {
            PackageLogger.languageModels(.error)?.error("Request \(request, privacy: .public): \(message, privacy: .public)")
            // The issue is filed under `LanguageModels`, the module apps import, and the module in `fileID` is its category.
            runtimeWarning(message, fileID: "LanguageModels/ModelDetails.swift")
        }
    }
}

extension [ModelRemovals.Report] {
    /// The models a request may reach that their provider stopped listing.
    ///
    /// - Parameter models: The models a request may reach, in the order the provider tries them.
    package init(reaching models: [any ModelDetails]) {
        self = models.compactMap { details in
            details.removalDate.map { ModelRemovals.Report(id: details.id.rawValue, removedOn: $0) }
        }
    }

    /// Reports each model, before the request is sent.
    ///
    /// - Parameter request: The request, whose id names it in the log.
    package func report(for request: LanguageModelExecutorGenerationRequest) {
        let name = LanguageModelsLogging.requestName(request.id)
        for removed in self {
            removed.report(request: name)
        }
    }
}

extension DetailedLanguageModel {
    /// The model and fallbacks that their provider stopped listing, in the order the provider tries them.
    var removedModels: [ModelRemovals.Report] {
        [ModelRemovals.Report](reaching: [details] + fallbacks)
    }
}
