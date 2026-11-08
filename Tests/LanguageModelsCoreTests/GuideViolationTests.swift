import Foundation
import Testing
@testable import LanguageModelsCore

@Suite("Guide violations")
struct GuideViolationTests {
    @Test(arguments: [
        (#"{"type":"integer","minimum":5,"maximum":120}"#, "2", "The answer is 2, below the minimum of 5"),
        (#"{"type":"integer","minimum":5,"maximum":120}"#, "121", "The answer is 121, above the maximum of 120"),
        (#"{"type":"number","exclusiveMinimum":0}"#, "0", "The answer is 0, not above 0"),
        (#"{"type":"number","exclusiveMaximum":1}"#, "1.5", "The answer is 1.5, not below 1"),
        (#"{"type":"array","items":{"type":"string"},"minItems":3}"#, #"["Boil."]"#, "The answer has 1 item, fewer than the minimum of 3"),
        (#"{"type":"array","items":{"type":"string"},"maxItems":1}"#, #"["a","b"]"#, "The answer has 2 items, more than the maximum of 1"),
        (#"{"type":"string","minLength":2}"#, #""a""#, #"The answer is "a", shorter than the minimum of 2 characters"#),
        (#"{"type":"string","maxLength":2}"#, #""abc""#, #"The answer is "abc", longer than the maximum of 2 characters"#),
        (#"{"type":"string","pattern":"[A-Z].*"}"#, #""soup""#, #"The answer is "soup", which doesn't match the pattern [A-Z].*"#),
        (#"{"type":"string","enum":["low","high"]}"#, #""mid""#, #"The answer is "mid", not one of "low", "high""#),
        (#"{"type":"string","const":"soup"}"#, #""stew""#, #"The answer is "stew", not "soup""#),
        (
            #"{"type":"integer","minimum":9007199254740993}"#, "9007199254740992",
            "The answer is 9007199254740992, below the minimum of 9007199254740993"
        ),
        (
            #"{"type":"integer","const":90071992547409930001}"#, "90071992547409930000",
            "The answer is 90071992547409930000, not 90071992547409930001"
        ),
    ])
    func `a value that breaks a constraint reports it`(schema: String, value: String, expected: String) throws {
        #expect(try json(value).violations(of: json(schema)).map(\.description) == [expected])
    }

    @Test(arguments: [
        (#"{"type":"integer","minimum":5,"maximum":120}"#, "5"),
        (#"{"type":"integer","minimum":1}"#, "2.0"),
        (#"{"type":"string","pattern":"[A-Z]"}"#, #""a Soup""#),
        (#"{"type":"number","enum":[1,2]}"#, "2.0"),
        (#"{"type":"string","pattern":"["}"#, #""anything""#),
        (#"{"type":"integer","minimum":5}"#, #""not a number""#),
        (##"{"$ref":"#"}"##, "1"),
        (#"{"type":"string","pattern":"^[A-Z]"}"#, #""E\u0301clair""#),
        (#"{"type":"string","pattern":"^..$"}"#, #""\ud83c\uddec\ud83c\uddf7""#),
        (#"{"type":"string","pattern":"\\n"}"#, #""a\r\nb""#),
    ])
    func `a value that meets its constraints, or that they don't apply to, reports nothing`(schema: String, value: String) throws {
        #expect(try json(value).violations(of: json(schema)).isEmpty)
    }

    @Test func `a nested value is named by its path, through references into the definitions`() throws {
        let schema = try json(
            #"""
            {"type":"object","properties":{
                "ingredients":{"type":"array","items":{"$ref":"#/$defs/Ingredient"}},
                "servings":{"type":"integer","minimum":1}},
             "$defs":{"Ingredient":{"type":"object","properties":{"grams":{"type":"integer","minimum":1}}}}}
            """#)
        let answer = try json(#"{"ingredients":[{"grams":200},{"grams":0}],"servings":0}"#)

        let violations = answer.violations(of: schema)

        #expect(
            violations.map(\.description) == ["ingredients[1].grams is 0, below the minimum of 1", "servings is 0, below the minimum of 1"])
        #expect(violations.map(\.keyword) == ["minimum", "minimum"])
    }

    @Test(arguments: [("null", 0), (#""Soup""#, 0), (#""soup""#, 1)])
    func `an optional value is checked unless it's null`(value: String, count: Int) throws {
        let schema = try json(#"{"anyOf":[{"type":"string","pattern":"^[A-Z]"},{"type":"null"}]}"#)

        #expect(try json(value).violations(of: schema).count == count)
    }

    @Test(arguments: [
        (#"{"type":"circle","value":{"radius":0}}"#, "value.radius is 0, below the minimum of 1"),
        (#"{"type":"square","side":0}"#, "side is 0, below the minimum of 1"),
    ])
    func `an enum's case is checked against the branch it names`(value: String, expected: String) throws {
        let schema = try json(
            #"""
            {"anyOf":[{"$ref":"#/$defs/Circle"},{"$ref":"#/$defs/Square"}],
             "$defs":{
                "Circle":{"type":"object","properties":{"type":{"const":"circle"},"value":{"type":"object","properties":{"radius":{"type":"integer","minimum":1}}}}},
                "Square":{"type":"object","properties":{"type":{"const":"square"},"side":{"type":"integer","minimum":1}}}}}
            """#)

        #expect(try json(value).violations(of: schema).map(\.description) == [expected])
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONValue(json: Data(text.utf8))
    }
}
