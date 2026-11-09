public import FoundationModels
import LanguageModels

/// Request settings beyond Foundation Models' generation options: members of a provider's own that the module doesn't
/// write, the key of the provider's prompt cache, and whether a provider that speaks Responses keeps each response.
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

    /// The key that groups requests whose prompts start the same, so the provider's prompt cache serves their shared
    /// start more often, or `nil` for none.
    ///
    /// It goes out as `prompt_cache_key` to ``OpenAICompatibleProvider/xAI`` and ``OpenAICompatibleProvider/mistral``,
    /// which read it, and to a provider the app describes itself, which may refuse it as a member it doesn't know. The
    /// other presets leave it out and log it, since their providers refuse it, ignore it or don't document it.
    ///
    /// ```swift
    /// let model = OpenAICompatibleLanguageModel(
    ///     OpenAICompatibleModel("grok-4.3", on: .xAI),
    ///     options: OpenAICompatibleOptions(cacheKey: .session),
    ///     auth: .apiKey { try await keyStore.xAIKey() }
    /// )
    /// ```
    public var cacheKey: CacheKey?

    /// Whether a provider that speaks Responses keeps each response, as its `store` setting says. The module sends
    /// `store` only in the Responses format.
    public var storage: Storage

    /// Creates request settings.
    ///
    /// - Parameters:
    ///   - additionalMembers: Members that every request's body carries as written.
    ///   - cacheKey: The key that groups requests whose prompts start the same.
    ///   - storage: Whether a provider that speaks Responses keeps each response.
    public init(additionalMembers: [String: GeneratedContent] = [:], cacheKey: CacheKey? = nil, storage: Storage = .automatic) {
        self.additionalMembers = additionalMembers
        self.cacheKey = cacheKey
        self.storage = storage
    }

    /// Hashes the keys of the additional members, the cache key and the storage, which equal options always share.
    ///
    /// - Parameter hasher: The hasher to feed them to.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(Set(additionalMembers.keys))
        hasher.combine(cacheKey)
        hasher.combine(storage)
    }
}

extension OpenAICompatibleOptions {
    /// The key that groups requests whose prompts start the same, so the provider's prompt cache serves their shared
    /// start more often. It goes out as `prompt_cache_key` to the providers ``OpenAICompatibleOptions/cacheKey`` names.
    public struct CacheKey: Sendable, Hashable {
        /// Each session's own key: the id of its first prompt, which stays the same for the whole session.
        public static let session = Self(kind: .session)

        /// A key of the app's own, such as one for every session that shares the same long instructions.
        ///
        /// - Parameter key: The key.
        /// - Returns: The cache key.
        public static func named(_ key: String) -> Self {
            Self(kind: .named(key))
        }

        /// Where the key's text comes from.
        private enum Kind: Sendable, Hashable {
            case session
            case named(String)
        }

        private let kind: Kind

        /// The key's text: the session's first prompt's id, or the app's own key; `nil` before the first prompt.
        func text(firstPromptID: String?) -> String? {
            switch kind {
            case .session: firstPromptID
            case .named(let key): key
            }
        }
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
