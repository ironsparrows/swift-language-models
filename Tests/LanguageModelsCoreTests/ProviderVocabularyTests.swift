import Foundation
import LanguageModelsCore
import Testing

@Suite("Provider vocabulary")
struct ProviderVocabularyTests {
    @Test func `a dictionary keyed by a vocabulary type encodes as an object and reads back`() throws {
        let data = try JSONEncoder().encode([TestModelID("vendor/model"): 1])

        #expect(String(decoding: data, as: UTF8.self) == #"{"vendor\/model":1}"#)
        #expect(try JSONDecoder().decode([TestModelID: Int].self, from: data) == ["vendor/model": 1])
    }
}
