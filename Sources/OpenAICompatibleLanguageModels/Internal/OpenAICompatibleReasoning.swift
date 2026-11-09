import Foundation
import FoundationModels
import LanguageModels

// MARK: - Reasoning that goes back

extension OpenAICompatibleProvider.ReasoningReplay {
    /// The members an answer goes back with in Chat Completions.
    ///
    /// - Parameter answer: The answer's reasoning that goes back, and its tool calls.
    /// - Returns: The reasoning's text in the provider's member on the message, when there's any, or the answer's
    ///   thought signature on its first tool call, or on its message when it has no call.
    func members(for answer: ChatCompletions.ReplayedAnswer) -> ChatCompletions.ReplayMembers {
        switch self {
        case .notSent:
            return ChatCompletions.ReplayMembers()
        case .reasoningContent:
            return Self.text(of: answer, in: Member.reasoningContent)
        case .reasoning:
            return Self.text(of: answer, in: Member.reasoning)
        case .thoughtSignatures:
            return ThoughtSignatures.members(for: answer)
        }
    }

    /// The answer's reasoning text in a member of the message, or no member when it has none, such as an answer whose
    /// reasoning another provider wrote.
    private static func text(of answer: ChatCompletions.ReplayedAnswer, in member: String) -> ChatCompletions.ReplayMembers {
        let text = answer.reasoning.map(\.text).joined()
        return text.isEmpty ? ChatCompletions.ReplayMembers() : ChatCompletions.ReplayMembers(message: [member: .string(text)])
    }

    /// The members reasoning goes back in.
    private enum Member {
        static let reasoningContent = "reasoning_content"
        static let reasoning = "reasoning"
    }
}

// MARK: - Thought signatures

/// An answer's thought signature, which its provider checks on later turns: the first one a tool call of the answer
/// carried, or else the first one its text carried.
///
/// The answer's reasoning entry keeps it as its signature, so it goes back with the answer: on the answer's first tool
/// call, or on its message when it has no call, in `extra_content.google.thought_signature`.
struct ThoughtSignatures {
    /// The first signature a tool call carried.
    private var call: String?

    /// The first signature the answer's text carried.
    private var text: String?

    /// Keeps the signatures a chunk carries, unless earlier chunks carried one of the same kind.
    mutating func read(_ extras: OpenAICompatibleChunkExtras) {
        call = call ?? extras.callSignature
        text = text ?? extras.textSignature
    }

    /// The signature of the answer's reasoning entry, or `nil` when the answer carried none.
    var signature: Data? {
        (call ?? text).map { Data($0.utf8) }
    }

    /// The members an answer goes back with: its signature on its first tool call, or on its message when it has no
    /// call, and on a first tool call whose answer has none, such as a call another provider made, ``placeholder``.
    ///
    /// - Parameter answer: The answer's reasoning that goes back, and its tool calls.
    /// - Returns: The members.
    static func members(for answer: ChatCompletions.ReplayedAnswer) -> ChatCompletions.ReplayMembers {
        let signature = answer.reasoning.lazy.compactMap(\.entry.signature).first { !$0.isEmpty }
            .map { String(decoding: $0, as: UTF8.self) }
        if answer.toolCalls.isEmpty {
            return signature.map { ChatCompletions.ReplayMembers(message: extraContent($0)) } ?? ChatCompletions.ReplayMembers()
        }
        return ChatCompletions.ReplayMembers(toolCalls: [extraContent(signature ?? placeholder)])
    }

    /// The value that takes the place of a signature on a tool call the provider didn't make, which skips its check.
    static let placeholder = "skip_thought_signature_validator"

    /// The `extra_content` member that carries a signature.
    private static func extraContent(_ signature: String) -> JSONObject {
        ["extra_content": ["google": ["thought_signature": .string(signature)]]]
    }
}

// MARK: - Thinking

/// The `thinking` member of a provider whose `thinking` decides whether the model reasons: `{"type": "disabled"}` for
/// the reasoning level `off` and for a model that doesn't reason, and `{"type": "enabled"}` for any other level.
struct Thinking: Encodable {
    /// `enabled` or `disabled`.
    private let type: String

    /// The member for a request, or `nil` for a request that sets no reasoning level to a model that reasons, which
    /// leaves the provider's default.
    ///
    /// - Parameters:
    ///   - level: The request's reasoning level, if any.
    ///   - reasons: Whether the model reasons at all.
    init?(level: ContextOptions.ReasoningLevel?, reasons: Bool) {
        if !reasons || level == .off {
            type = Self.disabled
        } else if level != nil {
            type = "enabled"
        } else {
            return nil
        }
    }

    /// The member as JSON.
    var json: JSONValue {
        ["type": .string(type)]
    }

    /// Whether the model reasons for a request: as its `thinking` says, when it has one, otherwise unless its effort is
    /// `none`, and with neither, as it does by default.
    ///
    /// - Parameters:
    ///   - thinking: The request's `thinking`, if any.
    ///   - effort: The request's effort, if any.
    ///   - byDefault: Whether the model reasons for a request that asks for neither.
    /// - Returns: Whether the model reasons.
    static func reasons(thinking: JSONValue?, effort: String?, byDefault: Bool) -> Bool {
        if let type = thinking?["type"]?.stringValue { return type != disabled }
        guard let effort else { return byDefault }
        return effort != ContextOptions.ReasoningLevel.off.effortWord
    }

    /// The type that turns reasoning off.
    private static let disabled = "disabled"
}
