public import Foundation
import LanguageModels

// MARK: - Server tool

/// A tool that OpenAI runs for the model while it answers, such as a web search or an image generator.
///
/// Server tools are a setting of the model, in ``OpenAILanguageModel/serverTools``, rather than Foundation Models
/// tools: the app implements nothing, and their calls never reach the session as tool calls. The model decides when to
/// call one, and OpenAI runs it and hands the result back to the model, which may call it again before it answers. A
/// request lists them after the session's own tools, in the order given.
///
/// ```swift
/// let model = OpenAILanguageModel(
///     .gpt6Luna,
///     serverTools: [.webSearch(allowedDomains: ["swift.org"]), .imageGeneration(quality: .low)],
///     auth: .apiKey { try await keyStore.openAIKey() }
/// )
/// ```
///
/// The entry that ends the answer records each call, which ``OpenAIResponseMetadata/serverToolCalls`` reads, and each call
/// goes back on later turns while the model still has its tool. Each tool costs extra, on top of the model's tokens:
/// a search by the call, an image by its size and quality, and a file search by the call and the storage it searches.
///
/// Two tools are equal when a request sends the same entry for them.
public struct OpenAIServerTool: Sendable, Hashable {
    /// The tool's entry in a request's `tools`, and what the request asks for with it.
    let entry: Entry

    private init(_ entry: Entry) {
        self.entry = entry
    }

    /// Searches the web, so the model can answer with current information and cite the pages it used.
    ///
    /// The answer's response entry lists the cited pages, which ``OpenAIResponseMetadata/citations`` reads. Show them
    /// to the person as links beside the answer.
    ///
    /// - Parameters:
    ///   - searchContextSize: How much of each page the model gets, or `nil` for OpenAI's default, `medium`. More
    ///     context costs more prompt tokens.
    ///   - allowedDomains: The only domains to search, such as `"swift.org"`, which include their subdomains, or `nil`
    ///     to search any.
    ///   - userLocation: Roughly where the person is, so results suit it, or `nil` for none, which OpenAI takes as the
    ///     United States. A location with no fields avoids that.
    ///   - webAccess: Whether the search reads pages live or only from OpenAI's cache.
    ///   - listsSources: Whether the answer lists every page the searches consulted, which
    ///     ``OpenAIResponseMetadata/sources`` reads, beyond the pages it cites.
    /// - Returns: The web search.
    public static func webSearch(
        searchContextSize: OpenAISearchContextSize? = nil,
        allowedDomains: [String]? = nil,
        userLocation: Location? = nil,
        webAccess: WebAccess = .automatic,
        listsSources: Bool = false
    ) -> Self {
        Self(
            .webSearch(
                WebSearch(
                    filters: allowedDomains.map(WebSearch.Filters.init), searchContextSize: searchContextSize,
                    userLocation: userLocation, externalWebAccess: webAccess.value),
                listsSources: listsSources))
    }

