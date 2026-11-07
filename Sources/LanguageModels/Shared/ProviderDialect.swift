package import Foundation
import LanguageModelsCore

/// What every API format needs from a provider, whatever the format: who it is, the model a request is for, where its
/// API lives, how requests reach it, and its own error.
///
/// `ChatCompletionsDialect` refines this protocol with the hooks of its format, so a provider that moves to another
/// format keeps these requirements as they are. A dialect is created for each request, by the format's executor, from
/// the model and the model's own request executor, so a request executor can only run a dialect made for its model.
package protocol ProviderDialect: Sendable {
    /// The model whose requests the dialect sends.
    associatedtype Model: DetailedLanguageModel

    /// The provider's word for a model, such as `OpenRouterModelID`.
    associatedtype ModelID: ProviderVocabulary

    /// The `error` object of the provider's failed responses, `{"error": {…}}`. The default is the one OpenAI's formats
    /// send.
    associatedtype ErrorBody: Decodable & Sendable = APIErrorBody

    /// The provider's own public error, for the failures Foundation Models has no case for.
    associatedtype ProviderError: Error & Sendable

    /// The provider's name, such as `OpenRouter`, as the log and error messages name it.
    static var name: String { get }

    /// The dialect of one request.
    ///
    /// - Parameters:
    ///   - model: The model the request is for.
    ///   - executor: The model's request executor, with its configuration.
    init(model: Model, executor: Model.RequestExecutor)

    /// The model the request names.
    var modelID: ModelID { get }

    /// Where the provider's API lives; each format's calls go under it.
    ///
    /// - Throws: The provider's error when there's no valid base URL.
    var baseURL: URL { get throws(ProviderError) }

    /// How the request reaches the provider.
    var connection: Connection { get }

    /// How the request's image attachments are encoded, from the provider's configuration. A provider whose
    /// configuration has no image settings keeps the default, ``ImageEncoding/standard``.
    var imageEncoding: ImageEncoding { get }
}

extension ProviderDialect {
    package var imageEncoding: ImageEncoding { .standard }

    /// The logger of the provider's category, named after the provider.
    package static var logger: PackageLogger {
        PackageLogger(category: name)
    }
}
