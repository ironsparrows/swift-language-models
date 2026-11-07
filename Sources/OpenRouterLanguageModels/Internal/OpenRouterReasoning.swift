import Foundation
import FoundationModels
import LanguageModels

// MARK: - Details

/// OpenRouter's `reasoning_details`: the reasoning a model produced, in the form OpenRouter needs back on later turns.
///
/// The details are stored in a reasoning entry's signature, and the entry's metadata names OpenRouter as its origin, so
/// only reasoning from OpenRouter is sent back. The metadata also names the model that wrote it, so reasoning a
/// fallback wrote isn't sent to another model.
struct ReasoningDetails: Sendable, Equatable {
    private var details: [JSONValue] = []

    /// Adds the details of one stream delta.
    ///
    /// Models stream one reasoning block as many deltas, with the same `index`, so a delta continues the previous
    /// detail of its type unless its `index` or `id` names another block: a text detail continues until a signature
    /// closes it, a summary continues, and every other detail, such as encrypted reasoning, stands alone.
    mutating func append(_ delta: JSONValue) {
        guard case .object(let detail) = delta else { return }
        let kind = delta.reasoningKind
        guard case .object(var last)? = details.last, details.last?.reasoningKind == kind, Self.isSameBlock(last, detail)
        else {
            details.append(delta)
            return
        }
        switch kind {
        case .text? where last["signature"]?.stringValue == nil:
            last["text"] = .string((last["text"]?.stringValue ?? "") + (detail["text"]?.stringValue ?? ""))
            Self.fill(&last, from: detail, keys: ["signature", "format", "id"])
        case .summary?:
            last["summary"] = .string((last["summary"]?.stringValue ?? "") + (detail["summary"]?.stringValue ?? ""))
            Self.fill(&last, from: detail, keys: ["format", "id"])
        default:
            details.append(delta)
            return
        }
        details[details.count - 1] = .object(last)
    }

    /// Whether a delta continues the last detail's block: neither its `index` nor its `id` names another one.
    private static func isSameBlock(_ last: JSONObject, _ detail: JSONObject) -> Bool {
        if let index = detail["index"], let lastIndex = last["index"], index != lastIndex { return false }
        if let id = detail["id"]?.stringValue, let lastID = last["id"]?.stringValue, id != lastID { return false }
        return true
    }

    /// Sets each of the keys that the last detail lacks and the delta has.
    private static func fill(_ last: inout JSONObject, from detail: JSONObject, keys: [String]) {
        for key in keys where last[key]?.stringValue == nil && detail[key]?.stringValue != nil {
            last[key] = detail[key]
        }
    }

    /// The details as the signature of a reasoning entry.
    var signature: Data {
        JSONValue.array(details).data
    }

    /// The text a person can read in one delta's details: reasoning text and summaries, not encrypted blobs.
    static func readableText(in delta: [JSONValue]) -> String {
        delta.compactMap { detail in
            switch detail.reasoningKind {
            case .text?: detail["text"]?.stringValue
            case .summary?: detail["summary"]?.stringValue
            default: nil
            }
        }.joined()
    }

    /// Whether a reasoning entry's reasoning came as text alone: without details, or with an empty list of them.
    private static func isTextAlone(_ reasoning: Transcript.Reasoning) -> Bool {
        guard let signature = reasoning.signature else { return true }
        return (try? JSONValue(json: signature)) == .array([])
    }

    /// The details to send back for a reasoning entry, or `nil` when OpenRouter didn't write the entry.
    ///
    /// Anthropic and Gemini reject reasoning text without its signature, so unsigned text details in their formats are
    /// dropped. A detail without a format counts as Anthropic's, as OpenRouter treats it.
    private static func replayed(from reasoning: Transcript.Reasoning) -> [JSONValue]? {
        guard reasoning.origin == API.reasoningOrigin, let signature = reasoning.signature,
            case .array(let details)? = try? JSONValue(json: signature)
        else { return nil }
        return details.filter { detail in
            guard detail.reasoningKind == .text else { return true }
            let format = detail["format"]?.stringValue.map(Format.init(rawValue:)) ?? .anthropic
            return !format.requiresSignedText || detail["signature"]?.stringValue != nil
        }
    }
}

