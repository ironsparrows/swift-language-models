import CoreGraphics
import Foundation
import ImageIO
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

@Suite("Encoded image", .timeLimit(.minutes(1)))
struct EncodedImageTests {
    /// Where the red half of a 40 × 20 image ends up once it's turned upright.
    enum RedSide: Sendable {
        case left, right, top, bottom
    }

    @Test func `an image becomes a JPEG of the same size`() throws {
        let image = try #require(TestImage.halves(width: 40, height: 20))

        let encoded = try #require(EncodedImage(image, orientation: .up, maximumSide: 2_048))

        #expect(
            CGImageSourceCreateWithData(encoded.data as CFData, nil).flatMap(CGImageSourceGetType) == UTType.jpeg.identifier as CFString)
        let decoded = try #require(DecodedImage(encoded.data))
        #expect((decoded.width, decoded.height) == (40, 20))
        #expect((encoded.width, encoded.height) == (40, 20))
        #expect(decoded.isRed(x: 5, y: 10))
        #expect(decoded.isBlue(x: 35, y: 10))
    }

    @Test(arguments: [
        (CGImagePropertyOrientation.up, RedSide.left), (.upMirrored, .right), (.down, .right), (.downMirrored, .left),
        (.right, .top), (.left, .bottom), (.leftMirrored, .top), (.rightMirrored, .bottom),
    ])
    func `the pixels are turned upright by their orientation`(orientation: CGImagePropertyOrientation, red: RedSide) throws {
        let image = try #require(TestImage.halves(width: 40, height: 20))

        let decoded = try encoded(image, orientation: orientation, maximumSide: 2_048)

        let isTurned = [.top, .bottom].contains(red)
        #expect((decoded.width, decoded.height) == (isTurned ? (20, 40) : (40, 20)))
        let (redPoint, bluePoint) =
            switch red {
            case .left: ((5, 10), (35, 10))
            case .right: ((35, 10), (5, 10))
            case .top: ((10, 5), (10, 35))
            case .bottom: ((10, 35), (10, 5))
            }
        #expect(decoded.isRed(x: redPoint.0, y: redPoint.1))
        #expect(decoded.isBlue(x: bluePoint.0, y: bluePoint.1))
    }

    @Test func `an image over the limit is scaled down to it on its longer side, keeping its shape`() throws {
        let image = try #require(TestImage.halves(width: 3_000, height: 1_000))

        let encoded = try #require(EncodedImage(image, orientation: .up, maximumSide: 2_048))

        let decoded = try #require(DecodedImage(encoded.data))
        #expect((decoded.width, decoded.height) == (2_048, 683))
    }

    @Test func `a turned image is scaled by its upright longer side`() throws {
        let image = try #require(TestImage.halves(width: 1_000, height: 3_000))

        let decoded = try encoded(image, orientation: .right, maximumSide: 600)

        #expect((decoded.width, decoded.height) == (600, 200))
    }

    @Test(arguments: [
        (40, 20, CGImagePropertyOrientation.up, 2_048, 40, 20),
        (40, 20, .left, 2_048, 20, 40),
        (40, 20, .downMirrored, 2_048, 40, 20),
        (3_000, 1_000, .up, 2_048, 2_048, 683),
        (1_000, 3_000, .right, 600, 600, 200),
        (1_200, 4_096, .up, 2_048, 600, 2_048),
        (2_048, 2_048, .up, 2_048, 2_048, 2_048),
        (2_000, 1, .up, 100, 100, 1),
    ])
    func `the upright size turns the sides and scales the longer one down to the limit`(
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation,
        maximumSide: Int,
        uprightWidth: Int,
        uprightHeight: Int
    ) {
        let size = EncodedImage.uprightSize(width: width, height: height, orientation: orientation, maximumSide: maximumSide)

        #expect((size.width, size.height) == (uprightWidth, uprightHeight))
    }

    @Test func `the same image gives the same bytes every time`() throws {
        let image = try #require(TestImage.seven(size: 256))

        let first = try #require(EncodedImage(image, orientation: .right, maximumSide: 128))
        let second = try #require(EncodedImage(image, orientation: .right, maximumSide: 128))

        #expect(first.data == second.data)
    }

    @Test func `transparent areas turn white`() throws {
        let image = try #require(transparentImage())

        let decoded = try encoded(image, orientation: .up, maximumSide: 64)

        let color = decoded.color(x: 4, y: 4)
        #expect(color.red > 240 && color.green > 240 && color.blue > 240)
    }

    @Test(arguments: [UTType.png, .jpeg, .heic, .tiff])
    func `an image file is read, turned upright by the orientation it records, and encoded`(type: UTType) throws {
        let image = try #require(TestImage.halves(width: 40, height: 20))
        let file = try #require(TestImage.file(of: image, as: type, orientation: .right))

        let encoded = try #require(EncodedImage(data: file, maximumSide: 2_048))

        let decoded = try #require(DecodedImage(encoded.data))
        #expect((decoded.width, decoded.height) == (20, 40))
        #expect(decoded.isRed(x: 10, y: 5))
        #expect(EncodedImage.readableTypes.contains(type))
    }

    @Test func `a large image file is read at the smaller size`() throws {
        let image = try #require(TestImage.halves(width: 4_000, height: 2_000))
        let file = try #require(TestImage.file(of: image, as: .png))

        let encoded = try #require(EncodedImage(data: file, maximumSide: 1_000))

        #expect((encoded.width, encoded.height) == (1_000, 500))
    }

    @Test func `data that isn't an image, and an empty limit, give nothing`() throws {
        #expect(EncodedImage(data: Data("not an image".utf8), maximumSide: 2_048) == nil)
        #expect(EncodedImage(try #require(TestImage.halves(width: 4, height: 4)), orientation: .up, maximumSide: 0) == nil)
    }

    @Test(arguments: [(2_048, 0.85, 2_048, 0.85), (0, -1, 1, 0), (-5, 2, 1, 1), (512, .nan, 512, 0.85)])
    func `image settings outside their range count as the nearest valid value`(
        side: Int, quality: Double, encodedSide: Int, encodedQuality: Double
    ) {
        let encoding = ImageEncoding(maximumSide: side, quality: quality)

        #expect(encoding.encodedMaximumSide == encodedSide)
        #expect(encoding.encodedQuality == encodedQuality)
    }

    /// An image encoded, then decoded again.
    private func encoded(_ image: CGImage, orientation: CGImagePropertyOrientation, maximumSide: Int) throws -> DecodedImage {
        let encoded = try #require(EncodedImage(image, orientation: orientation, maximumSide: maximumSide))
        return try #require(DecodedImage(encoded.data))
    }

    /// A small image with no opaque pixels.
    private func transparentImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let context = unsafe CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }
}
