public import LanguageModels
public import UniformTypeIdentifiers

/// A kind of input an OpenAI model accepts, such as `text`, `image` or `pdf`.
///
/// Input kinds are an open vocabulary: any kind the catalog lists is valid, with or without a static member.
public struct OpenAIInputModality: ProviderVocabulary {
    /// The kind's name, as the catalog spells it.
    public let rawValue: String

    /// Creates an input kind from its name.
    ///
    /// - Parameter rawValue: The name, such as `"image"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The kinds of prompt attachment that carry this input, or none for a kind with no attachment form.
    ///
    /// Text is plain text, sent as text. An image is any kind ImageIO reads, such as PNG, JPEG or HEIC, sent as JPEG.
    /// A PDF is a PDF document. A kind that conforms to one of these, such as UTF-8 text to plain text, is carried too.
    public var contentTypes: Set<UTType> {
        Self.attachmentTypes.first { $0.key == self }?.value ?? []
    }

    /// The input kind whose attachments carry data of a kind, or `nil` when none does.
    ///
    /// - Parameter type: The kind of data, such as `UTType.pdf`.
    init?(carrying type: UTType) {
        guard let carrier = Self.attachmentTypes.first(where: { $0.value.contains { type.conforms(to: $0) } }) else { return nil }
        self = carrier.key
    }

    /// The kinds of data that carry each input kind with an attachment form, in the order a kind of data is matched
    /// against them.
    private static let attachmentTypes: KeyValuePairs<Self, Set<UTType>> = [
        .text: [.plainText],
        .image: AttachmentKind.readableImageTypes,
        .pdf: [.pdf],
    ]
}

/// A request setting that an OpenAI model accepts, such as `tools` or `temperature`.
///
/// Parameters are an open vocabulary: any name the catalog lists is a valid parameter, with or without a static member.
/// `structured_outputs` stands for answers held to a schema, and `reasoning` for a choice of reasoning effort.
public struct OpenAIParameter: ProviderVocabulary {
    /// The parameter's name, as the catalog spells it.
    public let rawValue: String

    /// Creates a parameter from its name.
    ///
    /// - Parameter rawValue: The name, such as `"top_p"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A processing tier, which trades speed against price.
///
/// ``OpenAIResponseMetadata/serviceTier`` names the tier that served an answer, which can differ from the one asked for.
public struct OpenAIServiceTier: ProviderVocabulary {
    /// The tier the project's settings choose, which is `default` unless the project set another.
    public static let auto: Self = "auto"

    /// The standard tier, at the standard price.
    public static let `default`: Self = "default"

    /// Slower and cheaper processing.
    public static let flex: Self = "flex"

    /// Faster processing at a higher price.
    public static let priority: Self = "priority"

    /// Reserved capacity, for projects that bought it.
    public static let scale: Self = "scale"

    /// Faster processing, which the answer reports as `priority`.
    public static let fast: Self = "fast"

    /// The fastest processing.
    public static let ultrafast: Self = "ultrafast"

    /// The tier's name in OpenAI's API.
    public let rawValue: String

    /// Creates a tier from its name in OpenAI's API.
    ///
    /// - Parameter rawValue: The name, such as `"flex"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How much of each page a web search gives the model, from `low` to `high`.
///
/// More context gives the model more to cite, and costs more prompt tokens. Sizes are an open vocabulary: any size OpenAI
/// lists is valid, with or without a static member.
public struct OpenAISearchContextSize: ProviderVocabulary {
    /// The least context.
    public static let low: Self = "low"

    /// More context, OpenAI's default.
    public static let medium: Self = "medium"

    /// The most context.
    public static let high: Self = "high"

    /// The size's name in OpenAI's API.
    public let rawValue: String

    /// Creates a size from its name in OpenAI's API.
    ///
    /// - Parameter rawValue: The name, such as `"medium"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A model that draws images for the image generation tool, such as `gpt-image-2`.
///
/// Image models are an open vocabulary: any model OpenAI lists for the tool is valid, with or without a static member.
public struct OpenAIImageModel: ProviderVocabulary {
    /// GPT Image 2, OpenAI's default for the tool.
    public static let gptImage2: Self = "gpt-image-2"

    /// GPT Image 1 mini.
    public static let gptImage1Mini: Self = "gpt-image-1-mini"

    /// The model's id in OpenAI's API.
    public let rawValue: String

    /// Creates a model from its id in OpenAI's API.
    ///
    /// - Parameter rawValue: The id, such as `"gpt-image-2"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How detailed a generated image is, which sets its price, from `low` to `high`.
///
/// Qualities are an open vocabulary: any quality OpenAI lists is valid, with or without a static member. Some models
/// take more, such as `xhigh` and `max`.
public struct OpenAIImageQuality: ProviderVocabulary {
    /// The least detailed images.
    public static let low: Self = "low"