extension ReasoningDetails {
    /// What a detail holds, from its `type`. Other kinds, such as encrypted reasoning, stay opaque.
    fileprivate struct Kind: ProviderVocabulary {
        /// Reasoning text, which may carry a signature.
        static let text: Self = "reasoning.text"

        /// A summary of the reasoning.
        static let summary: Self = "reasoning.summary"

        let rawValue: String
    }

    /// Whose reasoning a detail is, from its `format`.
    private struct Format: ProviderVocabulary {
        /// Anthropic's.
        static let anthropic: Self = "anthropic-claude-v1"

        /// Google Gemini's.
        static let gemini: Self = "google-gemini-v1"

        let rawValue: String

        /// Whether the host rejects reasoning text sent back without its signature.
        var requiresSignedText: Bool { self == .anthropic || self == .gemini }
    }
}

extension JSONValue {
    /// The kind of a reasoning detail.
    fileprivate var reasoningKind: ReasoningDetails.Kind? {
        self["type"]?.stringValue.map(ReasoningDetails.Kind.init(rawValue:))
    }
}

// MARK: - What goes back

extension ReasoningDetails {
    /// The assistant message's `reasoning` and `reasoning_details` for the reasoning it sends back.
    ///
    /// The details go back as OpenRouter sent them, with the text of the reasoning they came with. When no details are
    /// left to send, that text stays out too, since it would reach the host unsigned. Reasoning that came as text alone
    /// goes back as text, as OpenRouter takes it from models that return only raw reasoning. A block the model wrote in
    /// its answer's text already goes back there, so its text isn't sent again. Some models send an empty list of
    /// details when they didn't reason, and expect it back.
    static func replayMembers(for reasoning: [(entry: Transcript.Reasoning, text: String)]) -> JSONObject {
        var signedText = ""
        var plainText = ""
        var details: [JSONValue]?
        for replayed in reasoning {
            if let sent = Self.replayed(from: replayed.entry) {
                details = (details ?? []) + sent
                if !sent.isEmpty { signedText += replayed.text }
            }
            if isTextAlone(replayed.entry) { plainText += replayed.text }
        }
        let text = ((details ?? []).isEmpty ? "" : signedText) + plainText
        return ["reasoning": text.isEmpty ? nil : .string(text), "reasoning_details": details.map(JSONValue.array)]
    }
}

// MARK: - Which model wrote it

extension OpenRouterLanguageModel {
    /// Whether reasoning goes back in a request, since each request tries the model first and reasoning suits only
    /// the model that wrote it.
    ///
    /// - Parameter writer: The model that wrote the reasoning, as its answer named it, or `nil` when that isn't known.
    /// - Returns: `false` when a fallback, rather than the model, wrote the reasoning; otherwise `true`, also for a
    ///   writer that none of them names, such as the model a router picked.
    func replaysReasoning(writtenBy writer: String?) -> Bool {
        guard let writer else { return true }
        let model = details.specificity(naming: writer) ?? 0
        return fallbacks.allSatisfy { ($0.specificity(naming: writer) ?? 0) <= model }
    }
}

extension OpenRouterModel {
    /// How specifically an answer's `model` names this model: the length of the id it matches, or `nil` when it
    /// names another model.
    ///
    /// An answer names a model by its id, or by the id an alias points to, without a variant suffix such as `:free`,
    /// and often with a dated version after it, such as `openai/gpt-4.1-nano-2025-04-14`. A longer match is the more
    /// specific one, so `vendor/model-mini-2026-10-01` names `vendor/model-mini` rather than `vendor/model`.
    fileprivate func specificity(naming answerModel: String) -> Int? {
        let named = answerModel.prefix { $0 != ":" }
        return [id, aliasTarget].compactMap { id in
            guard let slug = id?.rawValue.prefix(while: { $0 != ":" }), named == slug || named.hasPrefix(slug + "-") else {
                return nil
            }
            return slug.count
        }.max()
    }
}
