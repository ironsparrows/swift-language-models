import Foundation
import LanguageModelsCore

extension ChatCompletionRequest {
    /// One message of the format's `messages`.
    enum Message: Encodable, Equatable {
        /// Instructions, as a `system` message.
        case system(Content)

        /// A prompt, as a `user` message.
        case user(Content)

        /// One answer's text, the reasoning it sends back and its tool calls, as an `assistant` message.
        case assistant(Assistant)

        /// A tool's output, as a `tool` message answering the call of the id.
        case tool(callID: String, content: Content)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            switch self {
            case .system(let content):
                try container.encode(Role.system, forKey: "role")
                try container.encode(content, forKey: "content")
            case .user(let content):
                try container.encode(Role.user, forKey: "role")
                try container.encode(content, forKey: "content")
            case .assistant(let assistant):
                try container.encode(Role.assistant, forKey: "role")
                if !assistant.text.isEmpty { try container.encode(assistant.text, forKey: "content") }
                for member in assistant.replay.members {
                    try container.encode(member.value, forKey: JSONKey(stringValue: member.key))
                }
                if !assistant.toolCalls.isEmpty { try container.encode(assistant.toolCalls, forKey: "tool_calls") }
            case .tool(let callID, let content):
                try container.encode(Role.tool, forKey: "role")
                try container.encode(callID, forKey: "tool_call_id")
                try container.encode(content, forKey: "content")
            }
        }
    }

    /// An `assistant` message's parts: the answer's text, with a reasoning block the model wrote in its text back at
    /// the start, the members of the reasoning it sends back, and its tool calls.
    struct Assistant: Equatable {
        var text = ""
        var replay = JSONObject()
        var toolCalls: [ToolCall] = []
    }

    /// A message's content: one text as a plain string, otherwise its parts.
    enum Content: Encodable, Equatable {
        case text(String)
        case parts([Part])

        /// The content of parts: a plain string for one text part without added members, otherwise the parts.
        init(_ parts: [Part]) {
            if parts.count == 1, case .text(let text, let marks) = parts[0], marks.members.isEmpty {
                self = .text(text)
            } else {
                self = .parts(parts)
            }
        }

        /// The content with members added to its last part, such as a cache mark, which makes a plain string a part.
        func marked(with marks: JSONObject) -> Content {
            var parts: [Part] =
                switch self {
                case .text(let text): [.text(text)]
                case .parts(let parts): parts
                }
            guard let last = parts.last else { return self }
            parts[parts.count - 1] = last.marked(with: marks)
            return .parts(parts)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text): try container.encode(text)
            case .parts(let parts): try container.encode(parts)
            }
        }
    }

    /// A content part of a message.
    enum Part: Encodable, Equatable {
        /// Text, with members a provider added, such as a cache mark.
        case text(String, marks: JSONObject = JSONObject())

        /// An image, at a web address or in a data URL.
        case image(url: String)

        /// A file, such as a PDF, in a data URL.
        case file(name: String, data: String)

        /// Audio as Base64, with its format's name.
        case audio(data: String, format: String)

        /// A movie in a data URL.
        case video(url: String)

        /// The part's `type`.
        var type: PartType {
            switch self {
            case .text: .text
            case .image: .image
            case .file: .file
            case .audio: .audio
            case .video: .video
            }
        }

        /// The part with members added, which only a text part takes.
        func marked(with marks: JSONObject) -> Part {
            guard case .text(let text, var existing) = self else { return self }
            for mark in marks.members { existing[mark.key] = mark.value }
            return .text(text, marks: existing)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode(type, forKey: "type")
            switch self {
            case .text(let text, let marks):
                try container.encode(text, forKey: "text")
                for mark in marks.members { try container.encode(mark.value, forKey: JSONKey(stringValue: mark.key)) }
            case .image(let url):
                try container.encode(["url": url], forKey: "image_url")
            case .file(let name, let data):
                var file = container.nestedContainer(keyedBy: JSONKey.self, forKey: "file")
                try file.encode(name, forKey: "filename")
                try file.encode(data, forKey: "file_data")
            case .audio(let data, let format):
                var audio = container.nestedContainer(keyedBy: JSONKey.self, forKey: "input_audio")
                try audio.encode(data, forKey: "data")
                try audio.encode(format, forKey: "format")
            case .video(let url):
                try container.encode(["url": url], forKey: "video_url")
            }
        }
    }

    /// One tool call of an `assistant` message, with its arguments as JSON text.
    struct ToolCall: Encodable, Equatable {
        let id: String
        let name: String
        let arguments: String

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode(id, forKey: "id")
            try container.encode("function", forKey: "type")
            var function = container.nestedContainer(keyedBy: JSONKey.self, forKey: "function")
            try function.encode(name, forKey: "name")
            try function.encode(arguments, forKey: "arguments")
        }
    }

    /// One of the session's tools, as a function.
    struct FunctionTool: Encodable {
        let name: String
        let description: String

        /// The JSON Schema of the arguments, which no fixed type can hold.
        let parameters: JSONValue

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode("function", forKey: "type")
            var function = container.nestedContainer(keyedBy: JSONKey.self, forKey: "function")
            try function.encode(name, forKey: "name")
            try function.encode(description, forKey: "description")
            try function.encode(parameters, forKey: "parameters")
        }
    }

    /// Structured outputs with a strict schema.
    struct ResponseFormat: Encodable {
        let name: String

        /// The JSON Schema of the answer, which no fixed type can hold.
        let schema: JSONValue

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: JSONKey.self)
            try container.encode("json_schema", forKey: "type")
            var format = container.nestedContainer(keyedBy: JSONKey.self, forKey: "json_schema")
            try format.encode(name, forKey: "name")
            try format.encode(true, forKey: "strict")
            try format.encode(schema, forKey: "schema")
        }
    }

    /// Who wrote a message: the instructions, the person, the model or a tool.
    struct Role: ProviderVocabulary {
        static let system: Self = "system"
        static let user: Self = "user"
        static let assistant: Self = "assistant"
        static let tool: Self = "tool"

        let rawValue: String
    }

    /// The `type` of a message's content part.
    struct PartType: ProviderVocabulary {
        static let text: Self = "text"
        static let image: Self = "image_url"
        static let file: Self = "file"
        static let audio: Self = "input_audio"
        static let video: Self = "video_url"

        let rawValue: String
    }
}
