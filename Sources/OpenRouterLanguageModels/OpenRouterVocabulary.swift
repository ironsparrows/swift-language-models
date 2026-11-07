public import LanguageModels
public import UniformTypeIdentifiers

/// A kind of input an OpenRouter model accepts, such as `text` or `image`.
///
/// Input kinds are an open vocabulary: any kind OpenRouter lists is valid, with or without a static member.
public struct OpenRouterInputModality: ProviderVocabulary {
    /// The kind's name in OpenRouter's API.
    public let rawValue: String

    /// Creates an input kind from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"image"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The kinds of prompt attachment that carry this input, or none for a kind with no attachment form.
    ///
    /// Text is plain text, sent as text. An image is any kind ImageIO reads, such as PNG, JPEG or HEIC, sent as JPEG. A
    /// file is a PDF document. Audio is WAV, MP3, AIFF, AAC, FLAC, Ogg or MPEG-4 audio, and video is MPEG-4, MPEG,
    /// QuickTime or WebM movies. A kind that conforms to one of these, such as UTF-8 text to plain text, is carried
    /// too.
    public var contentTypes: Set<UTType> {
        Self.attachmentTypes.first { $0.key == self }?.value ?? []
    }

    /// The input kind whose attachments carry data of a kind, or `nil` when none does.
    ///
    /// - Parameter type: The kind of data, such as `UTType.mp3`.
    init?(carrying type: UTType) {
        guard let carrier = Self.attachmentTypes.first(where: { $0.value.contains { type.conforms(to: $0) } }) else { return nil }
        self = carrier.key
    }

    /// The kinds of data that carry each input kind with an attachment form, in the order a kind of data is matched
    /// against them.
    private static let attachmentTypes: KeyValuePairs<Self, Set<UTType>> = [
        .text: [.plainText],
        .image: AttachmentKind.readableImageTypes,
        .file: [.pdf],
        .audio: Set(audioTypes),
        .video: Set(videoTypes),
    ]

    /// The kinds of audio OpenRouter takes, in the order a kind of data is matched against them.
    static let audioTypes =
        [UTType.wav, .mp3, .aiff, .mpeg4Audio] + [UnnamedType.aacAudio, UnnamedType.flacAudio, UnnamedType.oggAudio].compactMap(\.self)

    /// The kinds of movie OpenRouter takes, in the order a kind of data is matched against them.
    static let videoTypes = [UTType.mpeg4Movie, .mpeg, .quickTimeMovie] + [UnnamedType.webMMovie].compactMap(\.self)
}

extension OpenRouterInputModality {
    /// Kinds of data OpenRouter takes that the system knows by identifier but has no member for.
    enum UnnamedType {
        static let aacAudio = UTType("public.aac-audio")
        static let flacAudio = UTType("org.xiph.flac")
        static let oggAudio = UTType("org.xiph.ogg-audio")
        static let webMMovie = UTType("org.webmproject.webm")
    }
}

/// A kind of output an OpenRouter model generates, such as `text` or `image`.
///
/// Output kinds are an open vocabulary: any kind OpenRouter lists is valid, with or without a static member.
public struct OpenRouterOutputModality: ProviderVocabulary {
    /// The kind's name in OpenRouter's API.
    public let rawValue: String

    /// Creates an output kind from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"image"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The kind of data entry an answer carries for this output besides its text, or `nil` for text itself and for
    /// kinds that don't become data entries.
    ///
    /// Only images do. Audio needs a voice and a format that no Foundation Models option chooses, and the other kinds,
    /// such as embeddings, come from other OpenRouter APIs.
    public var contentType: UTType? {
        self == .image ? .image : nil
    }
}

/// A request parameter that an OpenRouter model accepts, such as `tools` or `temperature`.
///
/// Parameters are an open vocabulary: any name OpenRouter lists is a valid parameter, with or without a static member.
public struct OpenRouterParameter: ProviderVocabulary {
    /// The parameter's name in OpenRouter's API.
    public let rawValue: String

