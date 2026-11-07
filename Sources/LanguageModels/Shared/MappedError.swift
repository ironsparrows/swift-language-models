package import FoundationModels
import LanguageModelsCore

/// The error that a provider's failure becomes: Foundation Models' own when it has a case for the failure, so apps
/// handle it the same way for every model, and otherwise the provider's.
///
/// A provider's error mapping returns one, so it can't throw any other kind of error, such as a format's.
package enum MappedError<ProviderError: Error>: Sendable {
    /// A failure Foundation Models has a case for, such as a rate limit.
    case languageModel(LanguageModelError)

    /// Any other failure, as the provider's own public error.
    case provider(ProviderError)

    /// The error to throw.
    package var error: any Error {
        switch self {
        case .languageModel(let error): error
        case .provider(let error): error
        }
    }
}
