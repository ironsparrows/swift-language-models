public import LanguageModels

/// Request settings that only OpenAI has, beyond Foundation Models' generation options.
///
/// Every setting left at its default stays out of the request, so OpenAI's own default applies.
public struct OpenAIOptions: Sendable, Hashable {
    /// The processing tier, such as `flex` or `priority`, which trades speed against price, or `nil` for the project's
    /// default.
    public var serviceTier: OpenAIServiceTier?

    /// How long and detailed the answers are, such as `low` for concise ones, or `nil` for the model's default. It goes
    /// out as set: GPT-5 and later models take every value, while older ones, such as o3 and GPT-4.1, take only
    /// `medium` and fail the request with an error that names `text.verbosity`.
    public var verbosity: Verbosity?

    /// The summary of its reasoning a model writes, which the answer's reasoning entry shows, or `nil` for none. The
    /// reasoning of a model that writes no summary still goes back on later turns, encrypted.
    public var reasoningSummary: ReasoningSummary?

    /// Whether the model may ask for several of the session's tools in one answer.
    ///
    /// Calls that arrive in one answer run as one round either way.
    public var parallelToolCalls: ParallelToolCalls

    /// The key that groups requests whose prompts start the same, so OpenAI's cache serves their shared start more
    /// often, or `nil` for none.
    public var cacheKey: CacheKey?

    /// A stable id for the app's end user, such as a hash of their account, so OpenAI can tell users apart for abuse
    /// checks, or `nil` for none. It goes out as `safety_identifier`.
    public var endUserID: String?

    /// Whether OpenAI keeps each response, as its `store` setting says.
    public var storage: Storage

    /// Creates request settings.
    ///
    /// - Parameters:
    ///   - serviceTier: The processing tier.
    ///   - verbosity: How long and detailed the answers are.
    ///   - reasoningSummary: The summary of its reasoning a model writes.
    ///   - parallelToolCalls: Whether the model may ask for several of the session's tools in one answer.
    ///   - cacheKey: The key that groups requests whose prompts start the same.
    ///   - endUserID: A stable id for the app's end user.
    ///   - storage: Whether OpenAI keeps each response.
    public init(
        serviceTier: OpenAIServiceTier? = nil,
        verbosity: Verbosity? = nil,
        reasoningSummary: ReasoningSummary? = nil,
        parallelToolCalls: ParallelToolCalls = .automatic,
        cacheKey: CacheKey? = nil,
        endUserID: String? = nil,
        storage: Storage = .automatic
    ) {
        self.serviceTier = serviceTier
        self.verbosity = verbosity
        self.reasoningSummary = reasoningSummary
        self.parallelToolCalls = parallelToolCalls
        self.cacheKey = cacheKey
        self.endUserID = endUserID
        self.storage = storage
    }
}

extension OpenAIOptions {
    /// Whether a model may ask for several tools in one answer.
    public enum ParallelToolCalls: Sendable, Hashable {
        /// OpenAI's own default, with no `parallel_tool_calls` in the request.
        case automatic

        /// The model may ask for several tools in one answer.
        case allowed

        /// The model asks for at most one tool per answer.
        case disallowed
    }

    /// Whether OpenAI keeps a response.
    ///
    /// The package sends each request's whole transcript, and every reasoning item goes back encrypted, so later turns
    /// work the same whether or not OpenAI keeps the response.
    public enum Storage: Sendable, Hashable {
        /// OpenAI's own default, which keeps responses, with no `store` in the request.
        case automatic

        /// OpenAI keeps the response, such as for its dashboard's logs, evals or distillation.
        case stored

        /// OpenAI doesn't keep the response.
        case notStored
    }
}

extension OpenAIOptions {
    /// The key that groups requests whose prompts start the same, so OpenAI's prompt cache serves their shared start
    /// more often. It goes out as `prompt_cache_key`.
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
        enum Kind: Sendable, Hashable {
            case session
            case named(String)
        }

        let kind: Kind
    }
}

extension OpenAIOptions {
    /// How much of its reasoning a model summarizes for the answer's reasoning entry.
    public struct ReasoningSummary: ProviderVocabulary {
        /// The most detailed summary the model writes.
        public static let auto: Self = "auto"

        /// A short summary.
        public static let concise: Self = "concise"

        /// A detailed summary.
        public static let detailed: Self = "detailed"

        /// The summary's name in OpenAI's API.
        public let rawValue: String

        /// Creates a summary from its name in OpenAI's API.
        ///
        /// - Parameter rawValue: The name, such as `"auto"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

extension OpenAIOptions {
    /// How long and detailed a model's answers are, from `low` to `high`.
    public struct Verbosity: ProviderVocabulary {
        /// Short, concise answers.
        public static let low: Self = "low"

        /// Answers of the usual length, the model's default.
        public static let medium: Self = "medium"

        /// Longer, more detailed answers.
        public static let high: Self = "high"

        /// The level's name in OpenAI's API.
        public let rawValue: String

        /// Creates a level from its name in OpenAI's API.
        ///
        /// - Parameter rawValue: The name, such as `"low"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}
