public import FoundationModels
public import LanguageModels

// MARK: - Response

/// What OpenAI reported about an answer, read from the metadata of its response entry, or about a request that ended
/// in tool calls, read from its first call.
///
/// `Transcript.Response.openAI` and `Transcript.ToolCalls.openAI` read it. The response entry that ends an answer
/// carries the facts, and one that tool calls follow carries only the ``citations``. A fact OpenAI didn't report is
/// `nil`, and a list it didn't report is empty:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if case .response(let answer)? = response.transcriptEntries.last {
///     print("Request id, for OpenAI's support:", answer.openAI.requestID ?? "none")
///     if answer.openAI.finishReason == .length {
///         print("The answer was cut short at its token limit.")
///     }
/// }
/// ```
///
/// Each fact comes from a key that saved transcripts keep. The keys of ``model``, ``responseID``, ``requestID``,
/// ``finishReason``, ``serviceTier`` and ``citations`` are `LanguageModelMetadataKey`'s, which every provider module
/// shares, and ``messages`` comes from ``OpenAIMetadataKey/phases``.
public struct OpenAIResponseMetadata: Sendable, Hashable {
    /// The model that answered, as OpenAI names it, such as the dated snapshot `gpt-5-nano-2025-08-07` for
    /// `gpt-5-nano`.
    public let model: OpenAIModelID?

    /// OpenAI's id for the response, such as `resp_…`.
    public let responseID: String?

    /// OpenAI's id for the request, which its support asks for.
    public let requestID: String?

    /// Why the answer ended, such as ``FinishReason/length`` when it reached its token limit.
    ///
    /// A text answer cut off at its token limit doesn't throw, so its reason is the way to tell. A guided answer, or
    /// tool calls, cut off there throw instead.
    public let finishReason: FinishReason?

    /// The processing tier that served the answer, which it's billed at. It can differ from
    /// ``OpenAIOptions/serviceTier``, such as ``OpenAIServiceTier/default`` for a request that asked for
    /// ``OpenAIServiceTier/auto``.
    public let serviceTier: OpenAIServiceTier?

    /// The web pages the answer cites, in the order OpenAI listed them.
    ///
    /// Citations point into the answer's text, so they're on the response entry even when tool calls end the answer.
    public let citations: [Citation]

    /// The answer's messages, in their order, each with its phase, such as a ``Phase/commentary`` preamble before the
    /// ``Phase/finalAnswer``, or empty when the model names no phases and the answer holds no message out of its text.
    public let messages: [Message]

    /// What OpenAI reported about the request's counts, such as the prompt tokens written to its cache.
    ///
    /// A response's own `usage` has only its last request's facts, so a response whose tool calls ran reads each
    /// earlier request's here, on the tool calls it asked for.
    public let usage: OpenAIUsageMetadata

    /// The facts in a response entry's metadata.
    init(_ metadata: [String: GeneratedContent]) {
        let values = MetadataValues(metadata)
        model = values.string(LanguageModelMetadataKey.model).map(OpenAIModelID.init(rawValue:))
        responseID = values.string(LanguageModelMetadataKey.responseID)
        requestID = values.string(LanguageModelMetadataKey.requestID)
        finishReason = values.string(LanguageModelMetadataKey.finishReason).map(FinishReason.init(rawValue:))
        serviceTier = values.string(LanguageModelMetadataKey.serviceTier).map(OpenAIServiceTier.init(rawValue:))
        citations = values.array(LanguageModelMetadataKey.citations).compactMap(Citation.init(metadataValue:))
        messages = values.structures(OpenAIMetadataKey.phases).compactMap(Message.init)
        usage = OpenAIUsageMetadata(metadata)
    }
}

extension OpenAIResponseMetadata {
    /// One of an answer's messages: its phase, and where its text is.
    ///
    /// The answer's text joins the text of its messages in their order, so a message's ``length`` tells where its own
    /// text ends. A guided answer decodes only its first message with no phase or the ``Phase/finalAnswer`` phase, so
    /// the text of its other messages, such as a ``Phase/commentary`` preamble, stays out of the answer's text and is
    /// in ``heldText`` instead.
    public struct Message: Sendable, Hashable {
        /// The message's phase, or `nil` when OpenAI named none.
        public let phase: Phase?

        /// The length of the message's text in the answer's text, in characters, or 0 when ``heldText`` holds it.
        public let length: Int

        /// The message's text when it's held out of the answer's text, or `nil` when the answer's text holds it.
        public let heldText: String?

        /// A message read from an element of ``OpenAIMetadataKey/phases``, or `nil` for an element that isn't one.
        fileprivate init?(_ values: MetadataValues) {
            guard let length = values.integer(Field.length) else { return nil }
            phase = values.string(Field.phase).map(Phase.init(rawValue:))
            self.length = length
            heldText = values.string(Field.heldText)
        }
    }

    /// The phase of one of an answer's messages, such as ``commentary`` or ``finalAnswer``.
    public struct Phase: ProviderVocabulary {
        /// A preamble the model writes before it calls a tool or answers, such as what it's about to do.
        public static let commentary: Self = "commentary"

        /// The message that holds the answer.
        public static let finalAnswer: Self = "final_answer"

        /// The phase as OpenAI's API spells it.
        public let rawValue: String

