public import FoundationModels

extension Efforts {
    /// An effort type with no levels, for a model described by hand whose reasoning level can't be chosen: one that
    /// doesn't reason, or one that reasons at a level it picks itself.
    ///
    /// A catalog model of either kind has its own ``Efforts/Of`` with no members instead. For a model that reasons, a
    /// request's `ContextOptions` or a profile's `reasoningLevel(_:)` still turns reasoning on or off.
    ///
    /// Like the other effort types, it's `Codable`, so code that stores an effort works with any model. Decoding
    /// always fails, because there's no value to decode.
    public enum Unsupported: ModelEffort, CaseIterable, Codable {
        /// Never called, because the type has no values.
        public var reasoningLevel: ContextOptions.ReasoningLevel {
            switch self {}
        }

        /// Fails, because the type has no values.
        ///
        /// - Throws: `DecodingError.dataCorrupted`.
        public init(from decoder: any Decoder) throws {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Efforts.Unsupported has no values.")
            )
        }

        /// Never called, because the type has no values.
        public func encode(to encoder: any Encoder) throws {
            switch self {}
        }
    }
}
