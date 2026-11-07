public import Foundation

// MARK: - Pricing

/// What OpenRouter charges for a model, in US dollars: per token, and per request, image or search for the fees that
/// some models charge on top.
///
/// The base prices apply by default. Overrides replace some of them for some requests, such as those with a long
/// prompt or those sent at an off-peak hour, and ``prices(forPromptTokens:at:)`` applies the ones that match a
/// request. These prices are for estimates before a request; a response reports what the request actually cost.
public struct OpenRouterPricing: Sendable, Hashable {
    /// The price of one prompt token.
    public let prompt: Decimal

    /// The price of one generated token.
    public let completion: Decimal

    /// The price of one prompt token read from the prompt cache, when the model caches prompts.
    public let cacheRead: Decimal?

    /// The price of one prompt token written to the prompt cache, when writing costs extra.
    public let cacheWrite: Decimal?

    /// The price of one prompt token written to the prompt cache for an hour, when the model can cache that long.
    public let cacheWriteOneHour: Decimal?

    /// The price of one reasoning token, when the model prices reasoning apart from ``completion``.
    public let reasoning: Decimal?

    /// The price of one audio token in the prompt, when audio costs other than text.
    public let audio: Decimal?

    /// The price of one image in the prompt, when images cost other than text.
    public let image: Decimal?

    /// The fee for each request, on top of its tokens, when the model charges one.
    public let request: Decimal?

    /// The price of one web search that the model or its host runs, such as the search that Perplexity's Sonar models
    /// run for every request, or a host's own search for an ``OpenRouterServerTool`` web search.
    public let webSearch: Decimal?

    /// Prices that replace the base prices while their conditions hold. Where several apply, a later one wins for
    /// each price it sets.
    public let overrides: [Override]

    /// The fraction OpenRouter takes off these prices, from 0, for none, to 1, for free. The prices are before it.
    public let discount: Double

    /// Creates a model's pricing.
    ///
    /// - Parameters:
    ///   - prompt: The price of one prompt token.
    ///   - completion: The price of one generated token.
    ///   - cacheRead: The price of one prompt token read from the prompt cache.
    ///   - cacheWrite: The price of one prompt token written to the prompt cache.
    ///   - cacheWriteOneHour: The price of one prompt token written to the prompt cache for an hour.
    ///   - reasoning: The price of one reasoning token, when it isn't the price of a generated token.
    ///   - audio: The price of one audio token in the prompt.
    ///   - image: The price of one image in the prompt.
    ///   - request: The fee for each request, on top of its tokens.
    ///   - webSearch: The price of one web search.
    ///   - overrides: Prices that replace these while their conditions hold, a later one winning.
    ///   - discount: The fraction OpenRouter takes off these prices.
    public init(
        prompt: Decimal,
        completion: Decimal,
        cacheRead: Decimal? = nil,
        cacheWrite: Decimal? = nil,
        cacheWriteOneHour: Decimal? = nil,
        reasoning: Decimal? = nil,
        audio: Decimal? = nil,
        image: Decimal? = nil,
        request: Decimal? = nil,
        webSearch: Decimal? = nil,
        overrides: [Override] = [],
        discount: Double = 0
    ) {
        self.prompt = prompt
        self.completion = completion
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.cacheWriteOneHour = cacheWriteOneHour
        self.reasoning = reasoning
        self.audio = audio
        self.image = image
        self.request = request
        self.webSearch = webSearch
        self.overrides = overrides
        self.discount = discount
    }

