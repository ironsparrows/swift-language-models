package import Foundation

// MARK: - Value

/// A JSON value that writes the same bytes every time.
///
/// Providers reuse a cached prompt only when the request starts with the same bytes as before, and `JSONEncoder`
/// orders keys differently on every launch. Objects built in code keep the order they're written in; objects decoded
/// from JSON are sorted by key, so they come out the same however they arrived.
package enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case integer(Int)
    /// An integer too large for `Int`, kept digit for digit.
    case largeInteger(Decimal)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    /// The value's JSON text.
    package var text: String {
        var text = ""
        write(to: &text)
        return text
    }

    /// The value's JSON text, as UTF-8 bytes.
    package var data: Data {
        Data(text.utf8)
    }

    /// The member with the given key, when the value is an object.
    package subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    /// The element at an index, when the value is an array that long.
    package subscript(index: Int) -> JSONValue? {
        if case .array(let elements) = self, elements.indices.contains(index) { elements[index] } else { nil }
    }

    /// The text, when the value is a string.
    package var stringValue: String? {
        if case .string(let text) = self { text } else { nil }
    }

    private func write(to text: inout String) {
        switch self {
        case .null: text += "null"
        case .bool(let value): text += value ? "true" : "false"
        case .integer(let value): text += String(value)
        case .largeInteger(let value): text += value.description
        case .number(let value): text += Self.text(of: value)
        case .string(let value): Self.write(value, to: &text)
        case .array(let elements):
            text += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { text += "," }
                element.write(to: &text)
            }
            text += "]"
        case .object(let object):
            text += "{"
            for (index, member) in object.members.enumerated() {
                if index > 0 { text += "," }
                Self.write(member.key, to: &text)
                text += ":"
                member.value.write(to: &text)
            }
            text += "}"
        }
    }

    /// A number without a fraction as an integer, and any other number in its shortest exact form. JSON has no
    /// infinity or NaN, so those become `null`.
    private static func text(of number: Double) -> String {
        guard number.isFinite else { return "null" }
        if let integer = Int(exactly: number) { return String(integer) }
        return number.description
    }

    private static func write(_ string: String, to text: inout String) {
        text += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                text += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByStringLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral
{
    package init(dictionaryLiteral elements: (String, JSONValue?)...) {
        self = .object(JSONObject(optionalMembers: elements))
    }

    package init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }

    package init(stringLiteral value: String) {
        self = .string(value)
    }

    package init(integerLiteral value: Int) {
        self = .integer(value)
    }

    package init(floatLiteral value: Double) {
        self = .number(value)
    }

    package init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: Decodable {
    /// Decodes any JSON value, with each object's members sorted by key.
    package init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: JSONKey.self) {
            let members = try container.allKeys.map { key in
                JSONObject.Member(key: key.stringValue, value: try container.decode(JSONValue.self, forKey: key))
            }
            self = .object(JSONObject(members).sortedByKey())
        } else if var container = try? decoder.unkeyedContainer() {
            var elements: [JSONValue] = []
            while !container.isAtEnd { elements.append(try container.decode(JSONValue.self)) }
            self = .array(elements)
        } else {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self) {
                // `Int` refused it, so a whole number here is past `Int`'s range and would lose digits as a `Double`;
                // a `Decimal` keeps them. Checking the `Double` against `Int` instead would miss one that rounds to
                // `Int.min`.
                if value.rounded() == value, let exact = try? container.decode(Decimal.self) {
                    self = .largeInteger(exact)
                } else {
                    self = .number(value)
                }
            } else {
                self = .string(try container.decode(String.self))
            }
        }
    }

    /// Decodes JSON text.
    package init(json data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - Object

/// A JSON object whose members keep their order when written.
package struct JSONObject: Sendable, Hashable {
    package struct Member: Sendable, Hashable {
        package let key: String
        package var value: JSONValue

        package init(key: String, value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    package private(set) var members: [Member]

    package init(_ members: [Member] = []) {
        self.members = members
    }

    /// The value of the first member with the given key.
    package subscript(key: String) -> JSONValue? {
        get { members.first { $0.key == key }?.value }
        set {
            if let index = members.firstIndex(where: { $0.key == key }) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(Member(key: key, value: newValue))
            }
        }
    }

    /// Whether two objects have the same members, in any order, as JSON objects are compared.
    package static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        lhs.members.count == rhs.members.count && lhs.members.allSatisfy { rhs[$0.key] == $0.value }
    }

    /// Hashes the members in key order, so objects that are equal in any order hash alike.
    ///
    /// - Parameter hasher: The hasher to feed the members to.
    package func hash(into hasher: inout Hasher) {
        hasher.combine(sortedByKey().members)
    }

    /// The object with its members in a new order.
    func sorted(by areInIncreasingOrder: (Member, Member) -> Bool) -> JSONObject {
        JSONObject(members.sorted(by: areInIncreasingOrder))
    }

    /// The object with the members of the given keys first, in that order, then the others in their own order, so a
    /// body keeps the bytes it has always had however it was built.
    ///
    /// - Parameter keys: The keys in the order their members go.
    /// - Returns: The object.
    package func ordered(by keys: [String]) -> JSONObject {
        let position = Dictionary(keys.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = members.filter { position[$0.key] != nil }.sorted { position[$0.key, default: 0] < position[$1.key, default: 0] }
        return JSONObject(known + members.filter { position[$0.key] == nil })
    }

    /// The object with its members sorted by key, which gives the same bytes however it was built.
    package func sortedByKey() -> JSONObject {
        sorted { $0.key < $1.key }
    }
}

extension JSONObject: ExpressibleByDictionaryLiteral {
    /// An object with the members that have a value, in the order written, so an optional field can be `nil`.
    package init(dictionaryLiteral elements: (String, JSONValue?)...) {
        self.init(optionalMembers: elements)
    }

    init(optionalMembers elements: [(String, JSONValue?)]) {
        self.init(elements.compactMap { key, value in value.map { Member(key: key, value: $0) } })
    }
}

// MARK: - Key

/// The key of a JSON object's member, for any name, so a type can encode members whose names are known only at run
/// time, and write fixed ones as string literals.
package struct JSONKey: CodingKey, ExpressibleByStringLiteral, Sendable {
    package let stringValue: String

    package init(stringValue: String) {
        self.stringValue = stringValue
    }

    package init(stringLiteral value: String) {
        stringValue = value
    }

    package var intValue: Int? { nil }

    package init?(intValue: Int) {
        nil
    }
}

// MARK: - Encoder

/// Encodes a value as a ``JSONValue``, with each object's members in the order the value encodes them.
///
/// A request's typed parts, such as a provider's own members, go through this encoder, so their bytes come out the
/// same every time and in the order their types declare, which a host's prompt cache depends on. Integers become
/// integers, an unsigned one past `Int`'s range a large integer, floating-point numbers numbers, a `Decimal` its
/// digits, and a ``JSONValue`` stays as it is. An optional member that's `nil` is left out, as synthesized conformances
/// encode it; a member a value encodes twice keeps its first place and its last value.
package enum JSONValueEncoder {
    /// The value as JSON.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: The JSON the value encodes as, or `null` for one that encodes nothing.
    /// - Throws: What the value's `encode(to:)` throws.
    package static func encode(_ value: some Encodable) throws -> JSONValue {
        let node = Node()
        try node.encode(value, codingPath: [])
        return node.json
    }

    /// The members of a value that encodes as an object.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: The object's members, or none when the value encodes as something else.
    /// - Throws: What the value's `encode(to:)` throws.
    package static func members(of value: some Encodable) throws -> JSONObject {
        if case .object(let object) = try encode(value) { object } else { JSONObject() }
    }
}

extension JSONValueEncoder {
    /// One value of the tree being encoded, which containers fill in as the value encodes itself.
    private final class Node {
        private enum Content {
            case empty
            case value(JSONValue)
            case object([(key: String, node: Node)])
            case array([Node])
        }

        private var content = Content.empty

        var json: JSONValue {
            switch content {
            case .empty: .null
            case .value(let value): value
            case .object(let members): .object(JSONObject(members.map { .init(key: $0.key, value: $0.node.json) }))
            case .array(let elements): .array(elements.map(\.json))
            }
        }

        func set(_ value: JSONValue) {
            content = .value(value)
        }

        /// The node of the member with the given key, added at the end unless the object already has it.
        func member(_ key: String) -> Node {
            var members: [(key: String, node: Node)] = if case .object(let members) = content { members } else { [] }
            if let existing = members.first(where: { $0.key == key }) {
                existing.node.content = .empty
                return existing.node
            }
            let node = Node()
            members.append((key, node))
            content = .object(members)
            return node
        }

        func makeObject() {
            if case .object = content { return }
            content = .object([])
        }

        /// A new element at the end of the array.
        func appendElement() -> Node {
            var elements: [Node] = if case .array(let elements) = content { elements } else { [] }
            let node = Node()
            elements.append(node)
            content = .array(elements)
            return node
        }

        func makeArray() {
            if case .array = content { return }
            content = .array([])
        }

        var count: Int {
            switch content {
            case .object(let members): members.count
            case .array(let elements): elements.count
            default: 0
            }
        }

        /// Encodes a value into the node: JSON and decimals directly, anything else through its `encode(to:)`.
        func encode(_ value: some Encodable, codingPath: [any CodingKey]) throws {
            if let json = Self.json(of: value) {
                set(json)
            } else {
                try value.encode(to: TreeEncoder(node: self, codingPath: codingPath))
            }
        }

        private static func json(of value: some Encodable) -> JSONValue? {
            switch value {
            case let json as JSONValue: json
            case let decimal as Decimal: .largeInteger(decimal)
            default: nil
            }
        }
    }

    private struct TreeEncoder: Encoder {
        let node: Node
        let codingPath: [any CodingKey]
        var userInfo: [CodingUserInfoKey: Any] { [:] }

        func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
            node.makeObject()
            return KeyedEncodingContainer(KeyedContainer<Key>(node: node, codingPath: codingPath))
        }

        func unkeyedContainer() -> any UnkeyedEncodingContainer {
            node.makeArray()
            return UnkeyedContainer(node: node, codingPath: codingPath)
        }

        func singleValueContainer() -> any SingleValueEncodingContainer {
            SingleValueContainer(node: node, codingPath: codingPath)
        }
    }

    private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let node: Node
        let codingPath: [any CodingKey]

        mutating func encodeNil(forKey key: Key) throws { node.member(key.stringValue).set(.null) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { node.member(key.stringValue).set(.bool(value)) }
        mutating func encode(_ value: String, forKey key: Key) throws { node.member(key.stringValue).set(.string(value)) }
        mutating func encode(_ value: Double, forKey key: Key) throws { node.member(key.stringValue).set(.number(value)) }
        mutating func encode(_ value: Float, forKey key: Key) throws { node.member(key.stringValue).set(.number(Double(value))) }
        mutating func encode(_ value: Int, forKey key: Key) throws { node.member(key.stringValue).set(.integer(value)) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { node.member(key.stringValue).set(.integer(Int(value))) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { node.member(key.stringValue).set(.integer(Int(value))) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { node.member(key.stringValue).set(.integer(Int(value))) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { node.member(key.stringValue).set(.integer(Int(value))) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { node.member(key.stringValue).set(.unsigned(value)) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { node.member(key.stringValue).set(.integer(Int(value))) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { node.member(key.stringValue).set(.integer(Int(value))) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { node.member(key.stringValue).set(.integer(Int(value))) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { node.member(key.stringValue).set(.unsigned(value)) }

        mutating func encode(_ value: some Encodable, forKey key: Key) throws {
            try node.member(key.stringValue).encode(value, codingPath: codingPath + [key])
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy keyType: NestedKey.Type,
            forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            let member = node.member(key.stringValue)
            member.makeObject()
            return KeyedEncodingContainer(KeyedContainer<NestedKey>(node: member, codingPath: codingPath + [key]))
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            let member = node.member(key.stringValue)
            member.makeArray()
            return UnkeyedContainer(node: member, codingPath: codingPath + [key])
        }

        mutating func superEncoder() -> any Encoder {
            TreeEncoder(node: node.member("super"), codingPath: codingPath)
        }

        mutating func superEncoder(forKey key: Key) -> any Encoder {
            TreeEncoder(node: node.member(key.stringValue), codingPath: codingPath + [key])
        }
    }

    private struct UnkeyedContainer: UnkeyedEncodingContainer {
        let node: Node
        let codingPath: [any CodingKey]
        var count: Int { node.count }

        mutating func encodeNil() throws { node.appendElement().set(.null) }
        mutating func encode(_ value: Bool) throws { node.appendElement().set(.bool(value)) }
        mutating func encode(_ value: String) throws { node.appendElement().set(.string(value)) }
        mutating func encode(_ value: Double) throws { node.appendElement().set(.number(value)) }
        mutating func encode(_ value: Float) throws { node.appendElement().set(.number(Double(value))) }
        mutating func encode(_ value: Int) throws { node.appendElement().set(.integer(value)) }
        mutating func encode(_ value: Int8) throws { node.appendElement().set(.integer(Int(value))) }
        mutating func encode(_ value: Int16) throws { node.appendElement().set(.integer(Int(value))) }
        mutating func encode(_ value: Int32) throws { node.appendElement().set(.integer(Int(value))) }
        mutating func encode(_ value: Int64) throws { node.appendElement().set(.integer(Int(value))) }
        mutating func encode(_ value: UInt) throws { node.appendElement().set(.unsigned(value)) }
        mutating func encode(_ value: UInt8) throws { node.appendElement().set(.integer(Int(value))) }
        mutating func encode(_ value: UInt16) throws { node.appendElement().set(.integer(Int(value))) }
        mutating func encode(_ value: UInt32) throws { node.appendElement().set(.integer(Int(value))) }
        mutating func encode(_ value: UInt64) throws { node.appendElement().set(.unsigned(value)) }

        mutating func encode(_ value: some Encodable) throws {
            let index = node.count
            try node.appendElement().encode(value, codingPath: codingPath + [IndexKey(index)])
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
            let index = node.count
            let element = node.appendElement()
            element.makeObject()
            return KeyedEncodingContainer(KeyedContainer<NestedKey>(node: element, codingPath: codingPath + [IndexKey(index)]))
        }

        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
            let index = node.count
            let element = node.appendElement()
            element.makeArray()
            return UnkeyedContainer(node: element, codingPath: codingPath + [IndexKey(index)])
        }

        mutating func superEncoder() -> any Encoder {
            let index = node.count
            return TreeEncoder(node: node.appendElement(), codingPath: codingPath + [IndexKey(index)])
        }
    }

    private struct SingleValueContainer: SingleValueEncodingContainer {
        let node: Node
        let codingPath: [any CodingKey]

        mutating func encodeNil() throws { node.set(.null) }
        mutating func encode(_ value: Bool) throws { node.set(.bool(value)) }
        mutating func encode(_ value: String) throws { node.set(.string(value)) }
        mutating func encode(_ value: Double) throws { node.set(.number(value)) }
        mutating func encode(_ value: Float) throws { node.set(.number(Double(value))) }
        mutating func encode(_ value: Int) throws { node.set(.integer(value)) }
        mutating func encode(_ value: Int8) throws { node.set(.integer(Int(value))) }
        mutating func encode(_ value: Int16) throws { node.set(.integer(Int(value))) }
        mutating func encode(_ value: Int32) throws { node.set(.integer(Int(value))) }
        mutating func encode(_ value: Int64) throws { node.set(.integer(Int(value))) }
        mutating func encode(_ value: UInt) throws { node.set(.unsigned(value)) }
        mutating func encode(_ value: UInt8) throws { node.set(.integer(Int(value))) }
        mutating func encode(_ value: UInt16) throws { node.set(.integer(Int(value))) }
        mutating func encode(_ value: UInt32) throws { node.set(.integer(Int(value))) }
        mutating func encode(_ value: UInt64) throws { node.set(.unsigned(value)) }

        mutating func encode(_ value: some Encodable) throws {
            try node.encode(value, codingPath: codingPath)
        }
    }

    /// The coding key of an array's element.
    private struct IndexKey: CodingKey {
        let intValue: Int?
        var stringValue: String { intValue.map(String.init) ?? "" }

        init(_ index: Int) {
            intValue = index
        }

        init?(stringValue: String) {
            nil
        }

        init?(intValue: Int) {
            self.intValue = intValue
        }
    }
}

extension JSONValue {
    /// An unsigned integer: an integer when `Int` holds it, otherwise a large integer that keeps every digit.
    fileprivate static func unsigned(_ value: some UnsignedInteger) -> JSONValue {
        Int(exactly: value).map(JSONValue.integer) ?? .largeInteger(Decimal(string: String(value)) ?? 0)
    }
}

extension JSONValue: Encodable {
    /// Encodes the value as the JSON it holds, with each object's members in their order.
    package func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .integer(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .largeInteger(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let elements):
            var container = encoder.unkeyedContainer()
            for element in elements { try container.encode(element) }
        case .object(let object):
            var container = encoder.container(keyedBy: JSONKey.self)
            for member in object.members {
                try container.encode(member.value, forKey: JSONKey(stringValue: member.key))
            }
        }
    }
}
