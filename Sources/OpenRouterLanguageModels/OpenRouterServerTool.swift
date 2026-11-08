public import Foundation
public import FoundationModels
import LanguageModels

// MARK: - Server tool

/// A tool that OpenRouter runs for the model while it answers, such as a web search or a call to another model.
///
/// Server tools are a setting of the model, in ``OpenRouterLanguageModel/serverTools``, rather than Foundation Models
/// tools: the app implements nothing, and their calls never reach the session. The model decides when to call one, and
/// OpenRouter runs it and hands the result back to the model, which may call it again before it answers. A request
/// lists them after the session's own tools, in the order given.
///
/// ```swift
/// let model = OpenRouterLanguageModel(
///     .openaiGpt5Mini,
///     serverTools: [.webSearch(maximumResults: 3, allowedDomains: ["swift.org"]), .datetime(timeZone: .current)],
///     auth: .apiKey { try await keyStore.openRouterKey() }
/// )
/// ```
///
/// A web search or web fetch costs extra, on top of the model's tokens, and its engine keeps what it's sent under its
/// own data retention policy; ``OpenRouterWebSearchEngine`` and ``OpenRouterWebFetchEngine`` say which engine runs
/// when and what each costs. The date and time cost nothing and never leave OpenRouter. An advisor or a subagent calls
/// another model, billed at that model's price on top of the model's own tokens, and only the answer it informs reaches
/// the session.
///
/// Two tools are equal when a request sends the same entry for them.
public struct OpenRouterServerTool: Sendable, Hashable {
    /// The tool's type and parameters, as a request lists them.
    let entry: Entry

    private init(_ entry: Entry) {
        self.entry = entry
    }

    /// Searches the web, so the model can answer with current information and cite the pages it used.
    ///
    /// The answer's response entry lists the cited pages, which ``OpenRouterResponseMetadata/citations`` reads.
    ///
    /// - Parameters:
    ///   - engine: The engine that searches, or `nil` for OpenRouter's default, `auto`: the host's own search when the
    ///     model's host has one, and Exa otherwise.
    ///   - mode: How deep Exa or Parallel searches, or `nil` for the engine's default. Other engines ignore it.
    ///   - maximumResults: The most results of one search, from 1 to 25, or `nil` for OpenRouter's default of 5. The
    ///     hosts' own search ignores it.
    ///   - maximumTotalResults: The most results across all of an answer's searches. Searches past it tell the model
    ///     the limit was reached instead of returning results.
    ///   - maximumSearches: The most searches in one answer. Searches past it return an error to the model instead of
    ///     running. Of the hosts' own search, only Anthropic's takes it.
    ///   - searchContextSize: How much of each page the model gets, for Exa, Parallel and Perplexity.
    ///   - allowedDomains: The only domains to return results from, such as `"arxiv.org"`. Most engines take either
    ///     this list or `excludedDomains`, not both, and Google's own search takes neither.
    ///   - excludedDomains: Domains never to return results from.
    /// - Returns: The web search.
    public static func webSearch(
        engine: OpenRouterWebSearchEngine? = nil,
        mode: OpenRouterWebSearchMode? = nil,
        maximumResults: Int? = nil,
        maximumTotalResults: Int? = nil,
        maximumSearches: Int? = nil,
        searchContextSize: OpenRouterSearchContextSize? = nil,
        allowedDomains: [String]? = nil,
        excludedDomains: [String]? = nil
    ) -> Self {
        Self(
            .webSearch(
                WebSearch(
                    engine: engine, mode: mode, maximumResults: maximumResults, maximumTotalResults: maximumTotalResults,
                    maximumSearches: maximumSearches, searchContextSize: searchContextSize, allowedDomains: allowedDomains,
                    excludedDomains: excludedDomains)))
    }