    /// The prices for one request, with the overrides that apply to it.
    ///
    /// - Parameters:
    ///   - promptTokens: The request's prompt length, in tokens.
    ///   - date: When the request is sent.
    /// - Returns: The prices, with no overrides left. The fees that no override changes, such as ``request`` and
    ///   ``webSearch``, carry over, and so does the ``discount``.
    public func prices(forPromptTokens promptTokens: Int, at date: Date = .now) -> OpenRouterPricing {
        let moment = Moment(date)
        let applying = overrides.filter { $0.condition.holds(promptTokens: promptTokens, at: moment) }
        return applying.reduce(withoutOverrides) { prices, override in
            OpenRouterPricing(
                prompt: override.prompt ?? prices.prompt,
                completion: override.completion ?? prices.completion,
                cacheRead: override.cacheRead ?? prices.cacheRead,
                cacheWrite: override.cacheWrite ?? prices.cacheWrite,
                cacheWriteOneHour: override.cacheWriteOneHour ?? prices.cacheWriteOneHour,
                reasoning: prices.reasoning,
                audio: override.audio ?? prices.audio,
                image: prices.image,
                request: prices.request,
                webSearch: prices.webSearch,
                discount: discount
            )
        }
    }

    /// The base prices, with no overrides.
    private var withoutOverrides: OpenRouterPricing {
        OpenRouterPricing(
            prompt: prompt,
            completion: completion,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            cacheWriteOneHour: cacheWriteOneHour,
            reasoning: reasoning,
            audio: audio,
            image: image,
            request: request,
            webSearch: webSearch,
            discount: discount
        )
    }
}

extension OpenRouterPricing {
    /// Prices that replace the base prices while a condition holds. A price it doesn't set stays as it was.
    public struct Override: Sendable, Hashable {
        /// When the override applies.
        public let condition: Condition

        /// The price of one prompt token.
        public let prompt: Decimal?

        /// The price of one generated token.
        public let completion: Decimal?

        /// The price of one prompt token read from the prompt cache.
        public let cacheRead: Decimal?

        /// The price of one prompt token written to the prompt cache.
        public let cacheWrite: Decimal?

        /// The price of one prompt token written to the prompt cache for an hour.
        public let cacheWriteOneHour: Decimal?

        /// The price of one audio token in the prompt.
        public let audio: Decimal?

        /// Creates an override.
        ///
        /// - Parameters:
        ///   - condition: When the override applies.
        ///   - prompt: The price of one prompt token.
        ///   - completion: The price of one generated token.
        ///   - cacheRead: The price of one prompt token read from the prompt cache.
        ///   - cacheWrite: The price of one prompt token written to the prompt cache.
        ///   - cacheWriteOneHour: The price of one prompt token written to the prompt cache for an hour.
        ///   - audio: The price of one audio token in the prompt.
        public init(
            condition: Condition,
            prompt: Decimal? = nil,
            completion: Decimal? = nil,
            cacheRead: Decimal? = nil,
            cacheWrite: Decimal? = nil,
            cacheWriteOneHour: Decimal? = nil,
            audio: Decimal? = nil
        ) {
            self.condition = condition
            self.prompt = prompt
            self.completion = completion
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
            self.cacheWriteOneHour = cacheWriteOneHour
            self.audio = audio
        }

        /// When an override applies: every part the condition sets must hold, and a condition that sets none always
        /// holds.
        public struct Condition: Sendable, Hashable {
            /// The prompt length, in tokens, that a request must exceed.
            public let promptTokensAbove: Int?

            /// The days, in UTC, that a request must be sent on.
            public let weekdays: Set<Locale.Weekday>?

            /// The time of day, in UTC, that a request must be sent in.
            public let hours: TimeWindow?

            /// Creates a condition.
            ///
            /// - Parameters:
            ///   - promptTokensAbove: The prompt length, in tokens, that a request must exceed.
            ///   - weekdays: The days, in UTC, that a request must be sent on.
            ///   - hours: The time of day, in UTC, that a request must be sent in.
            public init(promptTokensAbove: Int? = nil, weekdays: Set<Locale.Weekday>? = nil, hours: TimeWindow? = nil) {
                self.promptTokensAbove = promptTokensAbove
                self.weekdays = weekdays
                self.hours = hours
            }

            /// Whether the condition holds for a request.
            fileprivate func holds(promptTokens: Int, at moment: Moment) -> Bool {
                if let promptTokensAbove, promptTokens <= promptTokensAbove { return false }
                if let weekdays, !weekdays.contains(moment.weekday) { return false }
                if let hours, !hours.contains(moment.timeOfDay) { return false }
                return true
            }
        }
    }
}

