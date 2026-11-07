package import FoundationModels
package import LanguageModelsCore

/// Request metadata as OpenAI's formats take it.
package enum RequestMetadata {
    /// The limits that OpenAI's formats, and the hosts that follow them, put on request metadata.
    private enum MetadataLimit {
        static let pairs = 16
        static let keyLength = 64
        static let valueLength = 512
    }

    /// A request's string metadata, sorted by key, within the limits of 16 pairs, keys up to 64 characters and values
    /// up to 512. Pairs past the limits are left out, since a host rejects the whole request for them.
    ///
    /// - Returns: The metadata to send, or `nil` when none is left, and the keys of the pairs left out, sorted.
    package static func limited(_ metadata: [String: GeneratedContent]) -> (json: JSONValue?, droppedKeys: [String]) {
        let members = metadata.compactMap { key, value -> JSONObject.Member? in
            guard key.count <= MetadataLimit.keyLength, case .string(let text) = value.kind, text.count <= MetadataLimit.valueLength
            else { return nil }
            return .init(key: key, value: .string(text))
        }
        let limited = JSONObject(members).sortedByKey().members.prefix(MetadataLimit.pairs)
        let keptKeys = Set(limited.map(\.key))
        let droppedKeys = metadata.keys.filter { !keptKeys.contains($0) }.sorted()
        return (limited.isEmpty ? nil : .object(JSONObject(Array(limited))), droppedKeys)
    }
}