    /// Creates a parameter from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"top_p"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A plugin that OpenRouter runs on a request or its answer, by its id in the request's `plugins` and in the router's
/// report.
///
/// The package sends the plugins it needs from the model's settings, such as a router's settings or the engine that
/// reads PDFs, and ``OpenRouterResponseMetadata/PipelineStage/plugin`` names a plugin that ran. Plugins are an open
/// vocabulary: any plugin OpenRouter reports is valid, with or without a static member.
public struct OpenRouterPlugin: ProviderVocabulary {
    /// The Auto Router's settings, which ``OpenRouterOptions/autoRouter`` holds.
    public static let autoRouter: Self = "auto-router"

    /// The beta Auto Router's settings, which ``OpenRouterOptions/autoRouter`` also holds.
    public static let autoBetaRouter: Self = "auto-beta-router"

    /// Context compression, which drops the middle of a transcript that doesn't fit. Requests turn it off.
    public static let contextCompression: Self = "context-compression"

    /// The engine that reads PDF attachments, which ``OpenRouterOptions/pdfEngine`` picks.
    public static let fileParser: Self = "file-parser"

    /// The Pareto Code router's settings, which ``OpenRouterOptions/paretoRouter`` holds.
    public static let paretoRouter: Self = "pareto-router"

    /// The plugin's id in OpenRouter's API.
    public let rawValue: String

    /// Creates a plugin from its id in OpenRouter's API.
    ///
    /// - Parameter rawValue: The id, such as `"file-parser"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A host that serves models on OpenRouter, by name or slug, such as `Anthropic` or `amazon-bedrock`.
///
/// OpenRouter calls the companies that serve its models providers, such as a model's maker, Amazon Bedrock or
/// Together, and routes each request to one of them. This type, ``OpenRouterRouting``'s settings,
/// ``OpenRouterError/providerName`` and ``LanguageModelMetadataKey/provider`` keep OpenRouter's word, and their
/// documentation calls them hosts. Elsewhere in this package, as in `ProviderVocabulary`, a provider is the API a
/// request goes to, which here is OpenRouter itself.
public struct OpenRouterProviderName: ProviderVocabulary {
    /// The host's name or slug.
    public let rawValue: String

    /// Creates a host name.
    ///
    /// - Parameter rawValue: The name or slug, such as `"Anthropic"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The precision of a host's model weights, such as `fp8`.
public struct OpenRouterQuantization: ProviderVocabulary {
    /// 4-bit integers.
    public static let int4: Self = "int4"

    /// 8-bit integers.
    public static let int8: Self = "int8"

    /// 4-bit floating point.
    public static let fp4: Self = "fp4"

    /// 4-bit microscaling floating point.
    public static let mxfp4: Self = "mxfp4"

    /// NVIDIA's 4-bit floating point.
    public static let nvfp4: Self = "nvfp4"

    /// 6-bit floating point.
    public static let fp6: Self = "fp6"

    /// 8-bit floating point.
    public static let fp8: Self = "fp8"

    /// 8-bit microscaling floating point.
    public static let mxfp8: Self = "mxfp8"

    /// 16-bit floating point.
    public static let fp16: Self = "fp16"

    /// 16-bit brain floating point.
    public static let bf16: Self = "bf16"

    /// 32-bit floating point.
    public static let fp32: Self = "fp32"

    /// A precision the host doesn't report.
    public static let unknown: Self = "unknown"

    /// The precision's name in OpenRouter's API.
    public let rawValue: String

    /// Creates a precision from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"fp8"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How much of each page a web search returns to the model, from `low` to `high`.
///
/// Exa caps each result at a size the level picks, Parallel caps all results together, and Perplexity passes the level
/// on. Firecrawl and the hosts' own search ignore it. More context gives the model more to cite, and costs more prompt
/// tokens.
///
/// Sizes are an open vocabulary: any size OpenRouter lists is valid, with or without a static member.
public struct OpenRouterSearchContextSize: ProviderVocabulary {
    /// The size's name in OpenRouter's API.
    public let rawValue: String

