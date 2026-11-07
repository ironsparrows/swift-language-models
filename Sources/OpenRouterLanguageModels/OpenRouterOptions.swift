public import Foundation
public import LanguageModels

/// Request settings that only OpenRouter has, beyond Foundation Models' generation options.
///
/// Each sampling setting reaches the model only if the model lists its parameter, such as `frequency_penalty`, so a
/// setting a model doesn't take is left out instead of failing the request. Router settings reach only the router
/// model that reads them. Every setting left `nil` keeps the model's default.
public struct OpenRouterOptions: Sendable, Hashable {
    /// Lowers the chance of a token by how often it already appeared, from -2 to 2.
    public var frequencyPenalty: Double?

    /// Lowers the chance of a token that already appeared at all, from -2 to 2.
    public var presencePenalty: Double?

    /// Scales down the chance of tokens that already appeared; 1 means no penalty.
    public var repetitionPenalty: Double?

    /// Drops tokens whose chance is below this fraction of the most likely token's, from 0 to 1.
    public var minP: Double?

    /// Keeps only tokens with a chance close enough to the most likely token's, from 0 to 1.
    public var topA: Double?

    /// Text that ends the response when the model generates it, up to four sequences.
    public var stopSequences: [String]?

    /// Changes to the chance of specific tokens, by token id, from -100 to 100.
    public var logitBias: [Int: Double]?

    /// How long and detailed the answers are, such as `low` for concise ones.
    public var verbosity: OpenRouterOptions.Verbosity?

    /// The processing tier, such as `flex` or `priority`, which trades speed against price.
    public var serviceTier: OpenRouterServiceTier?

    /// A stable id for the app's end user, such as a hash, so a host can tell users apart for abuse checks.
    public var endUserID: String?

    /// How `openrouter/auto` and `openrouter/auto-beta` pick the model that answers.
    public var autoRouter: OpenRouterOptions.AutoRouter?

    /// How `openrouter/pareto-code` picks the coding model that answers.
    public var paretoRouter: OpenRouterOptions.ParetoRouter?

    /// Whether the model may ask for several of the session's tools in one answer.
    ///
    /// With ``ParallelToolCalls/automatic``, the request leaves the choice to the host. Either other choice reaches
    /// only models that list `parallel_tool_calls`, and with tools, OpenRouter then routes only to hosts that take it.
    /// Calls that arrive in one answer run as one round either way.
    public var parallelToolCalls: ParallelToolCalls

    /// The engine that reads PDF attachments, or `nil` for OpenRouter's default: the model's own reading when it reads
    /// PDFs, and Mistral's OCR, at a price per page, when it doesn't.
    ///
    /// It goes out only with a request that carries a PDF. With ``OpenRouterOptions/PDFEngine/native``, only models
    /// that read PDFs themselves take PDF attachments.
    public var pdfEngine: PDFEngine?

    /// Whether the answer reports how OpenRouter routed the request: the strategy, the endpoints it considered, each
    /// attempt, the edge region, the generation time and the plugins that changed the request or answer.
    ///
    /// The entry that ends the answer carries them under ``OpenRouterMetadataKey``, such as
    /// ``OpenRouterMetadataKey/routingStrategy``. An answer from the response cache never has them. Every request asks
    /// OpenRouter for this report, since only the report says a guardrail blocked a request, and this decides whether
    /// the answer keeps it.
    public var includesRouterMetadata: Bool

    /// Creates request settings.
    ///
    /// - Parameters:
    ///   - frequencyPenalty: Lowers the chance of a token by how often it already appeared.
    ///   - presencePenalty: Lowers the chance of a token that already appeared at all.
    ///   - repetitionPenalty: Scales down the chance of tokens that already appeared.
    ///   - minP: Drops tokens whose chance is below this fraction of the most likely token's.
    ///   - topA: Keeps only tokens with a chance close enough to the most likely token's.
    ///   - stopSequences: Text that ends the response when the model generates it.
    ///   - logitBias: Changes to the chance of specific tokens, by token id.
    ///   - verbosity: How long and detailed the answers are.
    ///   - serviceTier: The processing tier.
    ///   - endUserID: A stable id for the app's end user.
    ///   - autoRouter: How `openrouter/auto` and `openrouter/auto-beta` pick the model that answers.
    ///   - paretoRouter: How `openrouter/pareto-code` picks the coding model that answers.
    ///   - parallelToolCalls: Whether the model may ask for several of the session's tools in one answer.
    ///   - pdfEngine: The engine that reads PDF attachments, or `nil` for OpenRouter's default.
    ///   - includesRouterMetadata: Whether the answer reports how OpenRouter routed the request.
    public init(
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        repetitionPenalty: Double? = nil,
        minP: Double? = nil,
        topA: Double? = nil,
        stopSequences: [String]? = nil,
        logitBias: [Int: Double]? = nil,
        verbosity: OpenRouterOptions.Verbosity? = nil,
        serviceTier: OpenRouterServiceTier? = nil,
        endUserID: String? = nil,
        autoRouter: OpenRouterOptions.AutoRouter? = nil,
        paretoRouter: OpenRouterOptions.ParetoRouter? = nil,
        parallelToolCalls: ParallelToolCalls = .automatic,
        pdfEngine: PDFEngine? = nil,
        includesRouterMetadata: Bool = false
    ) {
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.repetitionPenalty = repetitionPenalty
        self.minP = minP
        self.topA = topA
        self.stopSequences = stopSequences
        self.logitBias = logitBias
        self.verbosity = verbosity
        self.serviceTier = serviceTier
        self.endUserID = endUserID
        self.autoRouter = autoRouter
        self.paretoRouter = paretoRouter
        self.parallelToolCalls = parallelToolCalls
        self.pdfEngine = pdfEngine
        self.includesRouterMetadata = includesRouterMetadata
    }
}

