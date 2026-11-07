package import FoundationModels

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
    package static func nearest(to word: String, among supported: [String], ranking: [String]) -> String? {
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