    /// Fetches a web page or PDF the model names by its URL, and gives the model its text.
    ///
    /// - Parameters:
    ///   - engine: The engine that fetches, or `nil` for OpenRouter's default, `auto`: the host's own fetch when the
    ///     model's host has one, and Exa otherwise.
    ///   - maximumFetches: The most fetches in one answer. Fetches past it return an error to the model. OpenRouter's
    ///     own fetcher and the hosts' own fetch stop at 50 anyway.
    ///   - maximumContentTokens: The most content of one page, in approximate tokens; longer content is cut short.
    ///     The hosts' own fetch ignores it.
    ///   - allowedDomains: The only domains to fetch from, such as `"docs.example.com"`.
    ///   - excludedDomains: Domains never to fetch from.
    /// - Returns: The web fetch.
    public static func webFetch(
        engine: OpenRouterWebFetchEngine? = nil,
        maximumFetches: Int? = nil,
        maximumContentTokens: Int? = nil,
        allowedDomains: [String]? = nil,
        excludedDomains: [String]? = nil
    ) -> Self {
        Self(
            .webFetch(
                WebFetch(
                    engine: engine, maximumFetches: maximumFetches, maximumContentTokens: maximumContentTokens,
                    allowedDomains: allowedDomains, excludedDomains: excludedDomains)))
    }

    /// Tells the model the current date and time.
    ///
    /// - Parameter timeZone: The time zone of the date and time, as a time zone with an IANA identifier such as
    ///   `Europe/Athens`, or `nil` for UTC.
    /// - Returns: The date and time tool.
    public static func datetime(timeZone: TimeZone? = nil) -> Self {
        Self(.datetime(timeZone: timeZone?.identifier))
    }

    /// Lets the model consult another model, usually a stronger one, for advice while it answers, such as before it
    /// settles on an approach or when it's stuck.
    ///
    /// The model sends the advisor a prompt, and OpenRouter returns the advisor's answer to the model, which writes the
    /// final answer. Each consultation is a request to the advisor model, billed at its price on top of the model's
    /// tokens, and it adds the time the advisor takes. The consultation never reaches the session: the answer's usage
    /// counts it among ``OpenRouterUsageMetadata/requestedServerToolCallCount``, and Chat Completions returns neither
    /// the prompt nor the advice. So the advisor can't recall its earlier consultations on later turns; with
    /// `forwardsTranscript`, it reads the whole conversation instead.
    ///
    /// To offer several advisors, list one advisor per model with a `name` each; at most one can go without a name,
    /// and keep their order across a session's requests. A required tool-calling mode doesn't force a consultation,
    /// since `tool_choice` goes out only with the session's own tools.
    ///
    /// - Parameters:
    ///   - model: The advisor model, such as `"~anthropic/claude-opus-latest"`, or `nil` to let the model name one in
    ///     each consultation, or else consult the model itself.
    ///   - name: The name the model knows the advisor by, of 1 to 64 letters, digits, spaces, `_` and `-`, or `nil`
    ///     for the default advisor.
    ///   - instructions: The advisor's instructions, or `nil` for none.
    ///   - forwardsTranscript: Whether the advisor reads the whole conversation, with the model's prompt after it,
    ///     rather than the prompt alone.
    ///   - maximumResponseTokens: The most tokens the advisor generates, reasoning included, or `nil` for its host's
    ///     default.
    ///   - reasoningLevel: How much the advisor reasons, as the nearest effort OpenRouter knows, or `nil` for its
    ///     default. A custom level that OpenRouter doesn't list is left out.
    ///   - maximumReasoningTokens: The most tokens the advisor reasons with, or `nil` for its default.
    ///   - temperature: The advisor's sampling temperature, from 0 to 2, or `nil` for its host's default.
    /// - Returns: The advisor.
    public static func advisor(
        model: OpenRouterModelID? = nil,
        name: String? = nil,
        instructions: String? = nil,
        forwardsTranscript: Bool = false,
        maximumResponseTokens: Int? = nil,
        reasoningLevel: ContextOptions.ReasoningLevel? = nil,
        maximumReasoningTokens: Int? = nil,
        temperature: Double? = nil
    ) -> Self {
        let call = ModelCall(
            model: model, name: name, instructions: instructions, maximumResponseTokens: maximumResponseTokens,
            reasoningLevel: reasoningLevel, maximumReasoningTokens: maximumReasoningTokens, temperature: temperature)
        return Self(.advisor(call, forwardsTranscript: forwardsTranscript))
    }