extension OpenRouterOptions {
    /// Whether a model may ask for several tools in one answer.
    public enum ParallelToolCalls: Sendable, Hashable {
        /// The host's own default, with no `parallel_tool_calls` in the request.
        case automatic

        /// The model may ask for several tools in one answer.
        case allowed

        /// The model asks for at most one tool per answer.
        case disallowed

    }
}

extension OpenRouterOptions {
    /// How OpenRouter's Auto Router picks the model that answers a request to `openrouter/auto` or
    /// `openrouter/auto-beta`.
    ///
    /// The router sorts each prompt into a kind of task, and picks from the models people spend the most on for that
    /// kind of task. The two routers read the same settings, each under its own plugin id, so a request sends them
    /// under the id of the router it goes to, and a request to any other model leaves them out. Every setting left
    /// `nil` keeps the router's default, or the one saved for the account.
    public struct AutoRouter: Sendable, Hashable {
        /// A band of the models people use for a kind of task, by their cost.
        ///
        /// Each tier holds a fifth of the models, from `low`, the cheapest, to `max`, the most capable at any price. A
        /// tier isn't a ceiling: it leaves out models cheaper than its band as well as dearer ones.
        public struct CostTier: ProviderVocabulary {
            /// The cheapest capable models, near what the router picks when no tier is set.
            public static let low: Self = "low"

            /// The second band by cost.
            public static let medium: Self = "medium"

            /// The middle band by cost.
            public static let high: Self = "high"

            /// The fourth band by cost.
            public static let xhigh: Self = "xhigh"

            /// The most capable models, whatever their price.
            public static let max: Self = "max"

            /// The tier's name in OpenRouter's API.
            public let rawValue: String

            /// Creates a tier from its name in OpenRouter's API.
            ///
            /// - Parameter rawValue: The name, such as `"medium"`.
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        /// A model the router may pick or must skip: by id, such as `anthropic/claude-sonnet-4.6`, or by a pattern in
        /// which `*` stands for any text, such as `anthropic/*` or `openai/gpt-5*`.
        public struct ModelPattern: ProviderVocabulary {
            /// The id or pattern, as OpenRouter's API spells it.
            public let rawValue: String

            /// Creates a pattern from an id or a pattern.
            ///
            /// - Parameter rawValue: The id or pattern, such as `"anthropic/*"`.
            public init(rawValue: String) {
                self.rawValue = rawValue
            }

            /// The pattern that matches exactly one model.
            ///
            /// - Parameter model: The model, usually from the catalog, such as `.anthropicClaudeSonnet4_6`.
            /// - Returns: The pattern of the model's id.
            public static func model<Effort: ModelEffort>(_ model: OpenRouterModel<Effort>) -> Self {
                Self(rawValue: model.id.rawValue)
            }
        }

        /// The models the router may pick from, such as `.model(.anthropicClaudeSonnet4_6)` or `"openai/gpt-5*"`.
        public var allowedModels: [ModelPattern]?

        /// The models the router never picks, even when `allowedModels` matches them. A request whose lists leave no
        /// model fails.
        public var excludedModels: [ModelPattern]?

        /// The band of models by cost to pick from.
        public var costTier: CostTier?

