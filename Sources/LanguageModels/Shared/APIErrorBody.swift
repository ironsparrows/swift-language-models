import LanguageModelsCore

/// The `error` object that OpenAI's formats send in a failed response's body, `{"error": {"message", "type",
/// "code", "param"}}`, which other hosts of the formats send too, often with members of their own.
///
/// The message is required. The other members are read when they have the expected kind and are `nil`
/// otherwise, since hosts vary them.
package struct APIErrorBody: Decodable, Sendable {
    /// What went wrong.
    package var message: String

    /// The kind of error, such as `invalid_request_error`.
    package var type: String?

    /// The error's code, a number or a word depending on the host.
    package var code: JSONValue?

    /// The request parameter the error concerns.
    package var param: String?

    package init(message: String, type: String? = nil, code: JSONValue? = nil, param: String? = nil) {
        self.message = message
        self.type = type
        self.code = code
        self.param = param
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        code = try container.decodeIfPresent(JSONValue.self, forKey: .code)
        param = try? container.decodeIfPresent(String.self, forKey: .param)
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case type
        case code
        case param
    }
}