        /// Creates a phase from OpenAI's spelling of it.
        ///
        /// - Parameter rawValue: The phase, such as `"commentary"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// The names of the fields of an element of ``OpenAIMetadataKey/phases``, which saved transcripts keep.
    private enum Field {
        static let phase = "phase"
        static let length = "length"
        static let heldText = "heldText"
    }
}

// MARK: - Usage

/// What OpenAI reported about an answer's counts beyond Foundation Models' own, read from its usage's metadata.
///
/// `LanguageModelSession.Usage.openAI` reads it. The usage's own input, cached, output and reasoning token counts hold
/// the rest, and the package keeps no prices, so it reports no cost. A fact OpenAI didn't report is `nil`:
///
/// ```swift
/// let response = try await session.respond(to: "Plan dinner.")
/// if let written = response.usage.openAI.cacheWriteTokenCount {
///     print("\(written) prompt tokens went into OpenAI's cache.")
/// }
/// ```
///
/// The facts are those of one request. A response whose tool calls ran has the last request's, and a session's own
/// `usage` keeps no metadata, so its facts are all `nil`. Each request's facts are also on the transcript entry that
/// ends it, which ``OpenAIResponseMetadata/usage`` reads.
public struct OpenAIUsageMetadata: Sendable, Hashable {
    /// The prompt tokens written to OpenAI's prompt cache.
    public let cacheWriteTokenCount: Int?

    /// The facts in a usage's metadata.
    init(_ metadata: [String: GeneratedContent]) {
        cacheWriteTokenCount = MetadataValues(metadata).integer(LanguageModelMetadataKey.cacheWriteTokenCount)
    }
}

// MARK: - Error

/// What OpenAI reported about a failure that throws Foundation Models' `LanguageModelError`, in OpenAI's own words,
/// read from the error's metadata.
///
/// `LanguageModelError.openAI` reads it. A fact OpenAI didn't report is `nil`:
///
/// ```swift
/// do {
///     let response = try await session.respond(to: "Plan dinner.")
///     print(response.content)
/// } catch let error as LanguageModelError {
///     print("Code \(error.openAI.errorCode?.rawValue ?? "none"), request id \(error.openAI.requestID ?? "none")")
/// }
/// ```
///
/// Its facts are the shared ones that `providerMetadata` also reads, with the code as an ``OpenAIError/Code``.
public struct OpenAIErrorMetadata: Sendable, Hashable {
    /// The HTTP status of the response that failed, such as 429 for a rate limit, or `nil` for a failure in the stream,
    /// which arrives after the response's HTTP 200.
    public let status: Int?

    /// The code the failure would have as an ``OpenAIError``: OpenAI's code or error type, or the package's code for
    /// the HTTP status, such as ``OpenAIError/Code/unmapped`` for a 429 without one.
    public let errorCode: OpenAIError.Code?

    /// OpenAI's id for the request that failed, which its support asks for.
    public let requestID: String?

    /// The facts in an error's metadata.
    init(_ metadata: [String: any Sendable]) {
        status = metadata[LanguageModelMetadataKey.status] as? Int
        errorCode = (metadata[LanguageModelMetadataKey.errorCode] as? String).map(OpenAIError.Code.init(rawValue:))
        requestID = metadata[LanguageModelMetadataKey.requestID] as? String
    }
}

// MARK: - Reading

extension Transcript.Response {
    /// What OpenAI reported about the answer, such as the model that answered, OpenAI's id for the request and why
    /// the answer ended.
    public var openAI: OpenAIResponseMetadata {
        OpenAIResponseMetadata(metadata)
    }
}

extension Transcript.ToolCalls {
    /// What OpenAI reported about the request that asked for these tool calls, such as the model that answered and the
    /// phases of the messages before them.
    ///
    /// Foundation Models keeps no readable metadata on the tool-calls entry itself, so the request's facts sit on its
    /// first call, and this reads them from there. A request that asked for several calls has one set of facts.
    public var openAI: OpenAIResponseMetadata {
        OpenAIResponseMetadata(first?.metadata ?? [:])
    }
}

extension LanguageModelSession.Usage {
    /// What OpenAI reported about the answer's counts, such as the prompt tokens written to its cache.
    public var openAI: OpenAIUsageMetadata {
        OpenAIUsageMetadata(metadata)
    }
}

extension LanguageModelError {
    /// What OpenAI reported about the failure, such as its code and OpenAI's id for the request.
    public var openAI: OpenAIErrorMetadata {
        OpenAIErrorMetadata(contextMetadata)
    }
}

// MARK: - Keys

/// The keys of the metadata facts that only OpenAI's models report about an answer, which start with `openAI.`, so they
/// never collide with another provider's keys.
///
/// The facts every provider reports, such as the model, the response id and the request id, use the bare keys of
/// `LanguageModelMetadataKey`. Saved transcripts keep the keys, so their spellings never change.
public enum OpenAIMetadataKey {
    /// The `phase` of each of an answer's messages, such as `commentary` or `final_answer`, on the entry that ends the
    /// answer: a list of structures with a `phase` and the `length` of the message's text, in characters. A guided
    /// answer's message that doesn't decode, such as a `commentary` preamble, stays out of the answer's text, so its
    /// structure keeps the text itself under `heldText`, with a `length` of 0. Each message goes back with its phase
    /// on later turns. ``OpenAIResponseMetadata/messages`` reads them.
    public static let phases = "openAI.phases"
}
