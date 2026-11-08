import Foundation

// MARK: - Stable JSON

/// Stable JSON for files in `Catalogs/`.
enum CatalogJSON {
    /// The value as JSON text with sorted keys, two-space indents and a final newline, so the same value always gives
    /// the same bytes.
    ///
    /// - Throws: ``GeneratorError/invalidCatalog(_:)`` when the value can't be encoded.
    static func encoded(_ value: some Encodable) throws(GeneratorError) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
        } catch {
            throw .invalidCatalog("A catalog can't be encoded: \(error)")
        }
    }

    /// Reads a file in the package, or returns `nil` when it doesn't exist.
    ///
    /// - Parameters:
    ///   - type: The type the file holds.
    ///   - path: The file, relative to the package root.
    ///   - packageDirectory: The package root.
    /// - Returns: The decoded value, or `nil` when the file doesn't exist.
    /// - Throws: ``GeneratorError/fileAccess(_:)`` when the file exists but can't be read, and
    ///   ``GeneratorError/invalidCatalog(_:)`` when it doesn't decode.
    static func read<Value: Decodable>(
        _ type: Value.Type,
        at path: String,
        in packageDirectory: URL
    ) throws(GeneratorError) -> Value? {
        let data: Data
        do {
            data = try Data(contentsOf: packageDirectory.appending(path: path))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            throw .fileAccess("Couldn't read \(path): \(error.localizedDescription)")
        }
        return try decode(type, from: data, path: path)
    }

    /// Decodes a catalog file's contents.
    ///
    /// - Parameters:
    ///   - type: The type the file holds.
    ///   - data: The file's contents.
    ///   - path: How to name the file in an error.
    /// - Returns: The decoded value.
    /// - Throws: ``GeneratorError/invalidCatalog(_:)`` when the contents don't decode.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data, path: String) throws(GeneratorError) -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .invalidCatalog("\(path) doesn't decode: \(error)")
        }
    }
}

// MARK: - API shape

/// The shape of a source's API: every field its raw model lists use, and the words of its vocabulary fields.
///
/// `Catalogs/<source>.schema.json` stores it. The file changes only when the source adds or drops a field or a
/// vocabulary word, so its diff flags API changes the decoder would otherwise ignore.
struct CatalogSchema: Codable, Equatable, Sendable {
    /// Every path that holds a value somewhere in the lists, sorted. Array elements are written `[]`, as in
    /// `data[].pricing.prompt`. Fields that are only ever `null` don't count.
    let fields: [String]

    /// The distinct words of each vocabulary field, sorted.
    let values: [String: [String]]
}

extension CatalogSchema {
    /// The shape of a raw JSON document.
    ///
    /// - Parameters:
    ///   - data: The document.
    ///   - vocabularyFields: The paths whose string values to collect.
    /// - Throws: An error when `data` isn't JSON.
    init(json data: Data, vocabularyFields: Set<String>) throws {
        var fields: Set<String> = []
        var values: [String: Set<String>] = [:]
        func walk(_ value: Any, at path: String) {
            switch value {
            case let object as [String: Any]:
                for (key, child) in object { walk(child, at: path.isEmpty ? key : "\(path).\(key)") }
            case let array as [Any]:
                for element in array { walk(element, at: "\(path)[]") }
            case is NSNull:
                break
            default:
                fields.insert(path)
                if vocabularyFields.contains(path), let word = value as? String { values[path, default: []].insert(word) }
            }
        }
        walk(try JSONSerialization.jsonObject(with: data), at: "")
        self.fields = fields.sorted()
        self.values = values.mapValues { $0.sorted() }
    }

    /// What changed since an earlier schema, one sentence per added or dropped field or word.
    func changes(since previous: CatalogSchema) -> [String] {
        let addedFields = Set(fields).subtracting(previous.fields).sorted().map { "Adds the field `\($0)`." }
        let droppedFields = Set(previous.fields).subtracting(fields).sorted().map { "Drops the field `\($0)`." }
        let valueChanges = Set(values.keys).union(previous.values.keys).sorted().flatMap { field in
            let old = previous.values[field] ?? []
            let new = values[field] ?? []
            return Set(new).subtracting(old).sorted().map { "Adds the value `\($0)` to `\(field)`." }
                + Set(old).subtracting(new).sorted().map { "Drops the value `\($0)` from `\(field)`." }
        }
        return addedFields + droppedFields + valueChanges
    }
}
