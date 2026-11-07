package import FoundationModels

/// One of an answer's reasoning entries that goes back in a later request, as a dialect's `replayMembers(_:)` hook
/// reads it.
///
/// Only an API format's executor creates one.
package struct ReplayedReasoning {
    /// The entry, with its signature and metadata.
    package let entry: Transcript.Reasoning

    /// The entry's text, or empty for a block the model wrote at the start of its answer's text, which goes back
    /// there instead.
    package let text: String

    package init(_ entry: Transcript.Reasoning, text: String) {
        self.entry = entry
        self.text = text
    }
}
