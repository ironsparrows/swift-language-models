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
