import CryptoKit
package import Foundation
import LanguageModelsCore
import Synchronization

/// Recent answers of a provider's info calls, kept in memory so repeated calls, such as one for each row of a list,
/// don't fetch them again.
///
/// An answer is kept by its URL and a digest of the headers that authenticated the call, never the headers themselves,
/// since some answers depend on the account. Failures aren't kept.
package final class InfoCache: Sendable {
    /// The cache that every call shares.
    package static let shared = InfoCache()

    /// What an answer is kept by.
    package struct Key: Hashable, Sendable {
        package let url: URL

        /// The SHA-256 digest of the headers that authenticated the call, or `nil` for a call without any.
        package let account: String?

        package init(url: URL, headers: [HTTPHeaderName: String]) {
            self.url = url
            let lines = headers.map { "\($0.key.rawValue.lowercased()): \($0.value)" }.sorted()
            account = lines.isEmpty ? nil : SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).description
        }
    }

    private struct Entry: Sendable {
        let value: any Sendable
        let expiry: ContinuousClock.Instant
    }

    private let entries = Mutex<[Key: Entry]>([:])

    /// Creates an empty cache, such as one of a test's own.
    package init() {}

    /// The answer kept for a key, or `nil` when there's none or it expired.
    package func value<Value: Sendable>(for key: Key, as type: Value.Type, now: ContinuousClock.Instant = .now) -> Value? {
        entries.withLock { entries in
            guard let entry = entries[key] else { return nil }
            guard entry.expiry > now else {
                entries[key] = nil
                return nil
            }
            return entry.value as? Value
        }
    }

    /// Keeps an answer for a while, and drops every answer that expired.
    ///
    /// - Parameters:
    ///   - value: The decoded answer.
    ///   - key: What the answer is kept by.
    ///   - lifetime: How long to keep it; zero or less keeps nothing.
    ///   - now: The time the lifetime counts from.
    package func store(_ value: some Sendable, for key: Key, lifetime: Duration, now: ContinuousClock.Instant = .now) {
        guard lifetime > .zero else { return }
        entries.withLock { entries in
            entries = entries.filter { $0.value.expiry > now }
            entries[key] = Entry(value: value, expiry: now + lifetime)
        }
    }
}
