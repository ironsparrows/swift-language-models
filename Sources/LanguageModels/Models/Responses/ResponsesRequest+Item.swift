import Foundation
import LanguageModelsCore

extension ResponsesRequest {
    /// One item of a request's `input`.
    enum Item: Encodable, Equatable {
        /// A message: the instructions, a prompt, or an answer's text, with the `phase` the answer's message had.
        case message(role: MessageRole, content: Content, phase: String?)

        /// One of an answer's function calls, matched to its output by `call_id`.
        case functionCall(callID: String, name: String, arguments: String)

        /// A tool's output for a function call.
        case functionCallOutput(callID: String, output: Content)

        /// One of an answer's `reasoning` items, as the provider sent it.
        case reasoning(ReasoningItem)

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .message(let role, let content, let phase):
                var container = encoder.container(keyedBy: JSONKey.self)
                try container.encode(role, forKey: "role")
                try container.encode(content, forKey: "content")
                try container.encodeIfPresent(phase, forKey: "phase")
            case .functionCall(let callID, let name, let arguments):
                var container = encoder.container(keyedBy: JSONKey.self)
                try container.encode(ItemType.functionCall, forKey: "type")
                try container.encode(callID, forKey: "call_id")
                try container.encode(name, forKey: "name")
                try container.encode(arguments, forKey: "arguments")
            case .functionCallOutput(let callID, let output):
                var container = encoder.container(keyedBy: JSONKey.self)
                try container.encode(ItemType.functionCallOutput, forKey: "type")
                try container.encode(callID, forKey: "call_id")
                try container.encode(output, forKey: "output")
            case .reasoning(let item):
                try item.encode(to: encoder)
            }
        }
    }

    /// A message's content or a tool's output: text alone, or a list of input parts.
    enum Content: Encodable, Equatable {
        case text(String)
        case parts([Part])

        /// One text part as its text, and anything else as parts.
        init(_ parts: [Part]) {
            if parts.count == 1, case .text(let text) = parts[0] {
                self = .text(text)
            } else {
                self = .parts(parts)
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text): try container.encode(text)
            case .parts(let parts): try container.encode(parts)
            }
        }
    }

    /// One part of a message's content.
    enum Part: Encodable, Equatable {
        /// An `input_text` part.
        case text(String)

        /// An `input_image` part, at a web address or as a data URL, which the model sees at the detail it picks.
        case image(url: String)

        /// An `input_file` part, holding the file as a data URL.
        case file(name: String, data: String)

        var type: PartType {
            switch self {
            case .text: .text
            case .image: .image
            case .file: .file
            }
        }

        /// Whether the part is a PDF file.
        var isPDF: Bool {
            if case .file(_, let data) = self { data.hasPrefix("data:\(MediaType.pdf);") } else { false }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode(type, forKey: "type")
            switch self {
            case .text(let text):
                try container.encode(text, forKey: "text")
            case .image(let url):
                try container.encode(url, forKey: "image_url")
                try container.encode("auto", forKey: "detail")
            case .file(let name, let data):
                try container.encode(name, forKey: "filename")
                try container.encode(data, forKey: "file_data")
            }
        }
    }

    /// One of the session's tools, as a function with `strict` off, so the host doesn't rewrite its schema.
    struct FunctionTool: Encodable {
        let name: String
        let description: String

        /// The JSON Schema of the arguments, which no fixed type can hold.
        let parameters: JSONValue

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode("function", forKey: "type")
            try container.encode(name, forKey: "name")
            try container.encode(description, forKey: "description")
            try container.encode(parameters, forKey: "parameters")
            // Left out, `strict` defaults to on, and OpenAI then holds the arguments to a strict form of the schema
            // that it makes up.
            try container.encode(false, forKey: "strict")
        }
    }

    /// Structured outputs with a strict schema, as `text.format`.
    struct TextFormat: Encodable {
        let name: String

        /// The JSON Schema of the answer, which no fixed type can hold.
        let schema: JSONValue

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode("json_schema", forKey: "type")
            try container.encode(name, forKey: "name")
            try container.encode(schema, forKey: "schema")
            try container.encode(true, forKey: "strict")
        }
    }

    /// The role of a message: the person's, the model's, or the instructions' role that the dialect picks.
    struct MessageRole: ProviderVocabulary {
        static let user: Self = "user"
        static let assistant: Self = "assistant"

        let rawValue: String
    }

    /// The `type` of a content part.
    struct PartType: ProviderVocabulary {
        static let text: Self = "input_text"
        static let image: Self = "input_image"
        static let file: Self = "input_file"

        let rawValue: String
    }
}

extension ResponsesRequest {
    /// The `type` of an input or output item.
    struct ItemType: ProviderVocabulary {
        static let message: Self = "message"
        static let functionCall: Self = "function_call"
        static let functionCallOutput: Self = "function_call_output"
        static let reasoning: Self = "reasoning"

        let rawValue: String
    }
}
