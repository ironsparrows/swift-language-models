/// How image attachments are encoded before they're sent: upright, on white, and as JPEG no larger than a size.
///
/// A provider's configuration that sends images holds one, such as `OpenAIConfiguration`'s `images`. A smaller
/// image costs fewer input tokens, and a larger one keeps small print legible:
///
/// ```swift
/// model.configuration.images = ImageEncoding(maximumSide: 1_024)
/// ```
///
/// An image at a web address goes as its address, so neither setting applies to it.
public struct ImageEncoding: Sendable, Hashable {
    /// The longest side, in pixels, of an image sent as data. A larger image is scaled down to it, keeping its shape,
    /// and a smaller one is never scaled up. A side under 1 counts as 1.
    public var maximumSide: Int

    /// The JPEG quality, from 0 for the smallest file to 1 for the best image. A value outside that range counts as
    /// the nearest end of it.
    public var quality: Double

    /// Creates encoding settings.
    ///
    /// - Parameters:
    ///   - maximumSide: The longest side, in pixels, of an image sent as data. The default, 2,048, is the largest image
    ///     that OpenAI's models see in full detail, and close to what other providers keep.
    ///   - quality: The JPEG quality, from 0 to 1. The default, 0.85, keeps small text legible at a fraction of PNG's
    ///     size.
    public init(maximumSide: Int = 2_048, quality: Double = 0.85) {
        self.maximumSide = maximumSide
        self.quality = quality
    }

    /// Images up to 2,048 pixels on their longest side, at a JPEG quality of 0.85.
    public static let standard = ImageEncoding()
}
