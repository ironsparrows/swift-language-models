import Foundation
import FoundationModels
import Testing

@testable import LanguageModelsCore

@Suite("A model's effort type")
struct EffortsOfTests {
    typealias Effort = Efforts.Of<EffortsOfTestModel>

    @Test func `the effort type offers the levels the model accepts, highest first`() {
        #expect(Effort.allCases == [.high, .off])
    }

    @Test(arguments: [("high", true), ("none", true), ("low", true), ("max", false), ("", false)])
    func `a word the model accepts, or accepted before, makes an effort, and no other word does`(word: String, makesEffort: Bool) {
        #expect((Effort(rawValue: word) != nil) == makesEffort)
    }

    @Test(arguments: [(Effort.high, ContextOptions.ReasoningLevel.custom("high")), (.off, .off)])
    func `an effort asks for the reasoning level named after its word`(effort: Effort, level: ContextOptions.ReasoningLevel) {
        #expect(effort.reasoningLevel == level)
    }

    @Test func `a dictionary keyed by effort encodes as an object, and an unknown word fails to decode`() throws {
        let data = try JSONEncoder().encode([Effort.high: 1])

        #expect(String(decoding: data, as: UTF8.self) == #"{"high":1}"#)
        #expect(try JSONDecoder().decode([Effort: Int].self, from: data) == [.high: 1])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Effort: Int].self, from: Data(#"{"max":1}"#.utf8)) }
    }

    @Test func `an effort encodes as its word and reads back`() throws {
        let data = try JSONEncoder().encode([Effort.high, .off])

        #expect(String(decoding: data, as: UTF8.self) == #"["high","none"]"#)
        #expect(try JSONDecoder().decode([Effort].self, from: data) == [.high, .off])
    }

    @Test func `an effort prints as its word`() {
        #expect([Effort.high, .off].map { "\($0)" } == ["high", "none"])
    }

    @Test func `a word the model never accepted doesn't decode`() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Effort.self, from: Data(#""max""#.utf8)) }
    }
}

/// A model that accepts `high` and `none`, and accepted `low` before.
enum EffortsOfTestModel: Efforts.List {
    static var efforts: [String] { ["high", "none"] }
    static var removedEfforts: [String] { ["low"] }
}

extension Efforts.Of where Tag == EffortsOfTestModel {
    static var high: Self { Self(listed: "high") }
    static var off: Self { Self(listed: "none") }
}
