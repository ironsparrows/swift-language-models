import Foundation
public import FoundationModels
public import LanguageModels

// MARK: - Response

/// What a provider reported about an answer, read from the metadata of its response entry, or about a request that
/// ended in tool calls, read from its first call.
///
/// `Transcript.Response.openAICompatible` and `Transcript.ToolCalls.openAICompatible` read it. The response entry that
/// ends an answer carries the facts, and one that tool calls follow carries only the ``citations``. A fact the provider
/// didn't report is `nil`, and a list it didn't report is empty:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if case .response(let answer)? = response.transcriptEntries.last {
///     print("Request id, for the provider's support:", answer.openAICompatible.requestID ?? "none")
///     if answer.openAICompatible.finishReason == .length {
///         print("The answer was cut short at its token limit.")
///     }
/// }
/// ```
///
/// Its facts are the shared ones that `providerMetadata` also reads, with the model as an ``OpenAICompatibleModelID``.
public struct OpenAICompatibleResponseMetadata: Sendable, Hashable {
    /// The model that answered, as the provider names it, which can differ from the id the request named, such as a
    /// dated version of it.
    public let model: OpenAICompatibleModelID?

    /// The provider's id for the response, such as `chatcmpl-…`.
    public let responseID: String?

    /// The provider's id for the request, from the header it sends one in, such as `x-request-id`, which its support
    /// asks for.
    public let requestID: String?

    /// Why the answer ended, such as ``FinishReason/length`` when it reached its token limit.
    ///
    /// A text answer cut off at its token limit doesn't throw, so its reason is the way to tell. A guided answer, or
    /// tool calls, cut off there throw instead. A word the format doesn't know ends the answer as complete, unless a
    /// preset knows it: DeepSeek's words for an answer its servers cut short fail the answer, and Mistral's
    /// `model_length` counts as the token limit. Either way, the word is kept here as the provider sent it.
    public let finishReason: FinishReason?

    /// The web pages the answer cites, in the order the provider listed them.
    ///
    /// Citations point into the answer's text, so they're on the response entry even when tool calls end the answer.
    public let citations: [Citation]

    /// What the provider reported about the request's counts beyond Foundation Models' own.
    ///
    /// A response's own `usage` has only its last request's facts, so a response whose tool calls ran reads each
    /// earlier request's here, on the tool calls it asked for.
    public let usage: OpenAICompatibleUsageMetadata

    /// The facts in a response entry's metadata.
    init(_ metadata: [String: GeneratedContent]) {
        let shared = ProviderResponseMetadata(metadata)
        model = shared.model.map(OpenAICompatibleModelID.init(rawValue:))
        responseID = shared.responseID
        requestID = shared.requestID
        finishReason = shared.finishReason
        citations = shared.citations
        usage = OpenAICompatibleUsageMetadata(metadata)
    }
}

// MARK: - Usage

/// What a provider reported about an answer's counts beyond Foundation Models' own, read from its usage's metadata.
///
/// `LanguageModelSession.Usage.openAICompatible` reads it. The usage's own input, cached, output and reasoning token
/// counts hold the rest, and the package keeps no prices, so it reports no cost. A fact the provider didn't report is
/// `nil`:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if let written = response.usage.openAICompatible.cacheWriteTokenCount {
///     print("\(written) prompt tokens went into the provider's cache.")
/// }
/// ```
///
/// The facts are those of one request. A response whose tool calls ran has the last request's, and a session's own
/// `usage` keeps no metadata, so its facts are all `nil`. Each request's facts are also on the transcript entry that
/// ends it, which ``OpenAICompatibleResponseMetadata/usage`` reads.
public struct OpenAICompatibleUsageMetadata: Sendable, Hashable {
    /// The prompt tokens written to the provider's prompt cache, when its usage reports them.
    public let cacheWriteTokenCount: Int?

    /// The facts in a usage's metadata.
    fileprivate init(_ metadata: [String: GeneratedContent]) {
        cacheWriteTokenCount = ProviderUsageMetadata(metadata).cacheWriteTokenCount
    }
}

// MARK: - Error

