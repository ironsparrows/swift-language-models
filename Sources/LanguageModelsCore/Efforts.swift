public import FoundationModels

// MARK: - Efforts

/// Reasoning effort types: ``Of`` for a model of a provider module's catalog, and ``Unsupported`` for a model described
/// by hand whose level can't be chosen.
///
/// ``Of`` offers exactly the levels its model accepts, so code can name only those, and keeps a level the model stopped
/// accepting as a deprecated member.
public enum Efforts {}

extension Efforts {
    /// The words of one model's reasoning levels, which ``Efforts/Of`` reads to make its values, with
    /// `init(rawValue:)`, and to list them, with `allCases`.
    ///
    /// A provider module's catalog gives each model an empty enum that conforms to this protocol, under the catalog's
    /// namespace, such as `VendorCatalog.ModelName`, so each model has an effort type of its own. The catalog also
    /// writes an extension of `Efforts.Of` for the model, with a static member for each level.
    public protocol List: Sendable {
        /// The words of the levels the model accepts, highest first.
        static var efforts: [String] { get }

        /// The words of the levels the model accepted before, which its effort type keeps as deprecated members.
        static var removedEfforts: [String] { get }
    }
}

extension Efforts.List {
    /// None: the model accepts every level it ever accepted.
    public static var removedEfforts: [String] { [] }
}

extension Efforts {
    /// A reasoning level of one model, which `Tag` names.
    ///
    /// A catalog model's effort type has a static member for each level the model accepts, such as `.high`, so code
    /// can name only those. Each model has an effort type of its own, so the type stays the same when the model's
    /// levels change: a level the model gains adds a member, and a level it stops accepting stays, marked deprecated.
    ///
    /// An effort prints as its word, such as `high`.
    public struct Of<Tag: List>: ModelEffort, RawRepresentable, Hashable, Codable, CodingKeyRepresentable,
        CaseIterable, CustomStringConvertible
    {
        /// The level's word, as the provider's API spells it.
        public let rawValue: String

        /// The level with the given word, or `nil` when the model neither accepts it nor accepted it before.
        ///
        /// - Parameter rawValue: The level's word, such as `high`.
        public init?(rawValue: String) {
            guard Tag.efforts.contains(rawValue) || Tag.removedEfforts.contains(rawValue) else { return nil }
            self.rawValue = rawValue
        }

        /// A level the model's catalog lists, which a generated member creates.
        ///
        /// - Parameter rawValue: The level's word, such as `high`.
        package init(listed rawValue: String) {
            self.rawValue = rawValue
        }

        /// The levels the model accepts, highest first, without the levels it stopped accepting.
        public static var allCases: [Self] {
            Tag.efforts.map(Self.init(listed:))
        }

        /// The level's word, such as `high`.
        public var description: String {
            rawValue
        }
    }
}

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

// MARK: - Model effort

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

extension ContextOptions.ReasoningLevel: ModelEffort {
    /// The level itself.
    public var reasoningLevel: Self { self }
}

extension ContextOptions.ReasoningLevel {
    /// The effort word the level asks a provider for, such as `high`: `low`, `medium` and `high` for `light`,
    /// `moderate` and `deep`, and a custom level's own word, such as `xhigh` or `none`.
    ///
    /// A typed effort's word is its `rawValue`; this reads the word back from a level in its open form, such as one an
    /// app picked at run time, so the app can show it or store it. `nil` for a level this package doesn't know yet.
    public var effortWord: String? {
        switch self {
        case .light: "low"
        case .moderate: "medium"
        case .deep: "high"
        case .custom(let word): word
        @unknown default: nil
        }
    }
}

// MARK: - Asking for an effort

extension DetailedLanguageModel {
    /// The reasoning level for one of this model's own efforts, for a request's `ContextOptions`.
    ///
    /// The effort's type comes from the model, so it takes only the levels the model accepts:
    ///
    /// ```swift
    /// let response = try await session.respond(
    ///     to: "Plan a trip.",
    ///     contextOptions: ContextOptions(reasoningLevel: model.reasoningLevel(.high))
    /// )
    /// ```
    ///
    /// ``ModelDetails/reasoningEfforts`` lists the levels the model accepts. A model whose levels are known only at
    /// runtime takes any level, and its provider module sends the nearest one the model accepts.
    ///
    /// - Parameter effort: One of the levels the model accepts.
    /// - Returns: The reasoning level to put in a request's `ContextOptions`.
    public func reasoningLevel(_ effort: Details.Effort) -> ContextOptions.ReasoningLevel {
        effort.reasoningLevel
    }
}

