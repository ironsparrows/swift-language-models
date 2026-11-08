import Foundation
import FoundationModels
import LanguageModelsCore
package import UniformTypeIdentifiers

// MARK: - Output items

/// One of an answer's output items, in the order the answer's reasoning entry keeps them in its signature: a
/// `reasoning` item whole, or the place of a message, a function call or a server tool's call.
///
/// A signature is a JSON array. When every `reasoning` item came before the answer's messages and calls, and no server
/// tool's call was kept, as in most answers, it holds the `reasoning` items alone. Otherwise it also holds
/// `{"type": "message"}`, `{"type": "function_call"}` and a server tool call's type, such as
/// `{"type": "web_search_call"}`, in the places of the answer's messages and calls, so they go back between the
/// `reasoning` items as they came. A reader skips a type it doesn't know. Saved transcripts keep this shape, so it never
/// changes.
enum OutputItem: Equatable {
    case reasoning(ReasoningItem)
    case message
    case functionCall
    case serverToolCall(Responses.ServerToolCall)

    /// The output items an entry's signature holds, in their order; none for an entry without one.
    static func items(inSignatureOf entry: Transcript.Reasoning) -> [OutputItem] {
        guard let signature = entry.signature, case .array(let items)? = try? JSONValue(json: signature) else { return [] }
        return items.compactMap { item in
            guard let type = item["type"]?.stringValue.map(Responses.ItemType.init(rawValue:)) else { return nil }
            switch type {
            case .reasoning: return .reasoning(ReasoningItem(json: item))
            case .message: return .message
            case .functionCall: return .functionCall
            default: return Responses.ServerToolCall(type).map(OutputItem.serverToolCall)
            }
        }
    }

    /// The signature for an answer's output items: the `reasoning` items alone when they all come first and no server
    /// tool's call is among the items, every item otherwise, or `nil` when there are no `reasoning` items.
    static func signature(of items: [OutputItem]) -> Data? {
        let reasoning = items.filter { if case .reasoning = $0 { true } else { false } }
        guard !reasoning.isEmpty else { return nil }
        // Each server tool's call needs its place, since it goes back right after the reasoning before it.
        let hasServerToolCalls = items.contains { if case .serverToolCall = $0 { true } else { false } }
        let kept = items.prefix(reasoning.count) == reasoning[...] && !hasServerToolCalls ? reasoning : items
        return JSONValue.array(kept.map(\.json)).data
    }

    /// The item as the signature writes it.
    private var json: JSONValue {
        switch self {
        case .reasoning(let item): item.json
        case .message: ["type": .string(Responses.ItemType.message.rawValue)]
        case .functionCall: ["type": .string(Responses.ItemType.functionCall.rawValue)]
        case .serverToolCall(let call): ["type": .string(call.itemType.rawValue)]
        }
    }
}

// MARK: - Server tool calls

extension Responses {
    /// A kind of call that one of a provider's server tools adds to an answer as an output item of its own, such as a web
    /// search, which a request that sends the tool keeps, so the call goes back on later turns in its place.
    ///
    /// An answer's response entry keeps the calls, an image's without its image, under the model's
    /// ``Model/serverToolsKey``, and its reasoning entry's signature their places among its `reasoning` items. A call
    /// goes back right after the reasoning items before it, or neither goes back.
    package enum ServerToolCall: CaseIterable, Sendable {
        /// A `web_search_call`: the searches, page opens and finds of a web search.
        case webSearch

        /// An `image_generation_call`, whose image the answer sends as a data entry of its own.
        case imageGeneration

        /// A `file_search_call`: the searches of the files in a provider's vector stores.
        case fileSearch

        /// The kind whose items have this type, or `nil` for another type.
        init?(_ type: ItemType) {
            guard let call = Self.allCases.first(where: { $0.itemType == type }) else { return nil }
            self = call
        }

        /// The type of the kind's items.
        var itemType: ItemType {
            switch self {
            case .webSearch: .webSearchCall
            case .imageGeneration: .imageGenerationCall
            case .fileSearch: .fileSearchCall
            }
        }

        /// Whether the call goes back to a provider that doesn't keep the response. An image's call doesn't: it goes back
        /// without its image, which only a provider that keeps the response can look up by the call's id.
        var goesBackUnstored: Bool {
            switch self {
            case .webSearch, .fileSearch: true
            case .imageGeneration: false
            }
        }

        /// The kind of a generated image in a format, such as `png`, as an image's call names it.
        package static func imageType(ofFormat format: String) -> UTType {
            UTType(filenameExtension: format, conformingTo: .image) ?? .image
        }

        /// The item as the answer keeps it: whole, but an image's call without its image, whose `result` becomes `null`.
        /// The answer sends the image as a data entry of its own.
        func kept(_ item: JSONValue) -> JSONValue {
            switch self {
            case .webSearch, .fileSearch:
                return item
            case .imageGeneration:
                guard case .object(var members) = item else { return item }
                members["result"] = JSONValue.null
                return .object(members)
            }
        }
    }

