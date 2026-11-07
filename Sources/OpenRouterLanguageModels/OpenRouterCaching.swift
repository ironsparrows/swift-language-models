import Foundation
import FoundationModels
import LanguageModels
import os

// MARK: - Cache control

/// How requests mark prompts for caching, and how long a cached prompt lasts.
///
/// Some hosts, Anthropic for Claude and Alibaba for Qwen, cache a prompt only when the request marks it. Others, such
/// as OpenAI, Google, DeepSeek and xAI, cache long prompts on their own, with or without marks. A marked request asks
/// for caching of the whole prompt and marks the end of the instructions.
///
/// ``automatic``, the model's default, marks a request only when every model it may reach, fallbacks included, caches
/// only marked prompts. ``always`` marks every request, such as for Claude with another vendor's fallback, or for
/// Gemini, where a mark switches implicit caching to explicit caching, which bills storage.
///
/// Writing a marked cache costs more than a normal prompt, and reading it costs much less. A prompt shorter than the
/// host's minimum, such as 1,024 tokens, isn't cached at all.
public struct OpenRouterCacheControl: Sendable, Hashable {
    /// How long a cached prompt lasts after its last use, as OpenRouter's `ttl` spells it.
    ///
    /// Any lifetime OpenRouter offers is valid too, written as its `ttl` value.
    public struct TimeToLive: ProviderVocabulary {
        /// Five minutes, the hosts' default.
        public static let fiveMinutes: Self = "5m"

        /// One hour, which costs more to write. Hosts without it use their default.
        public static let oneHour: Self = "1h"

        /// The lifetime as OpenRouter's `ttl` spells it.
        public let rawValue: String

        /// Creates a lifetime from OpenRouter's spelling of it.
        ///
        /// - Parameter rawValue: The `ttl` value, such as `"1h"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// How long a cached prompt lasts.
    public let timeToLive: TimeToLive

    /// Whether every request is marked, whatever models it may reach.
    fileprivate let marksEveryModel: Bool

    /// Five-minute caching, marked only when every model a request may reach caches only marked prompts.
    public static let automatic = Self.automatic(timeToLive: .fiveMinutes)

    /// Five-minute caching, marked on every request.
    public static let always = Self.always(timeToLive: .fiveMinutes)

    /// Caching that lasts for the given time, marked only when every model a request may reach caches only marked
    /// prompts: a Claude model, or one whose ``OpenRouterModel/cachesOnlyMarkedPrompts`` is `true`.
    ///
    /// - Parameter timeToLive: How long a cached prompt lasts.
    /// - Returns: The cache control.
    public static func automatic(timeToLive: TimeToLive) -> Self {
        Self(timeToLive: timeToLive, marksEveryModel: false)
    }

    /// Caching that lasts for the given time, marked on every request.
    ///
    /// - Parameter timeToLive: How long a cached prompt lasts.
    /// - Returns: The cache control.
    public static func always(timeToLive: TimeToLive) -> Self {
        Self(timeToLive: timeToLive, marksEveryModel: true)
    }

    /// The `cache_control` directive in OpenRouter's request.
    var directive: Directive {
        Directive(timeToLive: timeToLive == .fiveMinutes ? nil : timeToLive)
    }
}

extension OpenRouterLanguageModel {
    /// The cache control a request sends: the model's own, unless it's automatic and a model the request may reach
    /// caches prompts without marks.
    var requestCacheControl: OpenRouterCacheControl? {
        guard let cacheControl else { return nil }
        let needsMarks = details.needsCacheMarks && fallbacks.allSatisfy(\.needsCacheMarks)
        return cacheControl.marksEveryModel || needsMarks ? cacheControl : nil
    }
}

extension OpenRouterModel {
    /// Whether the model caches only marked prompts: its details say so, or it's a Claude model, whose details may have
    /// been built by hand without saying so.
    fileprivate var needsCacheMarks: Bool {
        cachesOnlyMarkedPrompts || id.isAnthropic
    }
}

// MARK: - Response cache

/// OpenRouter's response cache, which answers a request that repeats an earlier one with the earlier answer, at no
/// cost.
///
/// With a response cache set, OpenRouter keeps each successful answer, and a later request with the same API key and
/// the same body gets the kept answer back at once, streamed as before, without reaching a host:
///
/// ```swift
/// var model = OpenRouterLanguageModel(.openaiGpt5Mini, auth: .apiKey { try await keyStore.openRouterKey() })
/// model.responseCache = OpenRouterResponseCache(timeToLive: .seconds(3_600))
/// ```
///
/// A hit bills nothing: its usage is zero tokens and its cost zero. It has a response id of its own, and
/// ``OpenRouterResponseMetadata/responseCacheSourceID`` names the answer it repeats.
/// ``OpenRouterResponseMetadata/responseCacheStatus`` says whether the cache served an answer.
///
/// - A hit repeats the kept answer as it is, whatever the temperature, sampling mode or seed, so sampling with
///   randomness gives the same answer each time. Set ``refreshes`` to replace kept answers with new ones.
/// - A request repeats another only when every part of its body does: the model and its fallbacks, the transcript,
///   tools, schema and options, the request metadata and ``OpenRouterOptions/endUserID``. Each request sends the
///   session's transcript so far, so a hit needs a session that has gone the same way, such as a new session with the
///   same instructions and first prompt, or a workflow that runs again after it failed.
/// - The session id that keeps a session's requests on the host that cached its prompt differs for every session, so
///   while the cache is on it goes in the `X-Session-Id` header, which the cache doesn't compare, instead of the body.
///   A session's requests still go to one host.
/// - OpenRouter keeps only successful answers, tool calls included, and may drop one before it expires. Two identical
///   requests sent at once both miss, and both are billed.
/// - A hit repeats the answer's tool calls, not what the tools did: the session runs each tool again. A tool that
///   writes data needs to skip a repeat by an operation id the app owns, which a retry reuses and a new operation
///   doesn't. The arguments alone aren't enough, since a model can make two calls with the same arguments on purpose.
/// - The cache belongs to the API key: another key, even of the same account, starts empty. OpenRouter turns the cache
///   off for an account that enforces zero data retention.
public struct OpenRouterResponseCache: Sendable, Hashable {
    /// How long OpenRouter keeps an answer, in whole seconds from 1 second to 24 hours.
    public let timeToLive: Duration

