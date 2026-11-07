package import CoreGraphics
import CryptoKit
package import Foundation
package import ImageIO
import LanguageModelsCore
import Synchronization

/// Images already encoded as JPEG, kept in memory so that a transcript's images, which every request sends again, are
/// decoded and encoded once rather than with every request.
///
/// An image is kept by what it holds, never by a name an app could give another image: data by its SHA-256 digest, a
/// file by its path, size, modification date and file number, so a file that changes is read again, and decoded pixels
/// by the image itself, which the cache keeps alive so no other image can take its place. Each is also kept by its
/// orientation, longest side and JPEG quality. Once the cache is over its limits, the images used least recently go
/// first. Images that can't be read or encoded aren't kept.
package final class EncodedImageCache: Sendable {
    /// The cache that every request shares, which empties when the system runs low on memory, since the images it
    /// keeps can be encoded again.
    package static let shared = EncodedImageCache(emptiesUnderMemoryPressure: true)

    /// What an encoded image is kept by.
    package struct Key: Hashable, Sendable {
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
        package init(data: Data, maximumSide: Int, quality: Double = ImageEncoding.standard.quality) {
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
        package init?(
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
        package init(
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
    package init(byteLimit: Int = 64 << 20, entryLimit: Int = 64, emptiesUnderMemoryPressure: Bool = false) {
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
    package var count: Int {
        storage.withLock { $0.entries.count }
    }

    /// Drops every image, so each is encoded again the next time it's sent.
    package func removeAll() {
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
    package func jpeg(for key: Key?, encode: () -> Data?) -> Data? {
        guard let key else { return encode() }
        if let data = cached(key) { return data }
        guard let data = encode() else { return nil }
        // A file that changed while it was read may hold other bytes than the key names.
        if key.isCurrent { store(data, for: key) }
        return data
    }

    /// The JPEG kept for a key, now the most recently used, or `nil` when there's none.
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
