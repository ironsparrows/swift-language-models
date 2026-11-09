import Foundation

/// Facts about the formats' APIs that the model and its exchange rely on, whatever the provider.
enum API {
    /// The origin of reasoning that a model wrote through a provider in a format: `openai-compatible/` for Chat
    /// Completions or `openai-compatible-responses/` for Responses, then the provider's name in lowercase, so reasoning
    /// never goes back to another provider or into the other format, whatever the provider's name.
    ///
    /// Saved transcripts keep these values, so their spelling never changes.
    ///
    /// - Parameters:
    ///   - provider: The provider's name in lowercase.
    ///   - format: The format the reasoning came in.
    /// - Returns: The origin.
    static func reasoningOrigin(provider: String, format: OpenAICompatibleProvider.Format) -> String {
        switch format {
        case .chatCompletions: "openai-compatible/\(provider)"
        case .responses: "openai-compatible-responses/\(provider)"
        }
    }

    /// The names of the HTTP headers the module reads.
    enum Header {
        /// The media type of a response's body.
        static let contentType = "Content-Type"

        /// The provider's id for a request.
        static let requestID = "x-request-id"
    }
}
