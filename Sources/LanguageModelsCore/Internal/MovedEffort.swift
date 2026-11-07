/// A reasoning level sent as another effort, the nearest the models accept, or left out when none is near it.
///
/// A provider's dialect puts it in its format's body plan, and the format logs it as a change to the request.
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
