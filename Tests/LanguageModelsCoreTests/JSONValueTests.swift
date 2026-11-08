import Foundation
import FoundationModels
import LanguageModelsCore
import Testing

@Suite("JSON value")
struct JSONValueTests {
    @Test func `an object built in code keeps its order and drops members without a value`() {
        let missing: JSONValue? = nil
        let value: JSONValue = ["zeta": 1, "alpha": "a", "skipped": missing, "mid": [true, .null]]

        #expect(text(value) == #"{"zeta":1,"alpha":"a","mid":[true,null]}"#)
    }

    @Test func `an object decoded from JSON is sorted by key`() throws {
        let value = try JSONValue(json: Data(#"{"b": 1, "a": {"d": 2, "c": 3}}"#.utf8))

        #expect(text(value) == #"{"a":{"c":3,"d":2},"b":1}"#)
    }

    @Test(arguments: [(2.0, "2"), (2.5, "2.5"), (0.000_000_1, "1e-07"), (1e300, "1e+300"), (Double.infinity, "null")])
    func `a number without a fraction is written as an integer`(number: Double, written: String) {
        #expect(text(.number(number)) == written)
    }

    @Test(arguments: ["12345678901234567890", "-9223372036854775809", "[18446744073709551616,1]"])
    func `an integer too large for Int keeps every digit`(json: String) throws {
        #expect(text(try JSONValue(json: Data(json.utf8))) == json)
    }

    @Test func `a string escapes quotes, backslashes and control characters, and keeps other text`() {
        #expect(text(.string("a \"b\" \\ \n\t\u{01} é /")) == #""a \"b\" \\ \n\t\u0001 é /""#)
    }

    @Test func `generated content sorts each structure's properties`() throws {
        let content = try GeneratedContent(json: #"{"b": 1, "a": [true, null, "x", 2.5], "c": {"e": 1, "d": 2}}"#)

        #expect(text(JSONValue(content)) == #"{"a":[true,null,"x",2.5],"b":1,"c":{"d":2,"e":1}}"#)
    }

    @Test func `a schema's properties follow the generation order and lose x-order`() throws {
        let schema = try JSONValue(Meal.generationSchema, strict: false)

        #expect(schema["x-order"] == nil)
        #expect(propertyNames(schema) == ["name", "servings", "notes", "kind"])
        #expect(schema["required"] == ["name", "servings", "kind"])
    }

    @Test func `strict mode requires every property and lets optional ones be null`() throws {
        let schema = try JSONValue(Meal.generationSchema, strict: true)

        #expect(schema["required"] == ["name", "servings", "notes", "kind"])
        #expect(schema["properties"]?["notes"] == ["anyOf": [["type": "string"], ["type": "null"]]])
        #expect(schema["additionalProperties"] == false)
    }

    @Test(arguments: [(JSONValue.null, "null"), (true, "true")])
    func `an encoder writes null and a bool as the JSON they are`(value: JSONValue, json: String) throws {
        #expect(String(decoding: try JSONEncoder().encode(value), as: UTF8.self) == json)
    }

    @Test func `a schema gives the same bytes every time`() throws {
        let first = try JSONValue(Meal.generationSchema, strict: true).data

        for _ in 0..<5 {
            #expect(try JSONValue(Meal.generationSchema, strict: true).data == first)
        }
    }

    private func text(_ value: JSONValue) -> String {
        String(decoding: value.data, as: UTF8.self)
    }

    private func propertyNames(_ schema: JSONValue) -> [String] {
        guard case .object(let properties)? = schema["properties"] else { return [] }
        return properties.members.map(\.key)
    }
}

@Generable
private struct Meal {
    @Guide(description: "The meal's name")
    var name: String
    var servings: Int
    var notes: String?
    var kind: Kind

    @Generable
    enum Kind {
        case breakfast
        case dinner
    }
}