extension OpenRouterPricing {
    /// A daily window of time in UTC, which runs past midnight when it ends before it starts.
    public struct TimeWindow: Sendable, Hashable {
        /// When the window opens, as the time after midnight.
        public let start: Duration

        /// When the window closes, as the time after midnight. A time that equals it is outside the window.
        public let end: Duration

        /// Creates a window.
        ///
        /// - Parameters:
        ///   - start: When the window opens, as the time after midnight UTC.
        ///   - end: When the window closes, as the time after midnight UTC.
        public init(start: Duration, end: Duration) {
            self.start = start
            self.end = end
        }

        /// Whether a time of day falls in the window.
        ///
        /// - Parameter timeOfDay: The time after midnight UTC.
        /// - Returns: Whether the time is from ``start`` up to, but not including, ``end``.
        public func contains(_ timeOfDay: Duration) -> Bool {
            start <= end ? (start..<end).contains(timeOfDay) : timeOfDay >= start || timeOfDay < end
        }
    }
}

extension OpenRouterPricing {
    /// A request's send time, as the UTC weekday and time of day an override's condition reads.
    fileprivate struct Moment {
        private static let weekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

        let weekday: Locale.Weekday
        let timeOfDay: Duration

        init(_ date: Date) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            weekday = Self.weekdays[calendar.component(.weekday, from: date) - 1]
            timeOfDay = .seconds(date.timeIntervalSince(calendar.startOfDay(for: date)))
        }
    }
}

// MARK: - Wire

extension OpenRouterPricing {
    /// A `pricing` object in OpenRouter's model and endpoint lists, with each price as decimal text in US dollars.
    struct Payload: Decodable, Sendable {
        /// Prices that replace the base prices while their conditions hold.
        fileprivate struct Override: Decodable, Sendable {
            let minPromptTokens: Double?
            let utcDays: [String]?
            /// The start of a daily window in UTC, as an `HHMM` clock number such as `130` for 01:30.
            let utcStart: Double?
            /// The end of the window, exclusive, in the same form.
            let utcEnd: Double?
            let prompt: String?
            let completion: String?
            let inputCacheRead: String?
            let inputCacheWrite: String?
            let inputCacheWriteOneHour: String?
            let audio: String?

            private enum CodingKeys: String, CodingKey {
                case minPromptTokens = "min_prompt_tokens"
                case utcDays = "utc_days"
                case utcStart = "utc_start"
                case utcEnd = "utc_end"
                case prompt, completion, audio
                case inputCacheRead = "input_cache_read"
                case inputCacheWrite = "input_cache_write"
                case inputCacheWriteOneHour = "input_cache_write_1h"
            }
        }

        fileprivate let prompt: String?
        fileprivate let completion: String?
        fileprivate let inputCacheRead: String?
        fileprivate let inputCacheWrite: String?
        fileprivate let inputCacheWriteOneHour: String?
        fileprivate let internalReasoning: String?
        fileprivate let audio: String?
        fileprivate let image: String?
        fileprivate let request: String?
        fileprivate let webSearch: String?
        /// The fraction taken off the endpoint's prices, from 0 to 1.
        fileprivate let discount: Double?
        fileprivate let overrides: [Override]?

        private enum CodingKeys: String, CodingKey {
            case prompt, completion, audio, image, request, discount, overrides
            case inputCacheRead = "input_cache_read"
            case inputCacheWrite = "input_cache_write"
            case inputCacheWriteOneHour = "input_cache_write_1h"
            case internalReasoning = "internal_reasoning"
            case webSearch = "web_search"
        }
    }
}

