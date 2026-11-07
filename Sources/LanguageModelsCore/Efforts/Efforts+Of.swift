extension Efforts {
    /// The words of one model's reasoning levels, which ``Efforts/Of`` reads to make its values, with
    /// `init(rawValue:)`, and to list them, with `allCases`.
    ///
    /// A provider module's catalog gives each model an empty enum that conforms to this protocol, under the catalog's
    /// namespace, such as `VendorCatalog.ModelName`, so each model has an effort type of its own. The catalog also
    /// writes an extension of `Efforts.Of` for the model, with a static member for each level.
    public protocol List: Sendable {
        /// The words of the levels the model accepts, highest first.
        static var efforts: [String] { get }

        /// The words of the levels the model accepted before, which its effort type keeps as deprecated members.
        static var removedEfforts: [String] { get }
    }
}

extension Efforts.List {
    /// None: the model accepts every level it ever accepted.
    public static var removedEfforts: [String] { [] }
}

extension Efforts {
    /// A reasoning level of one model, which `Tag` names.
    ///
    /// A catalog model's effort type has a static member for each level the model accepts, such as `.high`, so code
    /// can name only those. Each model has an effort type of its own, so the type stays the same when the model's
    /// levels change: a level the model gains adds a member, and a level it stops accepting stays, marked deprecated.
    ///
    /// An effort prints as its word, such as `high`.
    public struct Of<Tag: List>: ModelEffort, RawRepresentable, Hashable, Codable, CodingKeyRepresentable,
        CaseIterable, CustomStringConvertible
    {
        /// The level's word, as the provider's API spells it.
        public let rawValue: String

        /// The level with the given word, or `nil` when the model neither accepts it nor accepted it before.
        ///
        /// - Parameter rawValue: The level's word, such as `high`.
        public init?(rawValue: String) {
            guard Tag.efforts.contains(rawValue) || Tag.removedEfforts.contains(rawValue) else { return nil }
            self.rawValue = rawValue
        }

        /// A level the model's catalog lists, which a generated member creates.
        ///
        /// - Parameter rawValue: The level's word, such as `high`.
        package init(listed rawValue: String) {
            self.rawValue = rawValue
        }

        /// The levels the model accepts, highest first, without the levels it stopped accepting.
        public static var allCases: [Self] {
            Tag.efforts.map(Self.init(listed:))
        }

        /// The level's word, such as `high`.
        public var description: String {
            rawValue
        }
    }
}
