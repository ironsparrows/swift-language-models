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
