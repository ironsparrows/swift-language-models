public import FoundationModels
import LanguageModels

/// Request settings beyond Foundation Models' generation options: members of a provider's own that the module doesn't
/// write, and whether a provider that speaks Responses keeps each response.
///
/// Every setting left at its default stays out of the request, so the provider's own default applies, but for the
/// storage of a preset that asks its provider not to keep responses, as ``OpenAICompatibleProvider/xAI`` does.
public struct OpenAICompatibleOptions: Sendable, Hashable {
    /// Members that every request's body carries as written, such as a setting only the provider has, or one the module
    /// writes another way.
    ///
    /// A member of a key the module writes, such as `max_tokens`, replaces that member in its place, and goes out even
    /// when the module leaves that setting out for the provider. The others go after the module's, sorted by key. The
    /// model id, the transcript (`messages` or `input`), `stream` and `tools` stay the module's: a member with one of
    /// those keys is left out, and the request logs it.
    ///
    /// ```swift
    /// var options = OpenAICompatibleOptions()
    /// options.additionalMembers["keep_alive"] = GeneratedContent("10m")
    /// options.additionalMembers["chat_template_kwargs"] = try GeneratedContent(json: #"{"enable_thinking":false}"#)
    /// ```
    public var additionalMembers: [String: GeneratedContent]

    /// Whether a provider that speaks Responses keeps each response, as its `store` setting says. The module sends
    /// `store` only in the Responses format.
    public var storage: Storage

    /// Creates request settings.
    ///
    /// - Parameters:
    ///   - additionalMembers: Members that every request's body carries as written.
    ///   - storage: Whether a provider that speaks Responses keeps each response.
    public init(additionalMembers: [String: GeneratedContent] = [:], storage: Storage = .automatic) {
        self.additionalMembers = additionalMembers
        self.storage = storage
    }

    /// Hashes the keys of the additional members and the storage, which equal options always share.
    ///
    /// - Parameter hasher: The hasher to feed them to.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(Set(additionalMembers.keys))
        hasher.combine(storage)
    }
}

extension OpenAICompatibleOptions {
    /// Whether a provider that speaks Responses keeps a response.
    ///
    /// The package sends each request's whole transcript, so later turns work whether or not the provider keeps the
    /// response. After a request that asks the provider not to keep it, with `store` false, later turns send back only
    /// the `reasoning` items that carry their reasoning encrypted, which a preset asks for where its provider sends it,
    /// as ``OpenAICompatibleProvider/xAI`` does; otherwise each goes back as it came.
    public enum Storage: Sendable, Hashable {
        /// The provider's own default, with no `store` in the request, or for a preset that asks its provider not to
        /// keep responses, as ``OpenAICompatibleProvider/xAI`` does, ``notStored``.
        case automatic

        /// The provider keeps the response.
        case stored

        /// The provider doesn't keep the response.
        case notStored
    }
}

extension OpenAICompatibleOptions {
    /// The additional members as a request's overriding members, sorted by key, so they give the same bytes every time.
    var overridingMembers: JSONObject {
        JSONObject(additionalMembers.sorted { $0.key < $1.key }.map { JSONObject.Member(key: $0.key, value: JSONValue($0.value)) })
    }
}
