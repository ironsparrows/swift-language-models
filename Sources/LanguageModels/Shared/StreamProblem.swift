import LanguageModelsCore

/// Why a format couldn't use a provider's streamed response, which a ``RequestFailure`` puts in words.
///
/// Only a shared model reports one.
package enum StreamProblem: Error, Equatable {
    /// An event's data isn't one the format can read, with the reason it couldn't be read.
    case unreadableEvent(String)

    /// The stream ended before it was complete.
    case cutOff

    /// A tool call never got its name.
    case toolCallWithoutName

    /// A tool call's arguments aren't a whole JSON object, such as ones that stop partway.
    case incompleteToolArguments(toolName: String)

    /// The answer reached its token limit inside a tool call.
    case tokenLimitInToolCall

    /// What went wrong, as an error says it.
    ///
    /// - Parameter provider: The provider's name, such as `OpenRouter`.
    /// - Returns: A sentence for the error's message.
    package func message(provider: String) -> String {
        switch self {
        case .unreadableEvent(let reason): "\(provider) sent an event that couldn't be read: \(reason)"
        case .cutOff: "The response ended before it was complete."
        case .toolCallWithoutName: "The model sent a tool call without its name."
        case .incompleteToolArguments(let toolName): "The model sent arguments for \(toolName) that aren't a whole JSON object."
        case .tokenLimitInToolCall: "The answer reached its token limit inside a tool call."
        }
    }
}
