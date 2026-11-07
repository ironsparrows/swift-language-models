package import LanguageModelsCore

/// OpenAI's Chat Completions format.
package enum ChatCompletions {}

extension ChatCompletions {
    /// The key of a member of a request's body: one of the format's, or one a provider adds.
    ///
    /// A provider's ``ChatCompletionsDialect/BodyExtras`` encodes its members under these keys, so each key is spelled
    /// once.
    package struct Member: ProviderVocabulary, CodingKey {
        package static let model: Self = "model"
        package static let messages: Self = "messages"
        package static let stream: Self = "stream"
        package static let tools: Self = "tools"
        package static let toolChoice: Self = "tool_choice"
        package static let responseFormat: Self = "response_format"
        package static let temperature: Self = "temperature"
        package static let topP: Self = "top_p"
        package static let seed: Self = "seed"
        package static let maxCompletionTokens: Self = "max_completion_tokens"
        package static let maxTokens: Self = "max_tokens"
        package static let metadata: Self = "metadata"

        /// The order the format writes its members in, each only when the request sets it.
        package static let formatOrder: [Member] = [
            model, messages, stream, tools, toolChoice, responseFormat, temperature, topP, seed, maxCompletionTokens, maxTokens, metadata,
        ]

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
