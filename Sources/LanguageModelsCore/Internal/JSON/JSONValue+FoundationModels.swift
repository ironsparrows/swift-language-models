import Foundation
package import FoundationModels

extension JSONValue {
    /// Generated content as JSON, with each structure's properties sorted by name.
    ///
    /// A structure parsed from JSON doesn't keep its key order between launches, so sorting is what makes the same
    /// content give the same bytes.
    package init(_ content: GeneratedContent) {
        switch content.kind {
        case .null: self = .null
        case .bool(let value): self = .bool(value)
        case .number(let value): self = .number(value)
        case .string(let value): self = .string(value)
        case .array(let elements): self = .array(elements.map(JSONValue.init))
        case .structure(let properties, _):
            self = .object(
                JSONObject(properties.map { JSONObject.Member(key: $0.key, value: JSONValue($0.value)) }).sortedByKey()
            )
        @unknown default:
            // A kind this version doesn't know still writes JSON, which reads back as the value it holds; text that
            // isn't JSON stays a string, so nothing is lost.
            self = (try? JSONValue(json: Data(content.jsonString.utf8))) ?? .string(content.jsonString)
        }
    }

    /// A schema as JSON Schema, with its properties in generation order.
    ///
    /// Foundation Models lists the order in `x-order`, which providers don't know, so the properties take that order
    /// and the key is dropped.
    ///
    /// - Parameters:
    ///   - schema: The schema.
    ///   - strict: Whether to apply structured-output strict mode: every property is required, and an optional one
    ///     also accepts `null`.
    /// - Throws: `LanguageModelError.unsupportedGenerationGuide` when a guide has a value JSON can't hold, such as an
    ///   infinite bound.
    package init(_ schema: GenerationSchema, strict: Bool) throws(LanguageModelError) {
        do {
            self = try JSONValue(json: JSONEncoder().encode(schema)).adaptedSchema(strict: strict)
        } catch {
            throw .unsupportedGenerationGuide(
                .init(schemaName: schema.name, debugDescription: "The schema has a guide value that JSON can't hold: \(error)"))
        }
    }

    private func adaptedSchema(strict: Bool) -> JSONValue {
        switch self {
        case .array(let elements):
            return .array(elements.map { $0.adaptedSchema(strict: strict) })
        case .object(var object):
            let order = object["x-order"].flatMap(\.stringArray) ?? []
            object["x-order"] = nil
            if case .object(let properties)? = object["properties"] {
                let required = Set(object["required"].flatMap(\.stringArray) ?? [])
                let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
                let ordered = properties.sorted { position[$0.key, default: .max] < position[$1.key, default: .max] }
                object["properties"] = .object(
                    JSONObject(
                        ordered.members.map { member in
                            let schema = member.value.adaptedSchema(strict: strict)
                            let isOptional = strict && !required.contains(member.key)
                            let nullable: JSONValue = ["anyOf": [schema, ["type": .string(SchemaType.null)]]]
                            return JSONObject.Member(key: member.key, value: isOptional ? nullable : schema)
                        }
                    )
                )
                if strict { object["required"] = .array(ordered.members.map { .string($0.key) }) }
            }
            return .object(
                JSONObject(
                    object.members.map { member in
                        member.key == "properties"
                            ? member : JSONObject.Member(key: member.key, value: member.value.adaptedSchema(strict: strict))
                    }
                )
            )
        default:
            return self
        }
    }

    private var stringArray: [String]? {
        guard case .array(let elements) = self else { return nil }
        return elements.compactMap(\.stringValue)
    }
}

extension GeneratedContent {
    /// A JSON value as generated content, with an object's members in their order.
    package init(_ value: JSONValue) {
        switch value {
        case .null: self.init(kind: .null)
        case .bool(let value): self.init(kind: .bool(value))
        case .integer(let value): self.init(kind: .number(Double(value)))
        case .largeInteger(let value): self.init(kind: .number(NSDecimalNumber(decimal: value).doubleValue))
        case .number(let value): self.init(kind: .number(value))
        case .string(let value): self.init(kind: .string(value))
        case .array(let elements): self.init(kind: .array(elements.map(GeneratedContent.init)))
        case .object(let object):
            let properties = Dictionary(object.members.map { ($0.key, GeneratedContent($0.value)) }) { first, _ in first }
            self.init(kind: .structure(properties: properties, orderedKeys: object.members.map(\.key)))
        }
    }
}