    /// Whether each request replaces the answer kept for it with a new one, which is kept for ``timeToLive``.
    ///
    /// The request reaches a host and is billed like one without the cache. Set it on a copy of the model for the
    /// requests whose kept answers are stale.
    public var refreshes: Bool

    /// Creates a response cache.
    ///
    /// - Parameters:
    ///   - timeToLive: How long OpenRouter keeps an answer. A fraction of a second is dropped, and the rest is clamped
    ///     to 1 second through 24 hours, with a runtime warning in a debug build.
    ///   - refreshes: Whether each request replaces the answer kept for it with a new one.
    public init(timeToLive: Duration = .seconds(300), refreshes: Bool = false) {
        let kept = Self.timeToLive(clamping: timeToLive)
        self.timeToLive = kept
        self.refreshes = refreshes
        guard kept != timeToLive else { return }
        let requested = Double(timeToLive.components.seconds) + Double(timeToLive.components.attoseconds) / 1e18
        let message = """
            OpenRouter's response cache keeps answers for whole seconds from 1 second to 24 hours, so a time to live of \
            \(requested) s becomes \(kept.components.seconds) s.
            """
        PackageLogger.openRouter(.info)?.info("\(message, privacy: .public)")
        runtimeWarning(message)
    }

    /// A time to live in whole seconds from 1 second to 24 hours, as OpenRouter takes it.
    private static func timeToLive(clamping requested: Duration) -> Duration {
        .seconds(min(max(requested.components.seconds, 1), 86_400))
    }

    /// The request headers that turn the cache on, set how long an answer is kept and replace the kept answer when
    /// refreshing, with the session id, which the cache doesn't compare.
    ///
    /// - Parameter sessionID: The id that keeps a session's requests on one host, or `nil` when there's none.
    /// - Returns: The headers by name.
    func headers(sessionID: String?) -> [String: String] {
        var headers = [API.Header.cache: "true", API.Header.cacheTimeToLive: String(timeToLive.components.seconds)]
        headers[API.Header.cacheClear] = refreshes ? "true" : nil
        headers[API.Header.sessionID] = sessionID
        return headers
    }
}

extension OpenRouterResponseCache {
    /// Whether the response cache served an answer, in the cache's own word for it, such as `HIT`.
    public struct Status: ProviderVocabulary {
        /// The cache served an answer it kept from an earlier request, at no cost.
        public static let hit: Self = "HIT"

        /// The cache had no answer for the request, so a host answered, and the cache now keeps the answer.
        public static let miss: Self = "MISS"

        /// The status's word in OpenRouter's response headers.
        public let rawValue: String

        /// Creates a status from its word in OpenRouter's response headers.
        ///
        /// - Parameter rawValue: The word, such as `"HIT"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

extension OpenRouterResponseCache {
    /// What OpenRouter's response cache reported about an answer, in the headers of its response.
    struct Report {
        /// Whether the cache served the answer or kept a new one.
        let status: Status

        /// How long the cache had kept the answer, in seconds, on a hit.
        let age: Int?

        /// The generation id of the answer the cache kept, on a hit.
        let sourceID: String?

        /// The report that a response's headers hold, or `nil` when they hold none, as when the cache is off.
        ///
        /// - Parameter header: The value of one of the response's headers, or `nil` when it has none.
        init?(header: (String) -> String?) {
            guard let status = header(API.Header.cacheStatus), !status.isEmpty else { return nil }
            self.status = Status(rawValue: status.uppercased())
            age = header(API.Header.cacheAge).flatMap { Int($0) }
            sourceID = header(API.Header.cacheSourceID)
        }
    }
}

// MARK: - Wire

extension OpenRouterCacheControl {
    /// The `cache_control` directive: an ephemeral cache, with its lifetime unless it's OpenRouter's default.
    struct Directive: Encodable, Sendable {
        fileprivate let timeToLive: TimeToLive?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode("ephemeral", forKey: .type)
            try container.encodeIfPresent(timeToLive, forKey: .timeToLive)
        }

        private enum Key: String, CodingKey {
            case type
            case timeToLive = "ttl"
        }
    }
}