    /// Generates images, which the answer sends as data entries of their own, from OS 27.2.
    ///
    /// Each image is a `Transcript.DataEntry` of its format's kind, such as PNG, in the transcript beside the answer's
    /// text, and the model sees it on later turns while OpenAI keeps responses, so it can edit it. A request that sends
    /// the tool throws `LanguageModelError.unsupportedCapability` before OS 27.2, or in an app built without Xcode
    /// 27.2's SDK, where no image could arrive.
    ///
    /// Without a `complexity`, OpenAI plans each image with the request's reasoning effort. GPT Image 2 refuses a
    /// complexity of `low` or `medium`, and GPT Image 1 mini of `low`, which a light reasoning level passes on, so with
    /// them a request at a light reasoning level fails; leave the reasoning level at the model's default.
    ///
    /// - Parameters:
    ///   - model: The model that draws the images, such as ``OpenAIImageModel/gptImage1Mini``, or `nil` for OpenAI's
    ///     default, GPT Image 2.
    ///   - quality: How detailed the images are, which sets their price, or `nil` for OpenAI's default, `auto`.
    ///   - complexity: How much the model plans each image, apart from its quality, or `nil` to plan with the request's
    ///     reasoning effort, or with the image model's default when the effort isn't one it takes.
    ///   - size: The images' size, or `nil` for OpenAI's default.
    ///   - format: The images' file format, or `nil` for OpenAI's default, PNG.
    ///   - compression: How much a JPEG or WebP image is compressed, from 0 to 100, or `nil` for OpenAI's default,
    ///     100.
    ///   - background: Whether the images' background is transparent, or `nil` for OpenAI's default, `auto`.
    ///   - moderation: How strictly OpenAI checks what the images show, or `nil` for OpenAI's default, `auto`.
    /// - Returns: The image generation.
    public static func imageGeneration(
        model: OpenAIImageModel? = nil,
        quality: OpenAIImageQuality? = nil,
        complexity: OpenAIImageComplexity? = nil,
        size: OpenAIImageSize? = nil,
        format: OpenAIImageFormat? = nil,
        compression: Int? = nil,
        background: OpenAIImageBackground? = nil,
        moderation: OpenAIImageModeration? = nil
    ) -> Self {
        Self(
            .imageGeneration(
                ImageGeneration(
                    model: model, quality: quality, complexity: complexity, size: size, outputFormat: format,
                    outputCompression: compression, background: background, moderation: moderation)))
    }

    /// Searches files the app added to OpenAI's vector stores, so the model can answer from them and cite them.
    ///
    /// The app makes the vector stores beforehand, with OpenAI's API: it uploads the files and adds them to a store,
    /// which indexes them. The answer's response entry lists the files it cites, which
    /// ``OpenAIResponseMetadata/fileCitations`` reads.
    ///
    /// - Parameters:
    ///   - vectorStoreIDs: The ids of the vector stores to search, such as `"vs_…"`.
    ///   - maximumResults: The most results of one search, from 1 to 50, or `nil` for OpenAI's default.
    /// - Returns: The file search.
    public static func fileSearch(vectorStoreIDs: [String], maximumResults: Int? = nil) -> Self {
        Self(.fileSearch(FileSearch(vectorStoreIDs: vectorStoreIDs, maximumResults: maximumResults)))
    }
}

extension OpenAIServerTool {
    /// Roughly where the person is, so a web search's results suit it.
    public struct Location: Sendable, Hashable {
        /// The city, such as `"San Francisco"`.
        public var city: String?

        /// The region, such as `"California"`.
        public var region: String?

        /// The country, as its two-letter ISO code, such as `"US"`.
        public var country: String?

        /// The time zone, sent as its IANA name, such as `America/Los_Angeles`.
        public var timeZone: TimeZone?

        /// Creates a location.
        ///
        /// - Parameters:
        ///   - city: The city.
        ///   - region: The region.
        ///   - country: The country, as its two-letter ISO code.
        ///   - timeZone: The time zone.
        public init(city: String? = nil, region: String? = nil, country: String? = nil, timeZone: TimeZone? = nil) {
            self.city = city
            self.region = region
            self.country = country
            self.timeZone = timeZone
        }
    }

    /// Whether a web search reads pages live or only from OpenAI's cache.
    public enum WebAccess: Sendable, Hashable {
        /// OpenAI's own default, which reads pages live, with no `external_web_access` in the request.
        case automatic

        /// The search reads pages live.
        case live

        /// The search reads only pages OpenAI cached and indexed, never live ones.
        case cachedOnly
    }
}

// MARK: - Wire

extension OpenAIServerTool {
    /// A server tool's entry in a request's `tools`, with what the request asks for with it.
    enum Entry: Encodable, Sendable, Hashable {
        case webSearch(WebSearch, listsSources: Bool)
        case imageGeneration(ImageGeneration)
        case fileSearch(FileSearch)

        /// The kind of call the tool adds to an answer, which the answer keeps.
        var call: Responses.ServerToolCall {
            switch self {
            case .webSearch: .webSearch
            case .imageGeneration: .imageGeneration
            case .fileSearch: .fileSearch
            }
        }

        /// What the request adds to `include` for the tool.
        var include: [Responses.Include] {
            switch self {
            case .webSearch(_, let listsSources): listsSources ? [Self.webSearchSources] : []
            case .imageGeneration, .fileSearch: []
            }
        }

