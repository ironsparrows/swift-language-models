/// Renders one static member of the provider's model type, such as `OpenRouterModel`, per model, each in an extension
/// for the model's own effort type, plus a lookup by id and a list of every model.
///
/// Each member passes only the arguments that differ from the initializer's defaults.
enum ModelsTemplate {
    /// Where a source's models go.
    static func path(for source: CatalogSource) -> String {
        "\(source.generatedDirectory)/\(source.modelTypeName)+Catalog.swift"
    }

    /// Where a model stands with its source.
    private enum Status {
        case current
        case retiring(on: CatalogDay)
        case removed(on: CatalogDay)

        /// The status of a model the source still lists: retiring when it has an expiration date, and current
        /// otherwise.
        init(expirationDate: CatalogDay?) {
            self = expirationDate.map(Status.retiring) ?? .current
        }

        /// The availability attribute of the model's public member, if any.
        func attribute(from source: CatalogSource) -> String? {
            switch self {
            case .current: nil
            case .retiring(let day):
                "@available(*, deprecated, message: \(SwiftLiteral.string("\(source.displayName) retires this model on \(day)")))"
            case .removed(let day): source.removedAttribute(on: day)
            }
        }

        /// Whether the model's data lives in a file-private member, so the lookup and the list can reach a deprecated
        /// model without a warning.
        var hasPrivateEntry: Bool {
            if case .retiring = self { true } else { false }
        }

        /// Whether the id lookup finds the model and the list of every model holds it.
        var isInLookup: Bool {
            if case .removed = self { false } else { true }
        }
    }

    /// A model's static member, and what it's rendered from.
    private struct Member {
        let model: CatalogModel
        let name: SwiftIdentifier
        /// The model's effort type, such as `Efforts.Of<OpenRouterCatalog.AnthropicClaudeHaiku5_5>`.
        let effortType: String
        /// The levels the model accepts, highest first.
        let efforts: [String]
        let status: Status

        /// The member that holds the model's data.
        var dataName: SwiftIdentifier { status.hasPrivateEntry ? name.appending("Entry") : name }
    }

    /// The source's file of model members, with the lookup by id and the list of every model.
    ///
    /// - Throws: ``GeneratorError/invalidCatalog(_:)`` when a model gets no member name, the name of a case of
    ///   `Optional` or the name of another model, or its data can't become a call of the initializer.
    static func render(_ snapshot: CatalogSnapshot, ranking: EffortRanking) throws(GeneratorError) -> GeneratedFile {
        let removedOn = Dictionary(snapshot.removed.map { ($0.model.id, $0.removedOn) }) { first, _ in first }
        let members = snapshot.namedModels.map { model, name in
            Member(
                model: model,
                name: name,
                effortType: snapshot.source.effortType(named: name),
                efforts: ranking.sorted(model.reasoningEfforts),
                status: removedOn[model.id].map { Status.removed(on: $0) } ?? Status(expirationDate: model.expirationDate)
            )
        }
        try SwiftIdentifier.check(
            members.flatMap { member in Set([member.name, member.dataName]).map { ($0, member.model.id) } },
            reserved: SwiftIdentifier.optionalCaseNames,
            kind: "\(snapshot.source.displayName) models"
        )

        var lines = SourceText.header(from: [snapshot.source])
        lines.insert("// swift-format-ignore-file: AlwaysUseLowerCamelCase", at: 0)
        lines += ["import Foundation", "public import FoundationModels", "public import LanguageModels"]
        for member in members {
            lines += ["", "extension \(snapshot.source.modelTypeName) where Effort == \(member.effortType) {"]
            lines += try memberLines(member, source: snapshot.source)
            lines += ["}"]
        }
        let listed = members.filter(\.status.isInLookup)
        lines += lookupLines(listed, source: snapshot.source)
        lines += listLines(listed, source: snapshot.source)
        return GeneratedFile(path: path(for: snapshot.source), contents: SourceText.file(lines))
    }

    /// A model's doc comment, its availability and its static member.
    ///
    /// - Throws: ``GeneratorError/invalidCatalog(_:)`` when the model's default effort isn't one it lists, or it needs
    ///   an argument its provider's initializer doesn't take.
    private static func memberLines(_ member: Member, source: CatalogSource) throws(GeneratorError) -> [String] {
        let model = member.model
        if let defaultEffort = model.defaultReasoningEffort, !member.efforts.contains(defaultEffort) {
            throw .invalidCatalog(
                "\(source.displayName) model \(model.id) defaults to the effort '\(defaultEffort)', which it doesn't list."
            )
        }

        var lines = SourceText.documentation(model.displayName, indent: "    ")
        if let target = model.aliasTarget {
            lines += ["    ///"] + SourceText.documentation("An alias that points to `\(target)` now.", indent: "    ")
        }
        if let attribute = member.status.attribute(from: source) { lines += ["    \(attribute)"] }
        if member.status.hasPrivateEntry {
            lines += ["    public static var \(member.name): Self { \(member.dataName) }", ""]
        }
        let access = member.status.hasPrivateEntry ? "fileprivate" : "public"
        lines += ["    \(access) static var \(member.dataName): Self {"]
        lines += try initializer(of: model, efforts: member.efforts, source: source).lines(indent: "        ", breaks: true)
        lines += ["    }"]
        return lines
    }

    /// The modalities that the model initializer takes and outputs unless told otherwise.
    private static let defaultModalities = [CatalogModel.textModality]

