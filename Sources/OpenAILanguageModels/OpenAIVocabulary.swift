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
        .image: EncodedImage.readableTypes,
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
/// The answer's metadata names the tier that served it, under `LanguageModelMetadataKey.serviceTier`, which can differ
/// from the one asked for.
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