    /// What a provider's server tools left on an entry, as its metadata keeps it under the model's
    /// ``Model/serverToolsKey``: their calls, in their order, and the files the answer cites.
    ///
    /// The entry that ends an answer keeps the answer's calls and cited files, and whether the provider kept the response
    /// that made them; the data entry of a generated image keeps the image's own call. A call is kept as the JSON text of
    /// its item, so it goes back as it came, apart from what ``ServerToolCall/kept(_:)`` leaves out. Saved transcripts
    /// keep this shape, so it never changes.
    package struct ServerToolOutput {
        /// The calls, in their order.
        package private(set) var calls: [JSONValue] = []

        /// The files the answer's text cites, in the order they came.
        package private(set) var fileCitations: [FileCitation] = []

        /// Whether the provider kept the response that made the calls, as its `store` said, or as the request asked when
        /// it didn't say, so it can look an image's call up by its id.
        private(set) var isStored = true

        init(calls: [JSONValue] = [], fileCitations: [FileCitation] = [], isStored: Bool = true) {
            self.calls = calls
            self.fileCitations = fileCitations
            self.isStored = isStored
        }

        /// What an entry's metadata keeps under a key; empty when the key is missing.
        ///
        /// - Parameters:
        ///   - values: The entry's metadata.
        ///   - key: The model's server tools key.
        package init(_ values: MetadataValues, key: String) {
            guard let output = values.structure(key) else { return }
            calls = output.strings(Field.calls).compactMap { try? JSONValue(json: Data($0.utf8)) }
            fileCitations = output.structures(Field.fileCitations).compactMap(FileCitation.init)
            isStored = output.bool(Field.unstored) != true
        }

        /// Whether nothing was left.
        var isEmpty: Bool {
            calls.isEmpty && fileCitations.isEmpty
        }

        /// The output as an entry's metadata keeps it, leaving out an empty list.
        var metadataValue: GeneratedContent {
            var properties: [(String, any ConvertibleToGeneratedContent)] = []
            if !calls.isEmpty { properties.append((Field.calls, calls.map(\.text))) }
            if !fileCitations.isEmpty { properties.append((Field.fileCitations, fileCitations.map(\.metadataValue))) }
            if !isStored { properties.append((Field.unstored, true)) }
            return GeneratedContent(properties: properties) { first, _ in first }
        }

        /// The keys of the structure. Saved transcripts keep them, so they never change.
        private enum Field {
            static let calls = "calls"
            static let fileCitations = "fileCitations"
            static let unstored = "unstored"
        }
    }

