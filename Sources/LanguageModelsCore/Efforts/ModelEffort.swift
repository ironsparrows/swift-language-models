public import FoundationModels

/// A value that names a reasoning level for one set of models.
///
/// Conform an enum that lists exactly the levels a set of models accepts, so it offers only those levels.
/// `ContextOptions.ReasoningLevel` conforms too, for models whose levels are known only at runtime.
public protocol ModelEffort: Sendable, Equatable {
    /// The reasoning level this value asks for.
    var reasoningLevel: ContextOptions.ReasoningLevel { get }
}

extension ModelEffort where Self: RawRepresentable, RawValue == String {
    /// The custom reasoning level named after the raw value.
    public var reasoningLevel: ContextOptions.ReasoningLevel { .custom(rawValue) }
}
