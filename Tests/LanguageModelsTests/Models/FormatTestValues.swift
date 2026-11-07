import FoundationModels
import LanguageModels

/// A text segment.
func text(_ content: String) -> Transcript.Segment {
    .text(.init(content: content))
}

/// The keys of an object, in order.
func keys(_ value: JSONValue?) -> [String] {
    if case .object(let object)? = value { object.members.map(\.key) } else { [] }
}