    /// The call that creates a model's details, which passes only the arguments that differ from the defaults.
    ///
    /// - Throws: ``GeneratorError/invalidCatalog(_:)`` when the model needs an argument its provider's initializer
    ///   doesn't take.
    private static func initializer(of model: CatalogModel, efforts: [String], source: CatalogSource) throws(GeneratorError)
        -> SwiftExpression
    {
        func words(_ words: [String], unlessEqualTo defaultWords: [String]) -> SwiftExpression? {
            words == defaultWords ? nil : .array(words.map { .atom(".\(SwiftIdentifier.member(for: $0))") })
        }
        func effort(_ word: String) -> SwiftExpression { .atom(".\(SwiftIdentifier.effortMember(for: word))") }
        // An argument that only some providers' initializers take, or `nil` when the model needs none.
        func optional(_ label: String, _ value: SwiftExpression?) throws(GeneratorError) -> SwiftExpression? {
            guard let value else { return nil }
            guard source.optionalModelArguments.contains(label) else {
                throw .invalidCatalog(
                    "\(source.displayName) model \(model.id) needs `\(label):`, which \(source.modelTypeName)'s initializer doesn't take.")
            }
            return value
        }
        let aliasTarget = try optional("aliasTarget", model.aliasTarget.map { .atom(SwiftLiteral.string($0)) })
        let outputModalities = try optional("outputModalities", words(model.outputModalities, unlessEqualTo: defaultModalities))
        let cachesOnlyMarkedPrompts = try optional("cachesOnlyMarkedPrompts", model.cachesOnlyMarkedPrompts ? .atom("true") : nil)

        return .call(
            "Self",
            [
                "id": .atom(SwiftLiteral.string(model.id)),
                "displayName": .atom(SwiftLiteral.string(model.displayName)),
                "releaseDate": .atom(SwiftLiteral.date(secondsSince1970: model.releasedAt)),
                "aliasTarget": aliasTarget,
                "knowledgeCutoff": model.knowledgeCutoff.map { .atom(SwiftLiteral.date($0)) },
                "expirationDate": model.expirationDate.map { .atom(SwiftLiteral.date($0)) },
                "contextSize": model.contextSize.map { .atom(SwiftLiteral.integer($0)) },
                "inputModalities": words(model.inputModalities, unlessEqualTo: defaultModalities),
                "outputModalities": outputModalities,
                // Always written: a model built by hand has to say which parameters it takes.
                "supportedParameters": .array(model.supportedParameters.map { .atom(".\(SwiftIdentifier.member(for: $0))") }),
                "reasoning": model.reasoning == .unsupported ? nil : .atom(model.reasoning.swiftLiteral),
                "reasoningEfforts": efforts.isEmpty ? nil : .array(efforts.map(effort)),
                "defaultReasoningEffort": model.defaultReasoningEffort.map(effort),
                "cachesOnlyMarkedPrompts": cachesOnlyMarkedPrompts,
            ]
        )
    }

    /// The initializer that finds a model by id. A retiring model is read through its data member, so the lookup builds
    /// without a deprecation warning.
    private static func lookupLines(_ members: [Member], source: CatalogSource) -> [String] {
        var lines = [
            "",
            "extension \(source.modelTypeName) where Effort == ContextOptions.ReasoningLevel {",
            "    /// The catalog's model with the given id, with its efforts in their open form, or `nil` when the catalog",
            "    /// doesn't list the id or \(source.displayName) stopped listing the model.",
            "    ///",
            "    /// - Parameter id: An \(source.displayName) model id, such as `\(source.exampleModelID)`.",
            "    public init?(catalogID id: \(source.modelIDTypeName)) {",
            "        switch id.rawValue {",
        ]
        for member in members {
            lines += ["        case \(SwiftLiteral.string(member.model.id)):"]
            lines += typedModel(member, in: "self.init", source: source).lines(indent: "            ")
        }
        lines += ["        default:", "            return nil", "        }", "    }", "}"]
        return lines
    }

    /// The list of every model the lookup finds, in the same order, built once into a file-level constant, since a
    /// generic type can't store a static one. A retiring model is read through its data member, so the list builds
    /// without a deprecation warning.
    private static func listLines(_ members: [Member], source: CatalogSource) -> [String] {
        let listName = "\(source.memberPrefix)CatalogModels"
        var lines = [
            "",
            "extension \(source.modelTypeName) where Effort == ContextOptions.ReasoningLevel {",
            "    /// Every model in the catalog, sorted by id, with their efforts in their open form, such as for listing the",
            "    /// models a person can pick from. Models \(source.displayName) removed aren't listed.",
            "    ///",
            "    /// The list is built once, the first time it's read.",
            "    public static var catalogModels: [Self] { \(listName) }",
            "}",
            "",
            "/// A catalog model with its efforts in their open form.",
            "private typealias OpenModel = \(source.modelTypeName)<ContextOptions.ReasoningLevel>",
            "",
            "/// Every model in the catalog, built once, the first time `catalogModels` is read.",
            "private let \(listName): [OpenModel] = [",
        ]
        for member in members {
            lines += typedModel(member, in: "OpenModel", source: source).lines(indent: "    ", suffix: ",")
        }
        lines += ["]"]
        return lines
    }

    /// A call that passes a model's member, such as `Self(OpenRouterModel<_>.typesafeJevRouter)`. Swift fills in the
    /// placeholder with the member's effort type, since each model's member is the only one with its name.
    private static func typedModel(_ member: Member, in call: String, source: CatalogSource) -> SwiftExpression {
        .call(call, arguments: [.init(label: "", value: .atom("\(source.modelTypeName)<_>.\(member.dataName)"))])
    }
}
