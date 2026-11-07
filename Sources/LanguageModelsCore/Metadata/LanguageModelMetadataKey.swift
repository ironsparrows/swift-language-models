/// The keys of the metadata facts that every provider module reports the same way, on the entries of an answer and on
/// the errors it ends in.
///
/// The response or tool-calls entry that ends an answer carries facts about it, such as the model that answered and
/// why it ended, and the answer's usage carries what it cost. A `LanguageModelError` a provider's failure becomes
/// carries the HTTP status and the provider's code for it. Each provider module writes these keys with the meaning
/// given here and leaves out a key its service doesn't report, so code that reads them works with any provider's
/// model. A provider module's own facts use keys of its own, with a prefix that names the module, such as `vendor.`.
///
/// Saved transcripts keep the keys, so their spellings never change.
public enum LanguageModelMetadataKey {
    /// The model that answered, in the provider's spelling of its id, which can differ from the one asked for when
    /// the service routes the request or a fallback answers. The answer's reasoning entry carries it too.
    public static let model = "model"

    /// The company whose servers ran the model, such as `Anthropic`, when the service names one. On the metadata of a
    /// `LanguageModelError`, the company that failed.
    public static let provider = "provider"

    /// The service's id for the answer.
    public static let responseID = "responseID"

    /// The service's id for the request that got the answer, which its support asks for. On the metadata of a
    /// `LanguageModelError`, the id of the request that failed.
    public static let requestID = "requestID"

    /// Why the answer ended, as a ``FinishReason`` raw value such as `length` when it reached its token limit.
    public static let finishReason = "finishReason"

    /// The processing tier that served the answer, which it's billed at, in the provider's own word for it.
    public static let serviceTier = "serviceTier"

    /// The web pages the answer cites, on its response entry, each a structure with the page's `url`, and its `title`,
    /// `excerpt`, `startOffset` and `endOffset` when known, which a provider module reads as ``Citation`` values.
    public static let citations = "citations"

    /// What the answer cost, in US dollars, when the service reports it.
    public static let cost = "cost"

    /// The prompt tokens written to the host's prompt cache.
    public static let cacheWriteTokenCount = "cacheWriteTokenCount"

    /// The web searches the service ran for the answer.
    public static let webSearchCount = "webSearchCount"

    /// The HTTP status of the failed request, on the metadata of a `LanguageModelError`, such as 429 for a rate limit.
    public static let status = "status"

    /// The provider's own code for the failure, in its own vocabulary, on the metadata of a `LanguageModelError`.
    public static let errorCode = "errorCode"
}
