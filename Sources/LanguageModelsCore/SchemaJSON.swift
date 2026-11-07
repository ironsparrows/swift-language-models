import Foundation
package import FoundationModels

// MARK: - Foundation Models' values

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
    init(_ value: JSONValue) {
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

// MARK: - Schema names and prompts

extension GenerationSchema {
    /// The schema's name as APIs that name a response schema take it: letters, digits, `_` and `-`, up to 64
    /// characters, with `response` for a name that keeps none.
    package var wireName: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let name = String(name.map { allowed.contains($0) ? $0 : "_" }.prefix(64))
        return name.isEmpty ? "response" : name
    }

    /// The text that asks for JSON matching the schema, for a prompt.
    ///
    /// - Throws: `LanguageModelError.unsupportedGenerationGuide` when a guide has a value JSON can't hold.
    package func promptInstructions() throws(LanguageModelError) -> String {
        "Respond with JSON that matches this JSON Schema:\n\(try JSONValue(self, strict: false).text)"
    }
}

// MARK: - Portable schemas

extension JSONValue {
    /// The keywords that structured outputs take on every host: the structure of a schema, without its constraints.
    /// They're those of Anthropic's structured outputs, the narrowest that a host documents, less `minItems`, which
    /// Cohere rejects.
    private static let portableKeywords: Set<String> = [
        "$defs", "$ref", "additionalProperties", "allOf", "anyOf", "const", "description", "enum", "items", "properties",
        "required", "title", "type",
    ]

    /// The schema with every keyword outside the portable ones moved into its description, as `{key: value, …}` after
    /// a blank line, so the model still reads the constraint.
    package var portableSchema: JSONValue {
        guard case .object(let schema) = self else { return self }
        var kept = JSONObject()
        var moved: [String] = []
        for member in schema.members {
            switch member.key {
            case "properties", "$defs":
                kept[member.key] = member.value.mappingObject(\.portableSchema)
            case "items":
                kept[member.key] = member.value.portableSchema
            case "anyOf", "allOf":
                kept[member.key] = member.value.mappingArray(\.portableSchema)
            case let key where Self.portableKeywords.contains(key):
                kept[key] = member.value
            default:
                moved.append("\(member.key): \(member.value.text)")
            }
        }
        if !moved.isEmpty {
            let constraints = "{\(moved.joined(separator: ", "))}"
            if let description = kept["description"]?.stringValue {
                kept["description"] = .string("\(description)\n\n\(constraints)")
            } else {
                kept["description"] = .string(constraints)
            }
        }
        return .object(kept)
    }

    /// The object with each member's value transformed, or the value unchanged when it isn't an object.
    private func mappingObject(_ transform: (JSONValue) -> JSONValue) -> JSONValue {
        guard case .object(let object) = self else { return self }
        return .object(JSONObject(object.members.map { JSONObject.Member(key: $0.key, value: transform($0.value)) }))
    }

    /// The array with each element transformed, or the value unchanged when it isn't an array.
    private func mappingArray(_ transform: (JSONValue) -> JSONValue) -> JSONValue {
        guard case .array(let elements) = self else { return self }
        return .array(elements.map(transform))
    }
}
