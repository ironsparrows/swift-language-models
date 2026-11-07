package import CoreGraphics
package import Foundation
package import ImageIO
package import LanguageModelsCore
package import UniformTypeIdentifiers

/// An image as JPEG bytes for a request: upright, on white, and no larger than a provider's limit.
///
/// The pixels are drawn upright, so the JPEG needs no orientation tag, and on white, so transparent areas don't turn
/// black. An image whose longer side is over the limit is scaled down to it, never up. Only the pixels reach the bytes,
/// never the source's metadata, such as where a photo was taken. The same image gives the same bytes every time, so a
/// provider's prompt cache stays valid when a later request sends it again.
package struct EncodedImage: Sendable, Equatable {
    /// The image kinds ImageIO reads, which ``init(data:maximumSide:quality:)`` takes.
    package static let readableTypes: Set<UTType> = Set(
        ((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []).compactMap { UTType($0) }.filter { $0.conforms(to: .image) }
    )

    /// The JPEG bytes.
    package let data: Data

    /// The width of the encoded image, in pixels.
    package let width: Int

    /// The height of the encoded image, in pixels.
    package let height: Int

    /// Encodes decoded pixels, such as a Foundation Models image attachment's, or fails when the image is empty or
    /// ImageIO can't encode it.
    ///
    /// - Parameters:
    ///   - image: The pixels as stored.
    ///   - orientation: How the stored pixels turn upright.
    ///   - maximumSide: The longest side, in pixels, of the encoded image.
    ///   - quality: The JPEG quality, from 0 to 1.
    package init?(
        _ image: CGImage, orientation: CGImagePropertyOrientation, maximumSide: Int, quality: Double = ImageEncoding.standard.quality
    ) {
        guard image.width > 0, image.height > 0, maximumSide > 0 else { return nil }
        let upright = orientation.upright(width: image.width, height: image.height)
        let (width, height) = Self.uprightSize(width: image.width, height: image.height, orientation: orientation, maximumSide: maximumSide)
        // Without a buffer of its own, the context allocates and owns its memory, so no pointer is ever used.
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = unsafe CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: Double(width) / Double(upright.width), y: Double(height) / Double(upright.height))
        context.concatenate(orientation.transform(width: Double(image.width), height: Double(image.height)))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let output = NSMutableData()
        guard
            let pixels = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, pixels, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        self.data = output as Data
        self.width = width
        self.height = height
    }

    /// Decodes an image file's bytes, such as a PNG, HEIC or JPEG, turns them upright by the orientation the file
    /// records, and encodes them, or fails when ImageIO can't read the data or encode the image.
    ///
    /// - Parameters:
    ///   - data: The file's bytes, in a kind of ``readableTypes``.
    ///   - maximumSide: The longest side, in pixels, of the encoded image.
    ///   - quality: The JPEG quality, from 0 to 1.
    package init?(data: Data, maximumSide: Int, quality: Double = ImageEncoding.standard.quality) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        self.init(source, orientation: nil, maximumSide: maximumSide, quality: quality)
    }

    /// Decodes an image file, turns it upright by the given orientation, and encodes it, or fails when ImageIO can't
    /// read the file or encode the image.
    ///
    /// - Parameters:
    ///   - url: The file, in a kind of ``readableTypes``.
    ///   - orientation: How the stored pixels turn upright, which wins over the orientation the file records.
    ///   - maximumSide: The longest side, in pixels, of the encoded image.
    ///   - quality: The JPEG quality, from 0 to 1.
    package init?(
        contentsOf url: URL, orientation: CGImagePropertyOrientation, maximumSide: Int, quality: Double = ImageEncoding.standard.quality
    ) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        self.init(source, orientation: orientation, maximumSide: maximumSide, quality: quality)
    }

    /// Decodes an image straight at no more than the limit, so a large photo never fills memory at full size, then
    /// turns it upright and encodes it.
    ///
    /// - Parameters:
    ///   - source: The image file.
    ///   - orientation: How the stored pixels turn upright, or `nil` for the orientation the file records.
    ///   - maximumSide: The longest side, in pixels, of the encoded image.
    ///   - quality: The JPEG quality, from 0 to 1.
    private init?(_ source: CGImageSource, orientation: CGImagePropertyOrientation?, maximumSide: Int, quality: Double) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: orientation == nil,
            kCGImageSourceThumbnailMaxPixelSize: maximumSide,
        ]
        guard maximumSide > 0, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        self.init(image, orientation: orientation ?? .up, maximumSide: maximumSide, quality: quality)
    }

    /// The size of the encoded image: the stored size turned upright, then scaled down, keeping its shape, until its
    /// longer side is no more than the limit. Each side is at least one pixel.
    ///
    /// - Parameters:
    ///   - width: The width of the stored pixels, above zero.
    ///   - height: The height of the stored pixels, above zero.
    ///   - orientation: How the stored pixels turn upright.
    ///   - maximumSide: The longest side, in pixels, of the encoded image, above zero.
    /// - Returns: The upright width and height, in pixels.
    package static func uprightSize(
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation,
        maximumSide: Int
    ) -> (width: Int, height: Int) {
        let upright = orientation.upright(width: width, height: height)
        let scale = min(1, Double(maximumSide) / Double(max(upright.width, upright.height)))
        return (max(1, Int((Double(upright.width) * scale).rounded())), max(1, Int((Double(upright.height) * scale).rounded())))
    }
}

extension CGImagePropertyOrientation {
    /// The size of stored pixels once they're turned upright, which swaps their width and height for a quarter turn.
    fileprivate func upright(width: Int, height: Int) -> (width: Int, height: Int) {
        switch self {
        case .leftMirrored, .right, .rightMirrored, .left: (height, width)
        default: (width, height)
        }
    }

    /// The transform that draws pixels of the given size upright, in Core Graphics' coordinates, where y grows upward.
    fileprivate func transform(width: Double, height: Double) -> CGAffineTransform {
        switch self {
        case .upMirrored: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
        case .down: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case .downMirrored: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        case .leftMirrored: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width)
        case .right: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        case .rightMirrored: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .left: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        default: .identity
        }
    }
}

extension ImageEncoding {
    /// The longest side the encoder uses, at least 1.
    package var encodedMaximumSide: Int {
        max(maximumSide, 1)
    }

    /// The JPEG quality the encoder uses, from 0 to 1.
    package var encodedQuality: Double {
        quality.isNaN ? Self.standard.quality : min(max(quality, 0), 1)
    }
}
