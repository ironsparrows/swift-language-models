/// A model whose request settings an app can change after creating it, such as how its requests retry.
///
/// Each provider has a configuration of its own, such as `OpenAIConfiguration`, which holds only the settings that
/// provider uses, built from the core's shared pieces, such as ``RequestRetries`` and ``ImageEncoding``. A
/// configuration conforms to a capability protocol for each piece it holds, such as ``RetryingConfiguration``, so code
/// that works with any provider asks for the capability it needs:
///
/// ```swift
/// /// The model without retries, so an evaluation counts each failure once.
/// func withoutRetries<Model: ConfigurableLanguageModel>(_ model: Model) -> Model
/// where Model.Configuration: RetryingConfiguration {
///     var model = model
///     model.configuration.retries = .disabled
///     return model
/// }
/// ```
///
/// A model whose configuration doesn't hold a piece can't be passed where the piece is needed, so a setting is never
/// silently ignored.
///
/// The configuration is what an app sets. Foundation Models reads the model's `executorConfiguration` instead, which
/// the model makes from its configuration and authentication.
public protocol ConfigurableLanguageModel: DetailedLanguageModel {
    /// The provider's request settings, such as `OpenAIConfiguration`.
    associatedtype Configuration: Sendable, Hashable

    /// How the model's requests are sent. A change applies to the next request.
    var configuration: Configuration { get set }
}

/// A configuration whose requests retry, as ``RequestRetries`` says.
public protocol RetryingConfiguration {
    /// How a request that fails before any data arrives is sent again.
    var retries: RequestRetries { get set }
}

/// A configuration whose requests send image attachments, encoded as ``ImageEncoding`` says.
public protocol ImageEncodingConfiguration {
    /// How image attachments are encoded before they're sent.
    var images: ImageEncoding { get set }
}
