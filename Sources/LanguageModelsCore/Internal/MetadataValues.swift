package import Foundation
package import FoundationModels

/// Typed reads of an entry's or usage's metadata, or of a structure in it. A read is `nil`, or a list empty, when the
/// key is missing or its value is of another kind.
package struct MetadataValues {
    private let values: [String: GeneratedContent]

    package init(_ values: [String: GeneratedContent]) {
        self.values = values
    }

    /// The properties of a structure, or `nil` when the content isn't one.
    package init?(_ content: GeneratedContent) {
        guard case .structure(let properties, _) = content.kind else { return nil }
        self.init(properties)
    }

    package func string(_ key: String) -> String? {
        if case .string(let value)? = values[key]?.kind { value } else { nil }
    }

    package func bool(_ key: String) -> Bool? {
        if case .bool(let value)? = values[key]?.kind { value } else { nil }
    }

    /// A whole number, or `nil` for a fraction.
    package func integer(_ key: String) -> Int? {
        number(key).flatMap { Int(exactly: $0) }
    }

    /// An amount as the decimal number its shortest spelling names, so `0.000012345` reads as exactly that rather than
    /// the binary fraction nearest to it, `0.000012344999999999997952`.
    package func decimal(_ key: String) -> Decimal? {
        // A nil locale always reads `.` as the decimal separator; Double's description is never localized.
        number(key).flatMap { $0.isFinite ? Decimal(string: String($0), locale: nil) : nil }
    }

    /// A number of seconds as a duration, rounded to the nanosecond, so `2.016` is exactly 2,016 milliseconds.
    package func duration(_ key: String) -> Duration? {
        number(key).flatMap { Int64(exactly: ($0 * 1e9).rounded()) }.map { .nanoseconds($0) }
    }

    /// The elements of a list.
    package func array(_ key: String) -> [GeneratedContent] {
        if case .array(let elements)? = values[key]?.kind { elements } else { [] }
    }

    /// The structures in a list, skipping any element that isn't one.
    package func structures(_ key: String) -> [MetadataValues] {
        array(key).compactMap(MetadataValues.init)
    }

    private func number(_ key: String) -> Double? {
        if case .number(let value)? = values[key]?.kind { value } else { nil }
    }
}