extension OpenRouterPricing {
    /// The prices in a `pricing` object, or `nil` when it lacks a prompt or completion price or has a negative one,
    /// which OpenRouter sends for a model whose price depends on the request, such as a router.
    ///
    /// An override whose time window isn't a time of day, or that changes none of the prices kept here, is left out.
    init?(_ payload: OpenRouterPricing.Payload) {
        guard let prompt = Self.price(payload.prompt), let completion = Self.price(payload.completion) else { return nil }
        self.init(
            prompt: prompt,
            completion: completion,
            cacheRead: Self.price(payload.inputCacheRead),
            cacheWrite: Self.price(payload.inputCacheWrite),
            cacheWriteOneHour: Self.price(payload.inputCacheWriteOneHour),
            reasoning: Self.price(payload.internalReasoning),
            audio: Self.price(payload.audio),
            image: Self.price(payload.image),
            request: Self.price(payload.request),
            webSearch: Self.price(payload.webSearch),
            overrides: (payload.overrides ?? []).compactMap(Override.init),
            discount: payload.discount ?? 0
        )
    }

    /// A price from OpenRouter's decimal text, or `nil` for a negative one or text that isn't a number.
    private static func price(_ text: String?) -> Decimal? {
        guard let text, let price = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), price >= 0 else {
            return nil
        }
        return price
    }
}

extension OpenRouterPricing.Override {
    /// The override in a `pricing` object, or `nil` when its window isn't a time of day or it changes no price.
    fileprivate init?(_ payload: OpenRouterPricing.Payload.Override) {
        let prices =
            [payload.prompt, payload.completion, payload.inputCacheRead, payload.inputCacheWrite]
            + [payload.inputCacheWriteOneHour, payload.audio]
        guard prices.contains(where: { OpenRouterPricing.price($0) != nil }) else { return nil }
        var hours: OpenRouterPricing.TimeWindow?
        if payload.utcStart != nil || payload.utcEnd != nil {
            guard let start = Self.timeOfDay(clockNumber: payload.utcStart ?? 0),
                let end = Self.timeOfDay(clockNumber: payload.utcEnd ?? 2_400)
            else { return nil }
            hours = OpenRouterPricing.TimeWindow(start: start, end: end)
        }
        self.init(
            condition: Condition(
                // The threshold counts whole tokens, so a fraction rounds down without changing which prompts exceed it.
                // One past Int's range keeps its meaning: every prompt exceeds a huge negative one, and none a huge one.
                promptTokensAbove: payload.minPromptTokens.map { Int(exactly: $0.rounded(.down)) ?? ($0 < 0 ? .min : .max) },
                weekdays: payload.utcDays.map { Set($0.compactMap(Self.weekday)) },
                hours: hours
            ),
            prompt: OpenRouterPricing.price(payload.prompt),
            completion: OpenRouterPricing.price(payload.completion),
            cacheRead: OpenRouterPricing.price(payload.inputCacheRead),
            cacheWrite: OpenRouterPricing.price(payload.inputCacheWrite),
            cacheWriteOneHour: OpenRouterPricing.price(payload.inputCacheWriteOneHour),
            audio: OpenRouterPricing.price(payload.audio)
        )
    }

    /// The time after midnight of an `HHMM` clock number, such as 1h30m for `130`, or `nil` when the number isn't a
    /// time from 00:00 to 24:00.
    private static func timeOfDay(clockNumber: Double) -> Duration? {
        guard let clock = Int(exactly: clockNumber), clock >= 0 else { return nil }
        let (hours, minutes) = clock.quotientAndRemainder(dividingBy: 100)
        guard (0...24).contains(hours), (0..<60).contains(minutes), hours < 24 || minutes == 0 else { return nil }
        return .seconds(hours * 3_600 + minutes * 60)
    }

    /// The day an override names, such as `monday`, or `nil` for any other name, which no request matches.
    private static func weekday(_ name: String) -> Locale.Weekday? {
        switch name {
        case "sunday": .sunday
        case "monday": .monday
        case "tuesday": .tuesday
        case "wednesday": .wednesday
        case "thursday": .thursday
        case "friday": .friday
        case "saturday": .saturday
        default: nil
        }
    }
}
