package import FoundationModels
import LanguageModelsCore

/// How a provider speaks OpenAI's Chat Completions format, which the format's executor sends requests in.
///
/// The executor owns the whole exchange: it builds the body from Foundation Models' request, authenticates and sends
/// it, retries as the provider's connection says and once with the portable schema when a host rejects a constraint,
/// streams the answer into Foundation Models' channel, maps a failed connection and logs. A dialect adds only what its
/// provider does differently, through hooks that each get what that hook needs and nothing else:
///
/// - ``headers(_:)``: headers beyond the authentication's.
/// - ``body(_:)``: the provider's own members, as ``BodyExtras``, and the few choices it makes about the format's.
/// - ``lists(_:)`` with ``listedMembers``: members sent only when the models take them.
/// - ``check(_:in:)`` with ``extraMedia``: the attachments its models take.
/// - ``replays(_:)`` and ``replayMembers(_:)``: the reasoning it sends back, as ``ReplayMembers``.
/// - ``streamState(_:)``, ``observe(_:into:)`` and ``facts(of:)``: what its chunks carry beyond the format's, as
///   ``ChunkExtras``, tracked across the answer in ``StreamState``.
/// - ``error(for:)``: what each failure becomes.
///
/// Every hook has a default that adds nothing, except ``error(for:)``, which turns failures into the provider's own
/// public error. A hook whose types the dialect sets has no default: a dialect that sets ``ChunkExtras`` and doesn't
/// read them in ``observe(_:into:)`` doesn't compile. Implement the hooks that have a default in the extension that
/// declares the conformance: only there does a misspelled one draw a warning instead of silently keeping the default.
///
/// A request executor runs a dialect with
/// ``LanguageModels/DetailedLanguageModelRequestExecutor/respond(to:model:streamingInto:as:)``, the format's only way
/// in.
package protocol ChatCompletionsDialect: ProviderDialect {
    /// The provider's own members of a request's body. Their keys are ``ChatCompletions/Member`` values, never the format's own.
    associatedtype BodyExtras: Encodable = NoMembers

    /// The members an assistant message carries after its content for the reasoning it sends back.
    associatedtype ReplayMembers: Encodable = NoMembers

    /// The provider's own members of a streamed chunk, decoded from the same JSON as the format's.
    associatedtype ChunkExtras: Decodable = NoMembers

    /// What the provider tracks across one streamed answer.
    associatedtype StreamState: Sendable = Void

    /// The origin the reasoning entries of the provider's answers carry, so that only its own reasoning goes back.
    /// Saved transcripts keep it, so it never changes. The default is the provider's name in lowercase.
    static var reasoningOrigin: ReasoningOrigin { get }

    /// The order of a body's members, the format's and the provider's, which a host's prompt cache depends on. A
    /// member it doesn't name goes after the ones it does, in the order it was written. The default is the format's
    /// order, ``ChatCompletions/Member/formatOrder``.
    static var memberOrder: [ChatCompletions.Member] { get }

    /// The members, the format's or the provider's, that go out only when ``lists(_:)`` says the models take them. A
    /// member left out is logged. The default is none.
    static var listedMembers: Set<ChatCompletions.Member> { get }

    /// The kinds of audio and movies the provider takes beyond the format's WAV and MP3, in the order they're
    /// matched. The default is none.
    static var extraMedia: [MediaPart] { get }

    /// The provider's headers for a request, which take precedence over the authentication's. The default is none.
    func headers(_ context: HeaderContext) -> [HTTPHeaderName: String]

    /// Whether the models take a member of ``listedMembers``. The default takes every one.
    func lists(_ member: ChatCompletions.Member) -> Bool

    /// Checks that the models take an attachment, before the format reads it. The default takes every one.
    ///
    /// - Throws: `LanguageModelError` for an attachment a model doesn't take.
    func check(_ attachment: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError)

    /// The provider's members of a request's body, and its choices about the format's own.
    ///
    /// - Throws: `LanguageModelError` when the provider can't send the request.
    func body(_ context: BodyContext) throws(LanguageModelError) -> ChatCompletionsBodyPlan<BodyExtras>

    /// Whether one of the provider's own reasoning entries goes back in a later request. Reasoning another provider
    /// wrote never does. The default sends back every one.
    func replays(_ reasoning: Transcript.Reasoning) -> Bool

    /// The members an assistant message carries for the reasoning it sends back. A member whose value is an empty
    /// list or empty text carries no reasoning, so an answer with nothing else isn't sent back.
    ///
    /// - Parameter reasoning: The answer's reasoning entries that go back, in their order.
    /// - Returns: The members, after the message's content.
    func replayMembers(_ reasoning: [ReplayedReasoning]) -> ReplayMembers

    /// What the provider tracks across one answer, before its first chunk.
    ///
    /// - Parameter headers: The headers of the response whose stream carries the answer.
    /// - Returns: The state before the answer's first chunk.
    func streamState(_ headers: ResponseHeaders) -> StreamState

    /// Reads the provider's members of one chunk, in the order chunks arrive.
    ///
    /// - Returns: What the chunk adds to the answer beyond the format's own members.
    func observe(_ extras: ChunkExtras, into state: inout StreamState) -> ChunkOutput

    /// The facts the provider adds to the answer once it's over, or to an error before then.
    func facts(of state: StreamState) -> AnswerAdditions

    /// What a failure becomes: Foundation Models' error when it has a case for it, otherwise the provider's own.
    func error(for failure: ChatCompletionsFailure<Self>) -> MappedError<ProviderError>
}

extension ChatCompletionsDialect {
    package static var reasoningOrigin: ReasoningOrigin { ReasoningOrigin(rawValue: name.lowercased()) }

    package static var memberOrder: [ChatCompletions.Member] { ChatCompletions.Member.formatOrder }

    package static var listedMembers: Set<ChatCompletions.Member> { [] }

    package static var extraMedia: [MediaPart] { [] }

    package func headers(_ context: HeaderContext) -> [HTTPHeaderName: String] { [:] }

    package func lists(_ member: ChatCompletions.Member) -> Bool { true }

    package func check(_ attachment: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {}

    package func replays(_ reasoning: Transcript.Reasoning) -> Bool { true }
}

extension ChatCompletionsDialect where BodyExtras == NoMembers {
    package func body(_ context: BodyContext) throws(LanguageModelError) -> ChatCompletionsBodyPlan<NoMembers> {
        ChatCompletionsBodyPlan(extras: NoMembers())
    }
}

extension ChatCompletionsDialect where ReplayMembers == NoMembers {
    package func replayMembers(_ reasoning: [ReplayedReasoning]) -> NoMembers { NoMembers() }
}

extension ChatCompletionsDialect where ChunkExtras == NoMembers {
    package func observe(_ extras: NoMembers, into state: inout StreamState) -> ChunkOutput { ChunkOutput() }
}

extension ChatCompletionsDialect where StreamState == Void {
    package func streamState(_ headers: ResponseHeaders) {}

    package func facts(of state: Void) -> AnswerAdditions { AnswerAdditions() }
}
