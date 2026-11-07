package import FoundationModels
import LanguageModelsCore

/// What a dialect's `body(_:)` hook reads of a request: the settings the app asked for, and what the format's own
/// members carry.
///
/// Only an API format's executor creates one, so the hook sees the request as the format read it, and never the
/// transcript or the format's members themselves.
package struct BodyContext {
    /// Whether the model may or must call the session's tools, as the app asked.
    package let toolCallingMode: GenerationOptions.ToolCallingMode?

    /// Whether the session has tools, which the format sends as functions.
    package let hasSessionTools: Bool

    /// Whether the request has a response schema, which the format sends as its structured output.
    package let hasSchema: Bool

    /// The sampling settings the app asked for, within the format's temperature range.
    package let sampling: Sampling

    /// The reasoning level the app asked for, or `nil` for the model's default.
    package let reasoningLevel: ContextOptions.ReasoningLevel?

    /// Whether the request's input carries a PDF.
    package let carriesPDF: Bool

    /// The id of the transcript's first prompt, which stays the same for the whole session; `nil` before the first
    /// prompt.
    package let firstPromptID: String?

    /// - Parameters:
    ///   - request: Foundation Models' request.
    ///   - sampling: The request's sampling settings, as the format reads them.
    ///   - carriesPDF: Whether the format's input carries a PDF.
    package init(_ request: LanguageModelExecutorGenerationRequest, sampling: Sampling, carriesPDF: Bool) {
        toolCallingMode = request.generationOptions.toolCallingMode
        hasSessionTools = !request.enabledToolDefinitions.isEmpty
        hasSchema = request.schema != nil
        self.sampling = sampling
        reasoningLevel = request.contextOptions.reasoningLevel
        self.carriesPDF = carriesPDF
        firstPromptID = request.transcript.firstPromptID
    }
}

/// What a dialect's `headers(_:)` hook reads of a request.
///
/// Only an API format's executor creates one.
package struct HeaderContext: Sendable {
    /// The id of the transcript's first prompt, which stays the same for the whole session, so a provider that keeps a
    /// session's requests on one host can send it as the session's id; `nil` before the first prompt.
    package let firstPromptID: String?

    package init(_ request: LanguageModelExecutorGenerationRequest) {
        firstPromptID = request.transcript.firstPromptID
    }
}

extension Transcript {
    /// The id of the transcript's first prompt, which stays the same for the whole session, so a provider that keeps a
    /// session's requests on one host can send it as the session's id; `nil` before the first prompt.
    package var firstPromptID: String? {
        for case .prompt(let prompt) in self {
            return prompt.id
        }
        return nil
    }
}
