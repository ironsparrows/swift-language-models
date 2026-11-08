import LanguageModelsCore
import Testing

@Suite("Portable schema")
struct PortableSchemaTests {
    @Test func `constraints move into the description, after the schema's own`() {
        let schema: JSONValue = ["type": "integer", "description": "Servings.", "minimum": 1, "maximum": 12]

        #expect(schema.portableSchema == ["type": "integer", "description": "Servings.\n\n{minimum: 1, maximum: 12}"])
    }

    @Test func `a schema without a description gets one with its constraints`() {
        let schema: JSONValue = ["type": "string", "pattern": "^[a-z]+$"]

        #expect(schema.portableSchema == ["type": "string", "description": #"{pattern: "^[a-z]+$"}"#])
    }

    @Test func `nested schemas lose their constraints too, in properties, definitions, items and alternatives`() {
        let constrained: JSONValue = ["type": "array", "maxItems": 3]
        let portable: JSONValue = ["type": "array", "description": "{maxItems: 3}"]
        let schema: JSONValue = [
            "type": "object",
            "properties": ["tags": constrained],
            "$defs": ["Tags": constrained],
            "items": constrained,
            "anyOf": [constrained, ["type": "null"]],
            "required": ["tags"],
        ]

        #expect(
            schema.portableSchema == [
                "type": "object",
                "properties": ["tags": portable],
                "$defs": ["Tags": portable],
                "items": portable,
                "anyOf": [portable, ["type": "null"]],
                "required": ["tags"],
            ])
    }

    @Test func `a value that isn't a schema object stays as it is`() {
        #expect(JSONValue.bool(true).portableSchema == true)
    }
}
