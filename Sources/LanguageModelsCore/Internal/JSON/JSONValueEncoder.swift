import Foundation

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