    /// Lets the model hand a self-contained task to another model, usually a smaller and cheaper one, such as
    /// summarizing a document or drafting boilerplate, and use its outcome while it answers.
    ///
    /// The model describes the task, and OpenRouter returns the worker model's outcome to the model. The worker reads
    /// only that description, never the conversation, and keeps nothing between tasks. Each task is a request to the
    /// worker model, billed at its price on top of the model's tokens, and more when the worker uses server tools. The
    /// task never reaches the session; the answer's usage counts it among
    /// ``OpenRouterUsageMetadata/requestedServerToolCallCount``.
    ///
    /// To offer several workers, list one subagent per model with a `name` each; at most one can go without a name,
    /// and keep their order across a session's requests.
    ///
    /// - Parameters:
    ///   - model: The worker model, such as `"~anthropic/claude-haiku-latest"`, or `nil` for the model itself.
    ///   - name: The name the model knows the worker by, of 1 to 64 letters, digits, spaces, `_` and `-`, or `nil`
    ///     for the default worker.
    ///   - instructions: The worker's instructions, or `nil` for none.
    ///   - tools: Server tools the worker can use for a task, such as `.webSearch()`, but no subagent. The session's
    ///     own tools never reach it.
    ///   - maximumToolCalls: The most tool-calling steps the worker takes for one task, from 1 to 25, or `nil` for
    ///     OpenRouter's default.
    ///   - maximumResponseTokens: The most tokens the worker generates, reasoning included, or `nil` for its host's
    ///     default.
    ///   - reasoningLevel: How much the worker reasons, as the nearest effort OpenRouter knows, or `nil` for its
    ///     default. A custom level that OpenRouter doesn't list is left out.
    ///   - maximumReasoningTokens: The most tokens the worker reasons with, or `nil` for its default.
    ///   - temperature: The worker's sampling temperature, from 0 to 2, or `nil` for its host's default.
    /// - Returns: The subagent.
    public static func subagent(
        model: OpenRouterModelID? = nil,
        name: String? = nil,
        instructions: String? = nil,
        tools: [OpenRouterServerTool] = [],
        maximumToolCalls: Int? = nil,
        maximumResponseTokens: Int? = nil,
        reasoningLevel: ContextOptions.ReasoningLevel? = nil,
        maximumReasoningTokens: Int? = nil,
        temperature: Double? = nil
    ) -> Self {
        let call = ModelCall(
            model: model, name: name, instructions: instructions, maximumResponseTokens: maximumResponseTokens,
            reasoningLevel: reasoningLevel, maximumReasoningTokens: maximumReasoningTokens, temperature: temperature)
        return Self(.subagent(call, tools: tools, maximumToolCalls: maximumToolCalls))
    }
}

// MARK: - Wire

extension OpenRouterServerTool {
    /// A server tool's entry in a request's `tools`: its type, and its parameters when any is set, in the order a
    /// request lists them.
    enum Entry: Encodable, Sendable, Hashable {
        case webSearch(WebSearch)
        case webFetch(WebFetch)
        case datetime(timeZone: String?)
        case advisor(ModelCall, forwardsTranscript: Bool)
        case subagent(ModelCall, tools: [OpenRouterServerTool], maximumToolCalls: Int?)

        /// The tool's type.
        private var type: String {
            switch self {
            case .webSearch: "openrouter:web_search"
            case .webFetch: "openrouter:web_fetch"
            case .datetime: "openrouter:datetime"
            case .advisor: "openrouter:advisor"
            case .subagent: "openrouter:subagent"
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(type, forKey: .type)
            let parameters = try JSONValueEncoder.members(of: Parameters(entry: self))
            if !parameters.members.isEmpty { try container.encode(JSONValue.object(parameters), forKey: .parameters) }
        }

        private enum Key: String, CodingKey {
            case type
            case parameters
        }
    }

    /// The parameters of an entry that are set.
    private struct Parameters: Encodable {
        let entry: Entry

