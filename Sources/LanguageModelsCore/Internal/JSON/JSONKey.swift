/// The key of a JSON object's member, for any name, so a type can encode members whose names are known only at run
/// time, and write fixed ones as string literals.
package struct JSONKey: CodingKey, ExpressibleByStringLiteral, Sendable {
    package let stringValue: String

    package init(stringValue: String) {
        self.stringValue = stringValue
    }

    package init(stringLiteral value: String) {
        stringValue = value
    }

    package var intValue: Int? { nil }

    package init?(intValue: Int) {
        nil
    }
}
