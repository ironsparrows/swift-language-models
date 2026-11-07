import LanguageModels

/// The members of a Responses request that only OpenAI's options set, each left out when the option keeps OpenAI's
/// default.
struct OpenAIBodyExtras: Encodable {
    let parallelToolCalls: Bool?
    let serviceTier: OpenAIServiceTier?
    let promptCacheKey: String?
    let safetyIdentifier: String?

    private enum CodingKeys: String, CodingKey {
        case parallelToolCalls = "parallel_tool_calls"
        case serviceTier = "service_tier"
        case promptCacheKey = "prompt_cache_key"
        case safetyIdentifier = "safety_identifier"
    }

    /// The key of `parallel_tool_calls`, which goes out only to models that take tools.
    static let parallelToolCallsKey = Responses.Member(rawValue: CodingKeys.parallelToolCalls.rawValue)
}

/// The members OpenAI adds to `text`: how long and detailed the answer is.
struct OpenAITextExtras: Encodable, Sendable {
    let verbosity: OpenAIOptions.Verbosity
}