        /// The format of the images the tool generates, or `nil` for a tool that generates none.
        var generatedFormat: OpenAIImageFormat? {
            switch self {
            case .imageGeneration(let generation): generation.outputFormat ?? .png
            case .webSearch, .fileSearch: nil
            }
        }

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .webSearch(let search, _): try search.encode(to: encoder)
            case .imageGeneration(let generation): try generation.encode(to: encoder)
            case .fileSearch(let search): try search.encode(to: encoder)
            }
        }

        /// What `include` asks for so that a web search's call lists every page it consulted.
        private static let webSearchSources: Responses.Include = "web_search_call.action.sources"
    }

    /// The `web_search` tool.
    struct WebSearch: Encodable, Sendable, Hashable {
        fileprivate struct Filters: Encodable, Sendable, Hashable {
            let allowedDomains: [String]

            private enum CodingKeys: String, CodingKey {
                case allowedDomains = "allowed_domains"
            }
        }

        fileprivate let filters: Filters?
        fileprivate let searchContextSize: OpenAISearchContextSize?
        fileprivate let userLocation: Location?
        fileprivate let externalWebAccess: Bool?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("web_search", forKey: .type)
            try container.encodeIfPresent(filters, forKey: .filters)
            try container.encodeIfPresent(searchContextSize, forKey: .searchContextSize)
            try container.encodeIfPresent(userLocation.map(UserLocation.init), forKey: .userLocation)
            try container.encodeIfPresent(externalWebAccess, forKey: .externalWebAccess)
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case filters
            case searchContextSize = "search_context_size"
            case userLocation = "user_location"
            case externalWebAccess = "external_web_access"
        }
    }

    /// A location as a web search's `user_location` names it.
    private struct UserLocation: Encodable {
        let type = "approximate"
        let city: String?
        let region: String?
        let country: String?
        let timezone: String?

        init(_ location: Location) {
            city = location.city
            region = location.region
            country = location.country
            timezone = location.timeZone?.identifier
        }
    }

    /// The `image_generation` tool.
    struct ImageGeneration: Encodable, Sendable, Hashable {
        fileprivate let model: OpenAIImageModel?
        fileprivate let quality: OpenAIImageQuality?
        fileprivate let complexity: OpenAIImageComplexity?
        fileprivate let size: OpenAIImageSize?
        fileprivate let outputFormat: OpenAIImageFormat?
        fileprivate let outputCompression: Int?
        fileprivate let background: OpenAIImageBackground?
        fileprivate let moderation: OpenAIImageModeration?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("image_generation", forKey: .type)
            try container.encodeIfPresent(model, forKey: .model)
            try container.encodeIfPresent(quality, forKey: .quality)
            try container.encodeIfPresent(complexity, forKey: .complexity)
            try container.encodeIfPresent(size, forKey: .size)
            try container.encodeIfPresent(outputFormat, forKey: .outputFormat)
            try container.encodeIfPresent(outputCompression, forKey: .outputCompression)
            try container.encodeIfPresent(background, forKey: .background)
            try container.encodeIfPresent(moderation, forKey: .moderation)
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case model
            case quality
            case complexity
            case size
            case outputFormat = "output_format"
            case outputCompression = "output_compression"
            case background
            case moderation
        }
    }

    /// The `file_search` tool.
    struct FileSearch: Encodable, Sendable, Hashable {
        fileprivate let vectorStoreIDs: [String]
        fileprivate let maximumResults: Int?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("file_search", forKey: .type)
            try container.encode(vectorStoreIDs, forKey: .vectorStoreIDs)
            try container.encodeIfPresent(maximumResults, forKey: .maximumResults)
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case vectorStoreIDs = "vector_store_ids"
            case maximumResults = "max_num_results"
        }
    }
}

extension OpenAIServerTool.WebAccess {
    /// The `external_web_access` value, or `nil` to leave the choice to OpenAI.
    fileprivate var value: Bool? {
        switch self {
        case .automatic: nil
        case .live: true
        case .cachedOnly: false
        }
    }
}