extension LanguageModelSession.DynamicProfile {
    /// Uses a model for requests from this profile, at a reasoning level the model supports.
    ///
    /// The effort's type comes from the model, so it takes only the levels the model accepts. The effort sets the
    /// profile's reasoning level: a request's `ContextOptions` replaces it for that request, and a `reasoningLevel(_:)`
    /// applied around this profile doesn't.
    ///
    /// - Parameters:
    ///   - model: The model to use.
    ///   - effort: The reasoning level, from the levels `model` accepts.
    /// - Returns: A profile that uses `model` at `effort`.
    public func model<Model: DetailedLanguageModel>(
        _ model: Model,
        effort: Model.Details.Effort
    ) -> some LanguageModelSession.DynamicProfile {
        self.model(model).reasoningLevel(effort.reasoningLevel)
    }
}

// MARK: - What a provider sends

extension ContextOptions.ReasoningLevel {
    /// The word to send for this level to a model that accepts the given levels.
    ///
    /// `light`, `moderate` and `deep` ask for `low`, `medium` and `high`; a custom level asks for its own word. The
    /// word is chosen by ``nearest(to:among:ranking:)``.
    ///
    /// - Parameters:
    ///   - supported: The levels the model accepts.
    ///   - ranking: Every known effort word, highest first. The catalogs' ranking unless a test passes its own.
    /// - Returns: The provider's word for the level, or `nil` to leave it out of the request.
    package func providerEffort(supporting supported: [some ModelEffort], ranking: [String] = effortRanking) -> String? {
        guard let effortWord else { return nil }
        return Self.nearest(to: effortWord, among: supported.compactMap(\.reasoningLevel.effortWord), ranking: ranking)
    }

    /// The effort to send for this level to a model that accepts the given levels, and the level with the effort sent
    /// when that effort isn't the level's own or none is, which the request logs.
    ///
    /// - Parameter supported: The levels the model accepts.
    /// - Returns: The provider's word for the level, or `nil` to leave it out, and the moved effort, if any.
    package func sentEffort(supporting supported: [some ModelEffort]) -> (effort: String?, moved: MovedEffort?) {
        let effort = providerEffort(supporting: supported)
        let requested = effortWord.flatMap { $0 == effort ? nil : $0 }
        return (effort, requested.map { MovedEffort(requested: $0, sent: effort) })
    }

    /// The word to send for an effort word to a model that accepts the given words.
    ///
    /// A word the model accepts is sent as is. Otherwise the nearest accepted word in `ranking` is sent, the lower one
    /// on a tie, but never `none`: a model asked to reason keeps reasoning, so only a request for `none` turns it off.
    /// A model that lists no words takes none, and a word missing from `ranking` has no nearest word; both give `nil`,
    /// so the provider uses its default.
    ///
    /// - Parameters:
    ///   - word: The effort word asked for, such as `low`.
    ///   - supported: The words the model accepts.
    ///   - ranking: Every known effort word, highest first.
    /// - Returns: The word to send, or `nil` to leave it out of the request.
    static func nearest(to word: String, among supported: [String], ranking: [String]) -> String? {
        guard !supported.contains(word) else { return word }
        guard let position = ranking.firstIndex(of: word) else { return nil }

        let ranked = supported.filter { $0 != Self.off.effortWord }.compactMap { candidate in
            ranking.firstIndex(of: candidate).map { (word: candidate, position: $0) }
        }
        return ranked.min { lhs, rhs in
            let (lhsDistance, rhsDistance) = (abs(lhs.position - position), abs(rhs.position - position))
            return lhsDistance == rhsDistance ? lhs.position > rhs.position : lhsDistance < rhsDistance
        }?.word
    }
}

/// A reasoning level sent as another effort, the nearest the models accept, or left out when none is near it.
///
/// A provider's exchange sets it on its request, and the format logs it as a change to the request.
package struct MovedEffort: Sendable, Equatable {
    /// The level's own effort word.
    package let requested: String

    /// The effort sent instead, or `nil` when none is.
    package let sent: String?

    package init(requested: String, sent: String?) {
        self.requested = requested
        self.sent = sent
    }
}
