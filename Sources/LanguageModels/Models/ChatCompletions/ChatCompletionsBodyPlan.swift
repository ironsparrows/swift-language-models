package import LanguageModelsCore

/// What a dialect's ``ChatCompletionsDialect/body(_:)`` adds to a request's body, and the choices it makes about the
/// format's own members.
///
/// The format writes its members in a fixed order: `model`, `messages`, `stream`, the session's `tools` and
/// `tool_choice`, `response_format`, `temperature`, `top_p`, `seed`, the token limit and `metadata`, each only when the
/// request sets it. The plan adds the provider's members and makes the few choices a provider has about the format's:
/// it can't change the messages or the settings the app asked for.
package struct ChatCompletionsBodyPlan<Extras: Encodable> {
    /// The provider's own members.
    package var extras: Extras

    /// Whether the session's tools, and with them `tool_choice`, go out.
    package var sessionTools = SessionTools.sent

    /// Tools that run on the provider's servers, sent after the session's in `tools`.
    package var serverTools: [any Encodable & Sendable] = []

    /// The member the token limit goes in.
    package var tokenLimit = TokenLimit.maxCompletionTokens

    /// The form the response schema goes in.
    package var schema = SchemaForm.full

    /// Members added to the last content part of the last instructions, such as a cache mark, so the tools and
    /// instructions before it are cached on the host; `nil` for none.
    package var instructionsMark: (any Encodable & Sendable)?

    /// A reasoning level the provider sends as another effort, or leaves out, which the request logs.
    package var movedEffort: MovedEffort?

    package init(extras: Extras) {
        self.extras = extras
    }

    /// Whether the session's tools go out.
    package enum SessionTools: Sendable {
        /// The session's tools go out as functions, with `tool_choice` when the app chose how they're called.
        case sent

        /// Neither the session's tools nor `tool_choice` go out, as for models that don't take tools.
        case leftOut
    }

    /// The member the request's token limit goes in.
    package enum TokenLimit: Sendable {
        /// `max_completion_tokens`, the format's own.
        case maxCompletionTokens

        /// `max_tokens`, the older member, for models that don't take `max_completion_tokens`.
        case maxTokens
    }

    /// The form of the response schema.
    package enum SchemaForm: Sendable {
        /// The full schema, and the portable one only if the host rejects one of its constraints.
        case full

        /// The portable schema from the start, which carries its constraints in descriptions, as for a host known to
        /// reject them.
        case portable
    }
}