/// What a provider reported about a failure that throws Foundation Models' `LanguageModelError`, read from the error's
/// metadata, with the name of the provider that failed.
///
/// `LanguageModelError.openAICompatible` reads it. A fact that wasn't reported is `nil`:
///
/// ```swift
/// do {
///     let response = try await session.respond(to: "Plan dinner.")
///     print(response.content)
/// } catch let error as LanguageModelError {
///     let facts = error.openAICompatible
///     print("\(facts.providerName ?? "A provider"): code \(facts.code?.rawValue ?? "none")")
/// }
/// ```
///
/// Its status, code and request id are the shared facts that `providerMetadata` also reads, with the code as an
/// ``OpenAICompatibleError/Code``.
public struct OpenAICompatibleErrorMetadata: Sendable, Hashable {
    /// The name of the provider that failed, as ``OpenAICompatibleProvider/name`` gives it, or `nil` for an error the
    /// module didn't throw.
    public let providerName: String?

    /// The HTTP status of the response that failed, such as 429 for a rate limit, or for an error in the stream, which
    /// arrives after the response's HTTP 200, the status its error names.
    public let status: Int?

    /// The code the failure would have as an ``OpenAICompatibleError``: the provider's code, or the package's code for
    /// the HTTP status, or for a status with no kind of its own the provider's error type, such as
    /// ``OpenAICompatibleError/Code/unmapped`` for a 429 that names neither.
    public let code: OpenAICompatibleError.Code?

    /// The provider's id for the request that failed, which its support asks for.
    public let requestID: String?

    /// The facts in an error's metadata.
    fileprivate init(_ metadata: [String: any Sendable]) {
        let shared = ProviderErrorMetadata(metadata)
        providerName = metadata[Key.providerName] as? String
        status = shared.status
        code = shared.code.map(OpenAICompatibleError.Code.init(rawValue:))
        requestID = shared.requestID
    }

    /// The metadata of a `LanguageModelError`: the status, the code, the request id, the company that ran the model and
    /// the provider's name.
    static func metadata(
        status: Int?, code: OpenAICompatibleError.Code, requestID: String?, providerName: String, host: String?
    ) -> [String: any Sendable] {
        var metadata = ProviderErrorMetadata(status: status, code: code.rawValue, host: host, requestID: requestID).contextMetadata
        metadata[Key.providerName] = providerName
        return metadata
    }
}

// MARK: - Reading

extension Transcript.Response {
    /// What the provider reported about the answer, such as the model that answered, the provider's id for the request
    /// and why the answer ended.
    public var openAICompatible: OpenAICompatibleResponseMetadata {
        OpenAICompatibleResponseMetadata(metadata)
    }
}

extension Transcript.ToolCalls {
    /// What the provider reported about the request that asked for these tool calls, such as the model that answered.
    ///
    /// Foundation Models keeps no readable metadata on the tool-calls entry itself, so the request's facts sit on its
    /// first call, and this reads them from there. A request that asked for several calls has one set of facts.
    public var openAICompatible: OpenAICompatibleResponseMetadata {
        OpenAICompatibleResponseMetadata(first?.metadata ?? [:])
    }
}

extension LanguageModelSession.Usage {
    /// What the provider reported about the answer's counts, such as the prompt tokens written to its cache.
    public var openAICompatible: OpenAICompatibleUsageMetadata {
        OpenAICompatibleUsageMetadata(metadata)
    }
}

extension LanguageModelError {
    /// What the provider reported about the failure, such as its code, the provider's id for the request and the name of
    /// the provider that failed.
    public var openAICompatible: OpenAICompatibleErrorMetadata {
        OpenAICompatibleErrorMetadata(contextMetadata)
    }
}

// MARK: - Keys

extension OpenAICompatibleResponseMetadata {
    /// The key of the `phase` of each of an answer's messages on the entry that ends an answer in the Responses format,
    /// which the format writes when a provider names phases, so each message goes back with its phase on later turns.
    ///
    /// It starts with `openAICompatible.`, so it never collides with another provider's keys. Saved transcripts keep it,
    /// so its spelling never changes.
    static let phasesKey = "openAICompatible.phases"

    /// The key of what an answer's server tools left, on the entry that ends an answer in the Responses format. The
    /// module sends no server tools, so no answer writes it.
    ///
    /// It starts with `openAICompatible.`, so it never collides with another provider's keys. Saved transcripts keep it,
    /// so its spelling never changes.
    static let serverToolsKey = "openAICompatible.serverTools"
}

/// The keys of the facts that only this module reports, which start with `openAICompatible.`, so they never collide with
/// another provider's keys.
private enum Key {
    /// The name of the provider that failed, on a `LanguageModelError`.
    static let providerName = "openAICompatible.providerName"
}
