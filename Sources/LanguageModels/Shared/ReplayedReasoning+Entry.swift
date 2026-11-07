package import FoundationModels

extension ReplayedReasoning {
    /// A reasoning entry that goes back, with its text, or empty text for a block the model wrote at the start of its
    /// answer's text, which goes back there instead.
    package init(_ entry: Transcript.Reasoning) {
        self.init(entry, text: TaggedReasoning.block(of: entry) == nil ? entry.segments.compactMap(\.text).joined() : "")
    }
}