    /// Images of medium detail.
    public static let medium: Self = "medium"

    /// The most detailed images.
    public static let high: Self = "high"

    /// The quality the model picks for the prompt, OpenAI's default.
    public static let auto: Self = "auto"

    /// The quality's name in OpenAI's API.
    public let rawValue: String

    /// Creates a quality from its name in OpenAI's API.
    ///
    /// - Parameter rawValue: The name, such as `"low"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How much an image model plans an image before it draws it, apart from the image's quality, from `low` to `high`.
///
/// Levels are an open vocabulary: any level OpenAI lists is valid, with or without a static member. GPT Image 2 refuses
/// `low` and `medium`, and GPT Image 1 mini `low`.
public struct OpenAIImageComplexity: ProviderVocabulary {
    /// The least planning.
    public static let low: Self = "low"

    /// More planning.
    public static let medium: Self = "medium"

    /// The most planning.
    public static let high: Self = "high"

    /// The level's name in OpenAI's API.
    public let rawValue: String

    /// Creates a level from its name in OpenAI's API.
    ///
    /// - Parameter rawValue: The name, such as `"medium"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The size of a generated image: one of the standard sizes, any width and height a model takes, or `auto`.
///
/// Sizes are an open vocabulary: any size OpenAI lists is valid, with or without a static member.
public struct OpenAIImageSize: ProviderVocabulary {
    /// A square image, 1024 by 1024 pixels.
    public static let square1024: Self = "1024x1024"

    /// A portrait image, 1024 pixels wide and 1536 high.
    public static let portrait1024x1536: Self = "1024x1536"

    /// A landscape image, 1536 pixels wide and 1024 high.
    public static let landscape1536x1024: Self = "1536x1024"

    /// The size the model picks for the prompt.
    public static let auto: Self = "auto"

    /// The size as OpenAI's API spells it, such as `"1536x864"`.
    public let rawValue: String

    /// Creates a size from its spelling in OpenAI's API.
    ///
    /// - Parameter rawValue: The size, such as `"1024x1024"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a size of any width and height, for a model that takes it, such as 1536 by 864 for GPT Image 2.
    ///
    /// - Parameters:
    ///   - width: The width in pixels. GPT Image 2 takes multiples of 16.
    ///   - height: The height in pixels. GPT Image 2 takes multiples of 16.
    public init(width: Int, height: Int) {
        self.init(rawValue: "\(width)x\(height)")
    }
}

/// The file format of a generated image, such as `png`, which is also the kind of its data entry.
///
/// Formats are an open vocabulary: any format OpenAI lists is valid, with or without a static member. Some models make
/// more, such as `gif` and `svg`.
public struct OpenAIImageFormat: ProviderVocabulary {
    /// PNG, OpenAI's default.
    public static let png: Self = "png"

    /// JPEG.
    public static let jpeg: Self = "jpeg"

    /// WebP.
    public static let webp: Self = "webp"

    /// The format's name in OpenAI's API.
    public let rawValue: String

    /// Creates a format from its name in OpenAI's API.
    ///
    /// - Parameter rawValue: The name, such as `"png"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The kind of an image in the format, which its data entry has.
    var contentType: UTType {
        Responses.ServerToolCall.imageType(ofFormat: rawValue)
    }
}

/// Whether a generated image's background is transparent.
///
/// Backgrounds are an open vocabulary: any value OpenAI lists is valid, with or without a static member.
public struct OpenAIImageBackground: ProviderVocabulary {
    /// A transparent background, which needs the PNG or WebP format.
    public static let transparent: Self = "transparent"

    /// An opaque background.
    public static let opaque: Self = "opaque"

    /// The background the model picks for the prompt, OpenAI's default.
    public static let auto: Self = "auto"

    /// The value's name in OpenAI's API.
    public let rawValue: String

    /// Creates a background from its name in OpenAI's API.
    ///
    /// - Parameter rawValue: The name, such as `"transparent"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// How strictly OpenAI checks what a generated image shows.
///
/// Levels are an open vocabulary: any level OpenAI lists is valid, with or without a static member.
public struct OpenAIImageModeration: ProviderVocabulary {
    /// OpenAI's standard checks, its default.
    public static let auto: Self = "auto"

    /// Less strict checks.
    public static let low: Self = "low"

    /// The level's name in OpenAI's API.
    public let rawValue: String

    /// Creates a level from its name in OpenAI's API.
    ///
    /// - Parameter rawValue: The name, such as `"low"`.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