        func encode(to encoder: any Encoder) throws {
            switch entry {
            case .webSearch(let search): try search.encode(to: encoder)
            case .webFetch(let fetch): try fetch.encode(to: encoder)
            case .datetime(let timeZone):
                var container = encoder.container(keyedBy: Key.self)
                try container.encodeIfPresent(timeZone, forKey: .timeZone)
            case .advisor(let call, let forwardsTranscript):
                try call.encode(to: encoder)
                var container = encoder.container(keyedBy: Key.self)
                if forwardsTranscript { try container.encode(true, forKey: .forwardTranscript) }
            case .subagent(let call, let tools, let maximumToolCalls):
                try call.encode(to: encoder)
                var container = encoder.container(keyedBy: Key.self)
                if !tools.isEmpty { try container.encode(tools.map(\.entry), forKey: .tools) }
                try container.encodeIfPresent(maximumToolCalls, forKey: .maximumToolCalls)
            }
        }

        private enum Key: String, CodingKey {
            case timeZone = "timezone"
            case forwardTranscript = "forward_transcript"
            case tools
            case maximumToolCalls = "max_tool_calls"
        }
    }

    /// The parameters of a web search.
    struct WebSearch: Encodable, Sendable, Hashable {
        fileprivate let engine: OpenRouterWebSearchEngine?
        fileprivate let mode: OpenRouterWebSearchMode?
        fileprivate let maximumResults: Int?
        fileprivate let maximumTotalResults: Int?
        fileprivate let maximumSearches: Int?
        fileprivate let searchContextSize: OpenRouterSearchContextSize?
        fileprivate let allowedDomains: [String]?
        fileprivate let excludedDomains: [String]?

        private enum CodingKeys: String, CodingKey {
            case engine
            case mode
            case maximumResults = "max_results"
            case maximumTotalResults = "max_total_results"
            case maximumSearches = "max_uses"
            case searchContextSize = "search_context_size"
            case allowedDomains = "allowed_domains"
            case excludedDomains = "excluded_domains"
        }
    }

    /// The parameters of a web fetch.
    struct WebFetch: Encodable, Sendable, Hashable {
        fileprivate let engine: OpenRouterWebFetchEngine?
        fileprivate let maximumFetches: Int?
        fileprivate let maximumContentTokens: Int?
        fileprivate let allowedDomains: [String]?
        fileprivate let excludedDomains: [String]?

        private enum CodingKeys: String, CodingKey {
            case engine
            case maximumFetches = "max_uses"
            case maximumContentTokens = "max_content_tokens"
            case allowedDomains = "allowed_domains"
            case excludedDomains = "blocked_domains"
        }
    }

    /// The parameters of a call to another model, which an advisor and a subagent share.
    struct ModelCall: Encodable, Sendable, Hashable {
        private let name: String?
        private let model: OpenRouterModelID?
        private let instructions: String?
        private let maximumResponseTokens: Int?
        private let reasoning: Reasoning?
        private let temperature: Double?

        /// The call's reasoning: the nearest effort OpenRouter names, and a token budget.
        private struct Reasoning: Encodable, Sendable, Hashable {
            let effort: String?
            let maximumTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case effort
                case maximumTokens = "max_tokens"
            }
        }

        fileprivate init(
            model: OpenRouterModelID?,
            name: String?,
            instructions: String?,
            maximumResponseTokens: Int?,
            reasoningLevel: ContextOptions.ReasoningLevel?,
            maximumReasoningTokens: Int?,
            temperature: Double?
        ) {
            self.name = name
            self.model = model
            self.instructions = instructions
            self.maximumResponseTokens = maximumResponseTokens
            let effort = reasoningLevel?.providerEffort(supporting: Self.everyEffort)
            reasoning =
                effort == nil && maximumReasoningTokens == nil ? nil : Reasoning(effort: effort, maximumTokens: maximumReasoningTokens)
            self.temperature = temperature
        }

        /// Every effort OpenRouter names, which a reasoning level goes to the nearest of.
        private static let everyEffort = ContextOptions.ReasoningLevel.effortRanking.map(ContextOptions.ReasoningLevel.custom)

        private enum CodingKeys: String, CodingKey {
            case name
            case model
            case instructions
            case maximumResponseTokens = "max_completion_tokens"
            case reasoning
            case temperature
        }
    }
}
