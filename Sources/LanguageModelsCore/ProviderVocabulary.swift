/// A word from a provider's API, such as a model id or a parameter name, in a type of its own.
///
/// Giving each kind of word its own type means one kind can't be passed where another belongs, while any word the
/// provider uses stays valid. A string literal creates a value directly, and a value encodes as its raw string, also
/// as a dictionary's key, so a dictionary keyed by one encodes as an object.
///
/// A conforming type declares only `rawValue` and `init(rawValue:)`: string literals and `description`, which prints
/// the raw value, come from this protocol. A provider module re-exports this module, so they work with only the
/// provider module imported.
public protocol ProviderVocabulary: RawRepresentable, Hashable, Sendable, Codable, CodingKeyRepresentable,
    ExpressibleByStringLiteral, CustomStringConvertible
where RawValue == String {
    /// Creates a value from the provider's spelling of it.
    init(rawValue: String)
}

extension ProviderVocabulary {
    /// Creates a value from a string literal of the provider's spelling of it.
    ///
    /// - Parameter value: The word, as the provider's API spells it.
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// The raw value, so printing a value shows the provider's spelling of it.
    public var description: String { rawValue }

    /// The word as a JSON string, as a provider's request spells it.
    package var json: JSONValue { .string(rawValue) }
}
