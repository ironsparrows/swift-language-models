import Foundation
import FoundationModels

extension JSONValue {
    /// The constraints of a JSON schema that the value breaks.
    ///
    /// It checks the constraints that guides become, `const`, `enum`, `minimum`, `maximum`, `exclusiveMinimum`,
    /// `exclusiveMaximum`, `minItems`, `maxItems`, `minLength`, `maxLength` and `pattern`, through `properties`,
    /// `items`, `anyOf`, `allOf` and references into `$defs`. Each applies only to values of its kind, and a `pattern`
    /// matches anywhere in the string, by Unicode scalar, as in JSON Schema. Types, and the `const` that names an
    /// enum's case, only choose the `anyOf` branch a value takes: decoding checks them.
    ///
    /// - Parameter schema: The schema, whose `$ref`s point into its own `$defs`.
    /// - Returns: Each broken constraint, in the order of the value; none when the value meets them all.
    package func violations(of schema: JSONValue) -> [GuideViolation] {
        SchemaChecker(root: schema).violations(of: self, against: schema, at: "", depth: 0)
    }
}

extension JSONValue {
    /// Checks values against the constraints of one schema.
    private struct SchemaChecker {
        let root: JSONValue

        /// How deep references may nest, so a schema that refers to itself ends.
        private static let maximumDepth = 64

        func violations(of value: JSONValue, against schema: JSONValue, at path: String, depth: Int) -> [GuideViolation] {
            guard case .object(let keywords) = schema, depth < Self.maximumDepth else { return [] }
            var found: [GuideViolation] = []
            if let target = keywords["$ref"].flatMap(resolve) {
                found += violations(of: value, against: target, at: path, depth: depth + 1)
            }
            if case .array(let branches)? = keywords["anyOf"] {
                found += violations(of: value, againstAnyOf: branches, at: path, depth: depth)
            }
            if case .array(let branches)? = keywords["allOf"] {
                for branch in branches { found += violations(of: value, against: branch, at: path, depth: depth + 1) }
            }
            found += Self.violations(of: value, keywords: keywords, at: path)
            switch value {
            case .object(let object):
                guard case .object(let properties)? = keywords["properties"] else { break }
                for member in object.members {
                    guard let property = properties[member.key] else { continue }
                    found += violations(of: member.value, against: property, at: Self.path(path, member.key), depth: depth + 1)
                }
            case .array(let elements):
                guard let items = keywords["items"] else { break }
                for (index, element) in elements.enumerated() {
                    found += violations(of: element, against: items, at: "\(path)[\(index)]", depth: depth + 1)
                }
            default:
                break
            }
            return found
        }

        /// A value meets `anyOf` when it meets a branch. Otherwise its violations are those of the first branch of its
        /// type, and none when no branch is of its type, which decoding reports.
        private func violations(of value: JSONValue, againstAnyOf branches: [JSONValue], at path: String, depth: Int) -> [GuideViolation] {
            var firstOfItsType: [GuideViolation]?
            for branch in branches where fits(value, branch, depth: depth + 1) {
                let found = violations(of: value, against: branch, at: path, depth: depth + 1)
                if found.isEmpty { return [] }
                if firstOfItsType == nil { firstOfItsType = found }
            }
            return firstOfItsType ?? []
        }

        /// Whether the value is of a type the schema allows, following references and `anyOf`, and names the case the
        /// schema is for, when the schema is one case of an enum. A schema without a type allows any.
        private func fits(_ value: JSONValue, _ schema: JSONValue, depth: Int) -> Bool {
            guard case .object(let keywords) = schema, depth < Self.maximumDepth else { return true }
            if let target = keywords["$ref"].flatMap(resolve), !fits(value, target, depth: depth + 1) { return false }
            if case .array(let branches)? = keywords["anyOf"], !branches.contains(where: { fits(value, $0, depth: depth + 1) }) {
                return false
            }
            // Each case of an enum with associated values is an object whose `type` property has a `const`, its name.
            if case .object(let object) = value, case .object(let properties)? = keywords["properties"] {
                for property in properties.members {
                    guard let name = property.value["const"] else { continue }
                    guard let member = object[property.key], member.isSame(as: name) else { return false }
                }
            }
            switch keywords["type"] {
            case .string(let type)?: return value.isOfType(type)
            case .array(let types)?: return types.contains { $0.stringValue.map(value.isOfType) ?? false }
            default: return true
            }
        }

        /// The schema a `$ref` such as `#/$defs/Ingredient` points to.
        private func resolve(_ reference: JSONValue) -> JSONValue? {
            guard let reference = reference.stringValue, reference.hasPrefix("#") else { return nil }
            var target: JSONValue? = root
            for component in reference.dropFirst().split(separator: "/") {
                let key = String(component).replacing("~1", with: "/").replacing("~0", with: "~")
                target = target?[key]
            }
            return target
        }

