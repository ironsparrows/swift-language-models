public import FoundationModels

/// What ``DetailedLanguageModelExecutor`` reads from a model before each request: its details and its fallbacks.
///
/// A provider module's model conforms to ``DetailedLanguageModel``, which refines this protocol. This protocol exists
/// so that a request executor's model has a type the executor can read, since ``DetailedLanguageModel`` names the
/// executor itself.
public protocol DetailedLanguageModelBase: LanguageModel {
    /// The type that describes the model.
    associatedtype Details: ModelDetails

    /// The type that describes the models the provider tries when this one fails.
    associatedtype Fallback: ModelDetails

    /// What the provider reports about this model.
    var details: Details { get }

    /// The models the provider tries, in order, when this one fails. Empty when the provider has no fallbacks.
    var fallbacks: [Fallback] { get }
}

/// A language model that carries what its provider reports about it.
///
/// The model's capabilities, and the kinds of data it accepts and generates, come from its details. Its executor is a
/// ``DetailedLanguageModelExecutor`` of the provider module's ``RequestExecutor``, which checks each request before the
/// request executor sends it, and each answer after.
public protocol DetailedLanguageModel: DetailedLanguageModelBase
where Executor == DetailedLanguageModelExecutor<RequestExecutor> {
    /// The type that sends the model's requests.
    associatedtype RequestExecutor: DetailedLanguageModelRequestExecutor where RequestExecutor.Model == Self
}

extension DetailedLanguageModel {
    /// The capabilities that the model's details and each of its fallbacks' list, since any of them may answer.
    ///
    /// A model without fallbacks has its details' capabilities. With fallbacks, only tool calling, guided
    /// generation, reasoning and vision can be kept, the capabilities Foundation Models names.
    public var capabilities: LanguageModelCapabilities {
        guard !fallbacks.isEmpty else { return details.capabilities }
        let named: [LanguageModelCapabilities.Capability] = [.toolCalling, .guidedGeneration, .reasoning, .vision]
        return LanguageModelCapabilities(
            named.filter { capability in
                details.capabilities.contains(capability) && fallbacks.allSatisfy { $0.capabilities.contains(capability) }
            }
        )
    }
}
