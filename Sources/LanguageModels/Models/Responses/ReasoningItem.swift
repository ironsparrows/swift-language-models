import Foundation
import FoundationModels
import LanguageModelsCore

/// One of an answer's `reasoning` output items, as a later request's input sends it back: the item the stream's
/// `response.output_item.done` carried, with members such as `type`, `id`, `summary` and `encrypted_content`, and
/// every other member the provider sent.
struct ReasoningItem: Encodable, Equatable {
    /// The item, as the provider sent it.
    let json: JSONValue

    /// Whether the item carries its reasoning encrypted, which a request that the provider doesn't store needs, since
    /// the provider can't look the item up by its id.
    var hasEncryptedContent: Bool {
        if case .string(let content)? = json["encrypted_content"] { !content.isEmpty } else { false }
    }

    func encode(to encoder: any Encoder) throws {
        try json.encode(to: encoder)
    }
}

/// One of an answer's output items, in the order the answer's reasoning entry keeps them in its signature: a
/// `reasoning` item whole, or the place of a message or a function call.
///
/// A signature is a JSON array. When every `reasoning` item came before the answer's messages and calls, as in most
/// answers and in every transcript written before the order was kept, it holds the `reasoning` items alone. Otherwise
/// it also holds `{"type": "message"}` and `{"type": "function_call"}` in the places of the answer's messages and
/// calls, so they go back between the `reasoning` items as they came. Saved transcripts keep this shape, so it never
/// changes.
enum OutputItem: Equatable {
    case reasoning(ReasoningItem)
    case message
    case functionCall

    /// The output items an entry's signature holds, in their order; none for an entry without one.
    static func items(inSignatureOf entry: Transcript.Reasoning) -> [OutputItem] {
        guard let signature = entry.signature, case .array(let items)? = try? JSONValue(json: signature) else { return [] }
        return items.compactMap { item in
            switch item["type"]?.stringValue.map(ResponsesRequest.ItemType.init(rawValue:)) {
            case .reasoning?: .reasoning(ReasoningItem(json: item))
            case .message?: .message
            case .functionCall?: .functionCall
            default: nil
            }
        }
    }

    /// The signature for an answer's output items: the `reasoning` items alone when they all come first, or `nil`
    /// when there are none.
    static func signature(of items: [OutputItem]) -> Data? {
        let reasoning = items.filter { if case .reasoning = $0 { true } else { false } }
        guard !reasoning.isEmpty else { return nil }
        let kept = items.prefix(reasoning.count) == reasoning[...] ? reasoning : items
        return JSONValue.array(kept.map(\.json)).data
    }

    /// The item as the signature writes it.
    private var json: JSONValue {
        switch self {
        case .reasoning(let item): item.json
        case .message: ["type": .string(ResponsesRequest.ItemType.message.rawValue)]
        case .functionCall: ["type": .string(ResponsesRequest.ItemType.functionCall.rawValue)]
        }
    }
}
