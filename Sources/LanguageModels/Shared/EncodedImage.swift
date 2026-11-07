import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import LanguageModelsCore
import Synchronization
import UniformTypeIdentifiers

// MARK: - Encoding

/// An image as JPEG bytes for a request: upright, on white, and no larger than the limit it's given.
///
/// The pixels are drawn upright, so the JPEG needs no orientation tag, and on white, so transparent areas don't turn
/// black. An image whose longer side is over the limit is scaled down to it, never up. Only the pixels reach the bytes,
/// never the source's metadata, such as where a photo was taken. The same image gives the same bytes every time, so a
/// host's prompt cache stays valid when a later request sends it again.
struct EncodedImage: Sendable, Equatable {
    /// The image kinds ImageIO reads, which ``init(data:maximumSide:quality:)`` takes.
    static let readableTypes: Set<UTType> = Set(
        ((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []).compactMap { UTType($0) }.filter { $0.conforms(to: .image) }
    )

    /// The JPEG bytes.
    let data: Data

    /// The width of the encoded image, in pixels.
    let width: Int

    /// The height of the encoded image, in pixels.
    let height: Int

    /// Encodes decoded pixels, such as a Foundation Models image attachment's, or fails when the image is empty or
    /// ImageIO can't encode it.
    ///
    /// - Parameters:
    ///   - image: The pixels as stored.
    ///   - orientation: How the stored pixels turn upright.
    ///   - maximumSide: The longest side, in pixels, of the encoded image.
    ///   - quality: The JPEG quality, from 0 to 1.
    init?(
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
    init?(data: Data, maximumSide: Int, quality: Double = ImageEncoding.standard.quality) {
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
    init?(
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
    static func uprightSize(
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
    var encodedMaximumSide: Int {
        max(maximumSide, 1)
    }

    /// The JPEG quality the encoder uses, from 0 to 1, or the standard quality for NaN.
    var encodedQuality: Double {
        quality.isNaN ? Self.standard.quality : min(max(quality, 0), 1)
    }
}

// MARK: - Cache

/// Images already encoded as JPEG, kept in memory so that a transcript's images, which every request sends again, are
/// decoded and encoded once rather than with every request.
///
/// An image is kept by what it holds, never by a name an app could give another image: data by its SHA-256 digest, a
/// file by its path, size, modification date and file number, so a file that changes is read again, and decoded pixels
/// by the image itself, which the cache keeps alive so no other image can take its place. Each is also kept by its
/// orientation, longest side and JPEG quality. Once the cache is over its limits, the images used least recently go
/// first. Images that can't be read or encoded aren't kept.
final class EncodedImageCache: Sendable {
    /// The cache that every request shares, which empties when the system runs low on memory, since the images it
    /// keeps can be encoded again.
    static let shared = EncodedImageCache(emptiesUnderMemoryPressure: true)

    /// What an encoded image is kept by.
    struct Key: Hashable, Sendable {
        private let source: Source

        /// The orientation the pixels are turned upright by, or `nil` for the one an image file's data records.
        private let orientation: CGImagePropertyOrientation?

        private let maximumSide: Int

        /// The JPEG quality, so images encoded at another quality are kept apart.
        private let quality: Double

        /// An image file's bytes, turned upright by the orientation they record.
        ///
        /// - Parameters:
        ///   - data: The file's bytes.
        ///   - maximumSide: The longest side, in pixels, of the encoded image.
        ///   - quality: The JPEG quality, from 0 to 1.
        init(data: Data, maximumSide: Int, quality: Double = ImageEncoding.standard.quality) {
            source = .data(SHA256.hash(data: data))
            orientation = nil
            self.maximumSide = maximumSide
            self.quality = quality
        }

        /// An image file as it is now, or `nil` when it can't be looked up, such as when it's missing.
        ///
        /// - Parameters:
        ///   - url: The file.
        ///   - orientation: How the stored pixels turn upright.
        ///   - maximumSide: The longest side, in pixels, of the encoded image.
        ///   - quality: The JPEG quality, from 0 to 1.
        init?(
            file url: URL, orientation: CGImagePropertyOrientation, maximumSide: Int, quality: Double = ImageEncoding.standard.quality
        ) {
            guard let version = FileVersion(path: url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)) else {
                return nil
            }
            source = .file(version)
            self.orientation = orientation
            self.maximumSide = maximumSide
            self.quality = quality
        }

        /// Decoded pixels, matched by the image itself rather than by what it shows.
        ///
        /// - Parameters:
        ///   - image: The pixels as stored.
        ///   - orientation: How the stored pixels turn upright.
        ///   - maximumSide: The longest side, in pixels, of the encoded image.
        ///   - quality: The JPEG quality, from 0 to 1.
        init(
            image: CGImage, orientation: CGImagePropertyOrientation, maximumSide: Int, quality: Double = ImageEncoding.standard.quality
        ) {
            source = .pixels(Identity(image: image))
            self.orientation = orientation
            self.maximumSide = maximumSide
            self.quality = quality
        }

        /// The bytes of the pixels the key keeps alive, counted toward the cache's limit, or the largest count when
        /// they overflow it.
        fileprivate var keptBytes: Int {
            guard case .pixels(let identity) = source else { return 0 }
            let (bytes, overflow) = identity.image.bytesPerRow.multipliedReportingOverflow(by: identity.image.height)
            return overflow ? .max : bytes
        }

        /// Whether the image is still what the key names: for a file, whether it's unchanged since the key was made.
        fileprivate var isCurrent: Bool {
            guard case .file(let version) = source else { return true }
            return FileVersion(path: version.path) == version
        }
    }

    /// Where an encoded image came from.
    private enum Source: Hashable, Sendable {
        case data(SHA256.Digest)
        case file(FileVersion)
        case pixels(Identity)
    }

    /// A file at one moment: changing its bytes changes its modification date, and often its size, and replacing it
    /// changes its file number.
    private struct FileVersion: Hashable, Sendable {
        let path: String
        let size: UInt64
        let modified: Date
        let device: UInt64
        let fileNumber: UInt64

        /// The file at a path as it is now, or `nil` when it can't be looked up.
        init?(path: String) {
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                let size = (attributes[.size] as? NSNumber)?.uint64Value,
                let modified = attributes[.modificationDate] as? Date,
                let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
                let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            else { return nil }
            self.path = path
            self.size = size
            self.modified = modified
            self.device = device
            self.fileNumber = fileNumber
        }
    }

    /// An image matched by identity, never by its pixels or address. The key holds the image, so while an entry keeps
    /// it alive, no other image can have its address.
    private struct Identity: Hashable, Sendable {
        let image: CGImage

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.image === rhs.image }

        func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(image)) }
    }

    private struct Entry {
        let data: Data

        /// The JPEG's bytes and those of the pixels the key keeps alive.
        let cost: Int

        /// When the entry was last used, as a count of uses.
        var lastUse: UInt64
    }

    private struct Storage {
        var entries: [Key: Entry] = [:]
        var cost = 0
        var uses: UInt64 = 0
    }

    /// The most bytes the cache keeps: those of the JPEGs and of the pixels it keeps alive.
    private let byteLimit: Int

    /// The most images the cache keeps.
    private let entryLimit: Int

    private let storage = Mutex(Storage())

    /// The source that empties the cache when the system runs low on memory, or `nil` for a cache that doesn't.
    private let memoryPressure: (any DispatchSourceMemoryPressure)?

    /// Creates an empty cache, such as one of a test's own.
    ///
    /// - Parameters:
    ///   - byteLimit: The most bytes the cache keeps: those of the JPEGs and of the decoded pixels it keeps alive. An
    ///     image over it on its own is encoded each time.
    ///   - entryLimit: The most images the cache keeps.
    ///   - emptiesUnderMemoryPressure: Whether the cache drops every image when the system warns that memory runs low.
    init(byteLimit: Int = 64 << 20, entryLimit: Int = 64, emptiesUnderMemoryPressure: Bool = false) {
        self.byteLimit = byteLimit
        self.entryLimit = entryLimit
        guard emptiesUnderMemoryPressure else {
            memoryPressure = nil
            return
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])
        memoryPressure = source
        source.setEventHandler { [weak self] in self?.removeAll() }
        source.activate()
    }

