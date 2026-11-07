package import LanguageModelsCore

/// OpenAI's Responses format.
package enum Responses {}

extension Responses {
    /// The key of a member of a request's body: one of the format's, or one a provider adds.
    ///
    /// A provider's ``ResponsesDialect/BodyExtras`` encodes its members under these keys, so each key is spelled once.
    package struct Member: ProviderVocabulary, CodingKey {
        package static let model: Self = "model"
        package static let input: Self = "input"
        package static let stream: Self = "stream"
        package static let store: Self = "store"
        package static let include: Self = "include"
        package static let tools: Self = "tools"
        package static let toolChoice: Self = "tool_choice"
        package static let text: Self = "text"
        package static let reasoning: Self = "reasoning"
        package static let temperature: Self = "temperature"
        package static let topP: Self = "top_p"
        package static let maxOutputTokens: Self = "max_output_tokens"
        package static let metadata: Self = "metadata"

        package let rawValue: String

        package init(rawValue: String) {
            self.rawValue = rawValue
        }

        package var description: String { rawValue }

        package var stringValue: String { rawValue }

        package init(stringValue: String) {
            rawValue = stringValue
        }

        package var intValue: Int? { nil }

        package init?(intValue: Int) {
            nil
        }
    }
}