        /// The violations of the keywords that constrain the value itself.
        private static func violations(of value: JSONValue, keywords: JSONObject, at path: String) -> [GuideViolation] {
            var found: [GuideViolation] = []
            func add(_ keyword: GuideViolation.Keyword, limit: JSONValue, _ problem: String) {
                found.append(
                    GuideViolation(
                        path: path, keyword: keyword, value: GeneratedContent(value), limit: GeneratedContent(limit), problem: problem))
            }
            if let constant = keywords["const"], !value.isSame(as: constant) {
                add(.const, limit: constant, "is \(value.shortText), not \(constant.shortText)")
            }
            if case .array(let allowed)? = keywords["enum"], !allowed.contains(where: value.isSame) {
                add(.enum, limit: .array(allowed), "is \(value.shortText), not one of \(allowed.map(\.shortText).joined(separator: ", "))")
            }
            func order(to keyword: String) -> ComparisonResult? {
                keywords[keyword].flatMap { JSONValue.order(of: value, to: $0) }
            }
            if let minimum = keywords["minimum"], order(to: "minimum") == .orderedAscending {
                add(.minimum, limit: minimum, "is \(value.shortText), below the minimum of \(minimum.shortText)")
            }
            if let maximum = keywords["maximum"], order(to: "maximum") == .orderedDescending {
                add(.maximum, limit: maximum, "is \(value.shortText), above the maximum of \(maximum.shortText)")
            }
            if let minimum = keywords["exclusiveMinimum"], let order = order(to: "exclusiveMinimum"), order != .orderedDescending {
                add(.exclusiveMinimum, limit: minimum, "is \(value.shortText), not above \(minimum.shortText)")
            }
            if let maximum = keywords["exclusiveMaximum"], let order = order(to: "exclusiveMaximum"), order != .orderedAscending {
                add(.exclusiveMaximum, limit: maximum, "is \(value.shortText), not below \(maximum.shortText)")
            }
            if case .array(let elements) = value {
                if let minimum = keywords["minItems"], let bound = minimum.numberValue, Double(elements.count) < bound {
                    add(.minItems, limit: minimum, "has \(items(elements.count)), fewer than the minimum of \(minimum.shortText)")
                }
                if let maximum = keywords["maxItems"], let bound = maximum.numberValue, Double(elements.count) > bound {
                    add(.maxItems, limit: maximum, "has \(items(elements.count)), more than the maximum of \(maximum.shortText)")
                }
            }
            if case .string(let text) = value {
                let length = Double(text.unicodeScalars.count)
                if let minimum = keywords["minLength"], let bound = minimum.numberValue, length < bound {
                    add(.minLength, limit: minimum, "is \(value.shortText), shorter than the minimum of \(minimum.shortText) characters")
                }
                if let maximum = keywords["maxLength"], let bound = maximum.numberValue, length > bound {
                    add(.maxLength, limit: maximum, "is \(value.shortText), longer than the maximum of \(maximum.shortText) characters")
                }
                // A pattern Swift can't compile is left unchecked, rather than failing an answer the host accepted.
                if let pattern = keywords["pattern"]?.stringValue, let regex = try? Regex(pattern).matchingSemantics(.unicodeScalar),
                    text.firstMatch(of: regex) == nil
                {
                    add(.pattern, limit: .string(pattern), "is \(value.shortText), which doesn't match the pattern \(pattern)")
                }
            }
            return found
        }

        private static func path(_ path: String, _ key: String) -> String {
            path.isEmpty ? key : "\(path).\(key)"
        }

        private static func items(_ count: Int) -> String {
            count == 1 ? "1 item" : "\(count) items"
        }
    }
}

extension JSONValue {
    /// The value as a number, for any of the number cases.
    fileprivate var numberValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .largeInteger(let value): NSDecimalNumber(decimal: value).doubleValue
        case .number(let value): value
        default: nil
        }
    }

    /// Whether the value is of a JSON Schema type, where a whole number is an `integer` too.
    fileprivate func isOfType(_ type: String) -> Bool {
        switch (type, self) {
        case (SchemaType.null, .null), (SchemaType.boolean, .bool), (SchemaType.string, .string),
            (SchemaType.array, .array), (SchemaType.object, .object):
            true
        case (SchemaType.integer, .integer), (SchemaType.integer, .largeInteger): true
        case (SchemaType.integer, .number(let value)): value.rounded() == value
        case (SchemaType.number, _): numberValue != nil
        default: false
        }
    }

    /// Whether two values are the same JSON value, where numbers compare by value.
    fileprivate func isSame(as other: JSONValue) -> Bool {
        if let order = Self.order(of: self, to: other) { return order == .orderedSame }
        return self == other
    }

    /// How one number compares with another, or `nil` when either isn't a number.
    ///
    /// Whole numbers compare exactly, also past the 2^53 that a `Double` holds exactly; a number with a fraction
    /// compares as a `Double`.
    fileprivate static func order(of value: JSONValue, to other: JSONValue) -> ComparisonResult? {
        switch (value, other) {
        case (.integer(let value), .integer(let other)):
            return order(value, other)
        case (.number, _), (_, .number):
            guard let value = value.numberValue, let other = other.numberValue else { return nil }
            return order(value, other)
        default:
            guard let value = value.wholeNumber, let other = other.wholeNumber else { return nil }
            return order(value, other)
        }
    }

    private static func order<Number: Comparable>(_ value: Number, _ other: Number) -> ComparisonResult {
        value < other ? .orderedAscending : value > other ? .orderedDescending : .orderedSame
    }

    /// The value as a whole number, for the integer cases.
    private var wholeNumber: Decimal? {
        switch self {
        case .integer(let value): Decimal(value)
        case .largeInteger(let value): value
        default: nil
        }
    }

    /// The value as JSON text, cut short after 60 characters.
    fileprivate var shortText: String {
        let text = self.text
        return text.count > 60 ? "\(text.prefix(60))…" : text
    }
}

extension JSONValue {
    /// The words of JSON Schema's `type` keyword.
    enum SchemaType {
        static let null = "null"
        static let boolean = "boolean"
        static let integer = "integer"
        static let number = "number"
        static let string = "string"
        static let array = "array"
        static let object = "object"
    }
}
