/// OpenAI's Chat Completions format.
package enum ChatCompletions {}

/// What a chunk's provider members add to the answer, as a dialect's ``ChatCompletionsDialect/observe(_:into:)``
/// returns it.
package struct ChunkOutput {
    /// Reasoning text to show before the chunk's answer text, empty to start the reasoning entry without text, or `nil`
    /// when the chunk carries no reasoning.
    package var reasoning: String?

    /// Data the model generated, such as an image, each sent as a data entry of its own after the chunk's other
    /// output.
    package var generatedData: [GeneratedData]

    package init(reasoning: String? = nil, generatedData: [GeneratedData] = []) {
        self.reasoning = reasoning
        self.generatedData = generatedData
    }
}

/// No members: what a provider adds to a request, or reads from a response, when it adds or reads nothing beyond the
/// format's own.
///
/// It encodes as an empty object, which adds no member, and decodes from any object.
package struct NoMembers: Codable, Sendable, Hashable {
    package init() {}
}