    /// Creates a size from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"medium"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A processing tier, which trades speed against price.
public struct OpenRouterServiceTier: ProviderVocabulary {
    /// The host's choice.
    public static let auto: Self = "auto"

    /// The standard tier.
    public static let `default`: Self = "default"

    /// Slower and cheaper processing.
    public static let flex: Self = "flex"

    /// Faster processing at a higher price. OpenRouter also accepts `fast` for it.
    public static let priority: Self = "priority"

    /// Reserved capacity, for accounts that bought it.
    public static let scale: Self = "scale"

    /// The fastest hosts, then `priority`, then the standard tier.
    public static let ultrafast: Self = "ultrafast"

    /// The tier's name in OpenRouter's API.
    public let rawValue: String

    /// Creates a tier from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"flex"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The engine that fetches pages for the ``OpenRouterServerTool`` web fetch.
///
/// `auto`, OpenRouter's default, fetches with the host's own fetch when the model's host has one, and with Exa
/// otherwise. `native` asks for the host's own fetch, falling back to `openrouter`, OpenRouter's own fetcher, which is
/// free. The other engines are services that OpenRouter calls for the model.
///
/// Each fetch with Exa, Parallel or Firecrawl costs extra, on top of the model's tokens, from the account's OpenRouter
/// credits, and a host's own fetch costs the host's price. Each engine keeps what it's sent under its own data
/// retention policy. With zero data retention enforced on the account, OpenRouter rejects Firecrawl; Exa, Parallel and
/// the hosts' own fetch still apply their own policies.
///
/// Engines are an open vocabulary: any engine OpenRouter lists is valid, with or without a static member.
public struct OpenRouterWebFetchEngine: ProviderVocabulary {
    /// The engine's name in OpenRouter's API.
    public let rawValue: String

    /// Creates an engine from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"exa"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The engine that runs the searches of the ``OpenRouterServerTool`` web search.
///
/// `auto`, OpenRouter's default, searches with the host's own search when the model's host has one, and with Exa
/// otherwise. `native` asks for the host's own search, also falling back to Exa. The other engines are search services
/// that OpenRouter calls for the model.
///
/// Each search costs extra, on top of the model's tokens: Exa, Parallel and Perplexity charge per search, Firecrawl per
/// search and per result, all from the account's OpenRouter credits, and a host's own search at the host's price.
/// Each engine keeps what it's sent under its own data retention policy. With zero data retention enforced on the
/// account, OpenRouter rejects Firecrawl; Exa, Parallel, Perplexity and the hosts' own search still apply their own
/// policies.
///
/// Engines are an open vocabulary: any engine OpenRouter lists is valid, with or without a static member.
public struct OpenRouterWebSearchEngine: ProviderVocabulary {
    /// The engine's name in OpenRouter's API.
    public let rawValue: String

    /// Creates an engine from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"exa"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How deep a web search engine searches, trading speed against thoroughness and price.
///
/// Each engine takes its own modes and ignores the others: Exa takes `instant`, `fast`, `auto`, its default,
/// `deep-lite`, `deep` and `deep-reasoning`, and Parallel takes `turbo`, `fast`, `basic`, its default, and `advanced`.
/// Deeper modes take longer and cost more per search.
///
/// Modes are an open vocabulary: any mode OpenRouter lists is valid, with or without a static member.
public struct OpenRouterWebSearchMode: ProviderVocabulary {
    /// The mode's name in OpenRouter's API.
    public let rawValue: String

    /// Creates a mode from its name in OpenRouter's API.
    ///
    /// - Parameter rawValue: The name, such as `"fast"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
