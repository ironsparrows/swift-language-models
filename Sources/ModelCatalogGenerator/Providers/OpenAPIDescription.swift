import Foundation

// MARK: - OpenAPI descriptions

/// A provider's OpenAPI description, reduced to the schemas whose string values the catalog reads.
protocol OpenAPIDescription: Decodable {
    associatedtype Schema: OpenAPIWordSchema

    var components: OpenAPIComponents<Schema> { get }
}

/// A schema whose string values the catalog reads.
protocol OpenAPIWordSchema: Decodable {
    /// The schema's string values, in order, each once.
    var values: [String] { get }
}

/// The `components` of an OpenAPI description: its schemas, by name.
struct OpenAPIComponents<Schema: Decodable>: Decodable {
    let schemas: [String: Schema]
}

/// A schema the catalog needs is missing from an OpenAPI description, or lists no words.
struct MissingSchema: Error, CustomStringConvertible {
    let name: String

    var description: String { "it has no words for the \(name) schema" }
}

extension OpenAPIDescription {
    /// The schema that lists every effort word, which every provider's description names alike.
    static var effortSchemaName: String { "ReasoningEffort" }

    static func decoded(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    /// The words a schema lists.
    ///
    /// - Throws: ``MissingSchema`` when the description has no such schema, or it lists no words.
    func words(ofSchema schema: String) throws(MissingSchema) -> [String] {
        guard let words = components.schemas[schema]?.values, !words.isEmpty else { throw MissingSchema(name: schema) }
        return words
    }
}

extension KeyedDecodingContainer {
    /// The string values of a schema's `enum`, in order, without `null`. An `enum` that lists numbers, which no
    /// vocabulary uses, or a missing one, has none.
    func decodeStringValues(forKey key: Key) -> [String] {
        (try? decodeIfPresent([String?].self, forKey: key))?.compactMap(\.self) ?? []
    }
}

// MARK: - Unique elements

extension Sequence where Element: Hashable {
    /// The elements without repeats, each where it first appears.
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