        /// Creates Auto Router settings.
        ///
        /// - Parameters:
        ///   - allowedModels: The models the router may pick from, by id or pattern.
        ///   - excludedModels: The models the router never picks, by id or pattern.
        ///   - costTier: The band of models by cost to pick from.
        public init(allowedModels: [ModelPattern]? = nil, excludedModels: [ModelPattern]? = nil, costTier: CostTier? = nil) {
            self.allowedModels = allowedModels
            self.excludedModels = excludedModels
            self.costTier = costTier
        }
    }
}

extension OpenRouterOptions {
    /// The engine that reads PDF attachments for a request.
    ///
    /// Without one, OpenRouter passes a PDF to a model that reads PDFs itself, and has `mistral-ocr` read it for any
    /// other model. `mistral-ocr` reads scanned pages and images, and costs extra per page, from the account's
    /// OpenRouter credits, also with the account's own provider keys. `cloudflare-ai` turns the PDF into text for free.
    /// `native` passes the PDF to the model, billed as input tokens, and only models that read PDFs themselves take it.
    ///
    /// An engine other than `native` reads the PDF before the model sees it, also for a model that could read it
    /// itself, and the service it uses keeps what it's sent under its own policy.
    ///
    /// Engines are an open vocabulary: any engine OpenRouter lists is valid, with or without a static member.
    public struct PDFEngine: ProviderVocabulary {
        /// Free text extraction through Cloudflare Workers AI, as Markdown.
        public static let cloudflareAI: Self = "cloudflare-ai"

        /// Mistral's OCR, for scanned documents and pages with images, at a price per page.
        public static let mistralOCR: Self = "mistral-ocr"

        /// The model's own PDF reading, for models that list file input.
        public static let native: Self = "native"

        /// The engine's name in OpenRouter's API.
        public let rawValue: String

        /// Creates an engine from its name in OpenRouter's API.
        ///
        /// - Parameter rawValue: The name, such as `"cloudflare-ai"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

extension OpenRouterOptions {
    /// How OpenRouter's Pareto router picks the coding model that answers a request to `openrouter/pareto-code`.
    ///
    /// The router picks from the top coding models: by quality tier, the cheapest available model of the tier, or its
    /// fastest with the ``OpenRouterRouting/Variant/nitro`` variant; or by price, the best-scoring model at or below
    /// ``maximumPromptPrice``. A request to any other model leaves the settings out. Every setting left `nil` keeps the
    /// router's default.
    public struct ParetoRouter: Sendable, Hashable {
        /// The price the router compares against ``OpenRouterOptions/ParetoRouter/maximumPromptPrice``.
        public struct PriceSource: ProviderVocabulary {
            /// Each model's listed prompt price. The router's default.
            public static let prompt: Self = "prompt"

            /// Each model's prompt price weighted by its traffic, or its listed price when it has none.
            public static let weightedAverage: Self = "weighted_avg"

            /// The source's name in OpenRouter's API.
            public let rawValue: String

            /// Creates a source from its name in OpenRouter's API.
            ///
            /// - Parameter rawValue: The name, such as `"weighted_avg"`.
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        /// The lowest coding score, from 0 to 1, of the models to pick from.
        ///
        /// The score picks a tier: 0.66 and up is the top coding models, 0.33 and up strong recent flagships, and below
        /// that capable coders above the median. When `nil`, the router picks from the top tier. ``maximumPromptPrice``
        /// takes over when it's set.
        public var minimumCodingScore: Double?

        /// The most a picked model's prompt may cost, in US dollars per million tokens.
        ///
        /// The router then picks the best-scoring model at or below it, and a request that no model fits fails.
        public var maximumPromptPrice: Decimal?

        /// The price ``maximumPromptPrice`` is compared against.
        public var priceSource: PriceSource?

        /// Creates Pareto router settings.
        ///
        /// - Parameters:
        ///   - minimumCodingScore: The lowest coding score, from 0 to 1, of the models to pick from.
        ///   - maximumPromptPrice: The most a picked model's prompt may cost, in US dollars per million tokens.
        ///   - priceSource: The price `maximumPromptPrice` is compared against.
        public init(minimumCodingScore: Double? = nil, maximumPromptPrice: Decimal? = nil, priceSource: PriceSource? = nil) {
            self.minimumCodingScore = minimumCodingScore
            self.maximumPromptPrice = maximumPromptPrice
            self.priceSource = priceSource
        }
    }
}

extension OpenRouterOptions {
    /// How long and detailed a model's answers are, from `low` to `max`.
    ///
    /// Lower levels give shorter answers, and higher levels fuller ones. For Anthropic models, OpenRouter sends the
    /// level as the model's effort setting.
    public struct Verbosity: ProviderVocabulary {
        /// Short, concise answers.
        public static let low: Self = "low"

        /// Answers of the usual length, the model's default.
        public static let medium: Self = "medium"

        /// Longer, more detailed answers.
        public static let high: Self = "high"

        /// More detail than `high`, for models that take it, such as Claude Opus 4.7 and later.
        public static let xhigh: Self = "xhigh"

        /// The most detail, for models that take it, such as Claude Opus 4.6 and later.
        public static let max: Self = "max"

        /// The level's name in OpenRouter's API.
        public let rawValue: String

        /// Creates a level from its name in OpenRouter's API.
        ///
        /// - Parameter rawValue: The name, such as `"low"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}