    /// A file that an answer's text cites, from a provider's file search.
    package struct FileCitation: Equatable {
        /// The provider's id for the file.
        package let fileID: String

        /// The file's name.
        package let filename: String?

        /// Where the citation goes in the answer's text, in characters, or `nil` when that isn't known.
        package let offset: Int?

        init(fileID: String, filename: String?, offset: Int?) {
            self.fileID = fileID
            self.filename = filename
            self.offset = offset
        }

        /// A citation read back from an element of the metadata, or `nil` for an element that isn't one.
        fileprivate init?(_ values: MetadataValues) {
            guard let fileID = values.string(Field.fileID) else { return nil }
            self.init(fileID: fileID, filename: values.string(Field.filename), offset: values.integer(Field.offset))
        }

        /// The citation as an element of the metadata.
        fileprivate var metadataValue: GeneratedContent {
            GeneratedContent(properties: [Field.fileID: fileID, Field.filename: filename, Field.offset: offset])
        }

        /// The keys of an element. Saved transcripts keep them, so they never change.
        private enum Field {
            static let fileID = "fileID"
            static let filename = "filename"
            static let offset = "offset"
        }
    }
}

// MARK: - Message phases

extension Responses {
    /// The `phase` of one of an answer's messages, such as `commentary` or `final_answer`, and the length of its text, in
    /// characters, as the response entry's metadata keeps them, so each message goes back on later turns with its own
    /// phase. A message whose text is held out of the answer's text, such as a guided answer's `commentary`, keeps the text
    /// itself instead.
    package struct MessagePhase: Equatable {
        package private(set) var phase: String?
        package private(set) var length = 0

        /// The message's text when it's held out of the answer's text, or `nil` when the answer's text holds it.
        package private(set) var heldText: String?

        init(phase: String? = nil, length: Int = 0) {
            self.phase = phase
            self.length = length
        }

        /// A message whose text is held out of the answer's text.
        init(phase: String?, heldText: String) {
            self.phase = phase
            self.heldText = heldText
        }

        /// A message's phase read back from an element of the metadata, or `nil` for an element that isn't one.
        package init?(_ values: MetadataValues) {
            guard let length = values.integer(Field.length) else { return nil }
            self.init(phase: values.string(Field.phase), length: length)
            heldText = values.string(Field.heldText)
        }

        /// The message as an element of the metadata.
        var metadataValue: GeneratedContent {
            guard let heldText else { return GeneratedContent(properties: [Field.phase: phase, Field.length: length]) }
            return GeneratedContent(properties: [Field.phase: phase, Field.length: length, Field.heldText: heldText])
        }

        /// The phase of the message that holds an answer's final text, which a guided answer decodes.
        static let finalAnswer = "final_answer"

        /// The keys of an element. Saved transcripts keep them, so they never change.
        private enum Field {
            static let phase = "phase"
            static let length = "length"
            static let heldText = "heldText"
        }

        /// An answer's text split into its messages, each with its phase, and the held-out messages in their places; when
        /// the lengths don't add up to the text, as when the text changed, the held-out messages, then the whole text as
        /// one message with the last phase of the others.
        ///
        /// - Parameters:
        ///   - text: The answer's text.
        ///   - phases: The answer's messages, in their order.
        /// - Returns: The messages' texts and phases, leaving out empty texts.
        static func split(_ text: String, into phases: [MessagePhase]) -> [(text: String, phase: String?)] {
            let shown = phases.filter { $0.heldText == nil }
            guard shown.map(\.length).reduce(0, +) == text.count else {
                let held = phases.compactMap { message in message.heldText.map { (text: $0, phase: message.phase) } }
                return (held + [(text, shown.last?.phase)]).filter { !$0.text.isEmpty }
            }
            var rest = Substring(text)
            return phases.compactMap { message in
                if let heldText = message.heldText { return heldText.isEmpty ? nil : (heldText, message.phase) }
                let part = rest.prefix(message.length)
                rest = rest.dropFirst(message.length)
                return part.isEmpty ? nil : (String(part), message.phase)
            }
        }
    }
}

// MARK: - Wire

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

extension Responses {
    /// The `type` of an input or output item.
    struct ItemType: ProviderVocabulary {
        static let message: Self = "message"
        static let functionCall: Self = "function_call"
        static let functionCallOutput: Self = "function_call_output"
        static let reasoning: Self = "reasoning"
        static let webSearchCall: Self = "web_search_call"
        static let imageGenerationCall: Self = "image_generation_call"
        static let fileSearchCall: Self = "file_search_call"

        let rawValue: String
    }
}
