package import FoundationModels
import LanguageModelsCore

/// How a provider speaks OpenAI's Responses format, which the format's executor sends requests in.
///
/// The executor owns the whole exchange: it builds the body from Foundation Models' request, authenticates and sends
/// it, retries a brief failure as the provider's connection allows and once with the portable schema when a host
/// rejects a constraint, streams the answer into Foundation Models' channel, sends each answer's `reasoning` items back
/// on later turns in the order they came, maps a failed connection and logs. A dialect adds only what its provider does
/// differently, through hooks that each get what that hook needs and nothing else:
///
/// - ``body(_:)``: the provider's own members, as ``BodyExtras``, and the few choices it makes about the format's.
/// - ``lists(_:)`` with ``listedMembers``: members sent only when the models take them.
/// - ``check(_:in:)``: the attachments its models take.
/// - ``instructionsRole``: the role the instructions go in.
/// - ``replays(_:)``: which of its reasoning entries go back.
/// - ``reasoningOrigin`` and ``phasesMetadataKey``: how its answers' reasoning and messages are tagged, so they go
///   back on later turns.
/// - ``streamState(_:)`` and ``facts(of:)``: what the response's headers carry beyond the format's, tracked across the
///   answer in ``StreamState``.
/// - ``error(for:)``: what each failure becomes.
///
/// Every hook has a default that adds nothing, except ``error(for:)``, which turns failures into the provider's own
/// public error, and ``body(_:)`` once the dialect sets ``BodyExtras``. Implement the hooks that have a default in the
/// extension that declares the conformance: only there does a misspelled one draw a warning instead of silently keeping
/// the default.
///
/// A request executor runs a dialect with
/// ``LanguageModels/DetailedLanguageModelRequestExecutor/respond(to:model:streamingInto:as:)``, the format's only way
/// in.
package protocol ResponsesDialect: ProviderDialect {
    /// The provider's own members of a request's body. Their keys are ``Responses/Member`` values, never the format's own.
    associatedtype BodyExtras: Encodable = NoMembers

    /// What the provider tracks across one streamed answer.
    associatedtype StreamState: Sendable = Void

    /// The origin the reasoning entries of the provider's answers carry, so that only its own reasoning goes back.
    /// Saved transcripts keep it, so it never changes. The default is the provider's name in lowercase, followed by
    /// `-responses`.
    static var reasoningOrigin: ReasoningOrigin { get }

    /// The metadata key under which an answer's response entry keeps the `phase` of each of its messages, such as
    /// `commentary` or `final_answer`, with the length of its text, so each message goes back with its phase on later
    /// turns. Saved transcripts keep it, so it never changes. The default is the provider's name with its first letter
    /// in lowercase, followed by `.phases`.
    static var phasesMetadataKey: String { get }

    /// The members, the format's or the provider's, that go out only when ``lists(_:)`` says the models take them. A
    /// member left out is logged. The default is none.
    static var listedMembers: Set<Responses.Member> { get }

    /// The role of the message the instructions go in. The default is `developer`.
    var instructionsRole: InstructionsRole { get }

    /// Whether the models take a member of ``listedMembers``. The default takes every one.
    func lists(_ member: Responses.Member) -> Bool

    /// Checks that the models take an attachment, before the format reads it. The default takes every one.
    ///
    /// - Throws: `LanguageModelError` for an attachment a model doesn't take.
    func check(_ attachment: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError)

    /// The provider's members of a request's body, and its choices about the format's own.
    ///
    /// - Throws: `LanguageModelError` when the provider can't send the request.
    func body(_ context: BodyContext) throws(LanguageModelError) -> ResponsesBodyPlan<BodyExtras>

    /// Whether one of the provider's own reasoning entries goes back in a later request, as the answer's `reasoning`
    /// items. Reasoning another provider wrote never does. The default sends back every one.
    func replays(_ reasoning: Transcript.Reasoning) -> Bool

    /// What the provider tracks across one answer, before its first event.
    ///
    /// - Parameter headers: The headers of the response whose stream carries the answer.
    /// - Returns: The state before the answer's first event.
    func streamState(_ headers: ResponseHeaders) -> StreamState

    /// The facts the provider adds to the answer once it's over, or to an error before then. Its reasoning signature
    /// is ignored, since the format's holds the answer's `reasoning` items.
    func facts(of state: StreamState) -> AnswerFacts

    /// What a failure becomes: Foundation Models' error when it has a case for it, otherwise the provider's own.
    func error(for failure: ResponsesFailure<Self>) -> MappedError<ProviderError>
}

extension ResponsesDialect {
    package static var reasoningOrigin: ReasoningOrigin { ReasoningOrigin(rawValue: "\(name.lowercased())-responses") }

    package static var phasesMetadataKey: String { "\(name.prefix(1).lowercased())\(name.dropFirst()).phases" }

    package static var listedMembers: Set<Responses.Member> { [] }

    package var instructionsRole: InstructionsRole { .developer }

    package func lists(_ member: Responses.Member) -> Bool { true }

    package func check(_ attachment: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {}

    package func replays(_ reasoning: Transcript.Reasoning) -> Bool { true }
}

extension ResponsesDialect where BodyExtras == NoMembers {
    package func body(_ context: BodyContext) throws(LanguageModelError) -> ResponsesBodyPlan<NoMembers> {
        ResponsesBodyPlan(extras: NoMembers())
    }
}

extension ResponsesDialect where StreamState == Void {
    package func streamState(_ headers: ResponseHeaders) {}

    package func facts(of state: Void) -> AnswerFacts { AnswerFacts() }
}