    deinit {
        memoryPressure?.cancel()
    }

    /// The number of images the cache keeps.
    var count: Int {
        storage.withLock { $0.entries.count }
    }

    /// Drops every image, so each is encoded again the next time it's sent.
    func removeAll() {
        storage.withLock { $0 = Storage() }
    }

    /// The JPEG kept for an image, or the one `encode` gives, which is kept for next time.
    ///
    /// The image is encoded outside the lock, so other images are looked up meanwhile.
    ///
    /// - Parameters:
    ///   - key: What the image is kept by, or `nil` to encode it without keeping it.
    ///   - encode: Encodes the image, or gives `nil` when it can't be read or encoded.
    /// - Returns: The JPEG's bytes, or `nil` when the image can't be read or encoded.
    func jpeg(for key: Key?, encode: () -> Data?) -> Data? {
        guard let key else { return encode() }
        if let data = cached(key) { return data }
        guard let data = encode() else { return nil }
        // A file that changed while it was read may hold other bytes than the key names.
        if key.isCurrent { store(data, for: key) }
        return data
    }

    /// The JPEG kept for a key, which counts as just used, or `nil` when there's none.
    private func cached(_ key: Key) -> Data? {
        storage.withLock { storage in
            guard let data = storage.entries[key]?.data else { return nil }
            storage.uses += 1
            storage.entries[key]?.lastUse = storage.uses
            return data
        }
    }

    /// Keeps a JPEG, then drops the images used least recently until the cache is within its limits.
    private func store(_ data: Data, for key: Key) {
        let (cost, overflow) = data.count.addingReportingOverflow(key.keptBytes)
        guard !overflow, cost <= byteLimit, entryLimit > 0 else { return }
        storage.withLock { storage in
            storage.uses += 1
            if let replaced = storage.entries.updateValue(Entry(data: data, cost: cost, lastUse: storage.uses), forKey: key) {
                storage.cost -= replaced.cost
            }
            storage.cost += cost
            while storage.cost > byteLimit || storage.entries.count > entryLimit,
                let oldest = storage.entries.min(by: { $0.value.lastUse < $1.value.lastUse })
            {
                storage.entries[oldest.key] = nil
                storage.cost -= oldest.value.cost
            }
        }
    }
}
