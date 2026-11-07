package import Foundation
public import FoundationModels
import os

/// A value of a guided answer that breaks a guide of its schema, such as a number below its minimum.
///
/// Foundation Models checks a guided answer's types as it decodes the answer, and the package checks the guides that
/// become constraints of the schema. An answer that breaks one throws `GeneratedContent.ParsingError`, whose
/// `underlyingError` is a ``GuideViolations`` that lists each value, so an app can decide value by value: clamp a
/// number, cut a list short, or ask again.
///
/// ```swift
/// do {
///     return try await session.respond(to: prompt, generating: Dinner.self).content
/// } catch let error as GeneratedContent.ParsingError {
///     guard let broken = error.underlyingError as? GuideViolations else { throw error }
///     for violation in broken.violations where violation.keyword == .minimum {
///         print(violation.path, violation.value, violation.limit)  // minutes 2 5
///     }
///     throw error
/// }
/// ```
public struct GuideViolation: Sendable, Equatable, CustomStringConvertible {
    /// Where the value is in the answer, such as `ingredients[1].grams`, or empty for the whole answer.
    public let path: String

    /// The schema keyword the value breaks, such as ``Keyword/minimum``.
    public let keyword: Keyword

    /// The value that breaks the guide.
    public let value: GeneratedContent

    /// The guide's limit, as the schema states it: the bound of a minimum, a maximum or a count, the pattern, the
    /// constant, or the allowed values.
    public let limit: GeneratedContent

    /// What's wrong with the value, such as `is 0, below the minimum of 1`.
    private let problem: String

    package init(path: String, keyword: Keyword, value: GeneratedContent, limit: GeneratedContent, problem: String) {
        self.path = path
        self.keyword = keyword
        self.value = value
        self.limit = limit
        self.problem = problem
    }

    /// Where the value is and what's wrong with it, such as `ingredients[1].grams is 0, below the minimum of 1`.
    public var description: String {
        "\(path.isEmpty ? "The answer" : path) \(problem)"
    }
}

extension GuideViolation {
    /// A JSON Schema keyword that a guide becomes.
    public struct Keyword: ProviderVocabulary {
        /// The one value allowed, which `.constant` becomes.
        public static let const: Self = "const"

        /// The values allowed, which `.anyOf` becomes.
        public static let `enum`: Self = "enum"

        /// The lowest number allowed, which `.minimum` and `.range` become.
        public static let minimum: Self = "minimum"

        /// The highest number allowed, which `.maximum` and `.range` become.
        public static let maximum: Self = "maximum"

        /// A number the value must be above.
        public static let exclusiveMinimum: Self = "exclusiveMinimum"

        /// A number the value must be below.
        public static let exclusiveMaximum: Self = "exclusiveMaximum"

        /// The fewest elements allowed, which `.minimumCount` and `.count` become.
        public static let minItems: Self = "minItems"

        /// The most elements allowed, which `.maximumCount` and `.count` become.
        public static let maxItems: Self = "maxItems"

        /// The fewest characters allowed.
        public static let minLength: Self = "minLength"

        /// The most characters allowed.
        public static let maxLength: Self = "maxLength"

        /// A pattern the text must match, which `.pattern` becomes.
        public static let pattern: Self = "pattern"

        /// The keyword's name in JSON Schema.
        public let rawValue: String

        /// Creates a keyword from its name in JSON Schema.
        ///
        /// - Parameter rawValue: The name, such as `"minimum"`.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

/// The values of a guided answer that break guides of its schema: the `underlyingError` of the
/// `GeneratedContent.ParsingError` that the answer throws.
public struct GuideViolations: Error, Sendable, Equatable, CustomStringConvertible {
    /// Each value that breaks a guide, in the order of the answer.
    public let violations: [GuideViolation]

    package init(_ violations: [GuideViolation]) {
        self.violations = violations
    }

    /// Each violation, such as `minutes is 2, below the minimum of 5`, separated by semicolons.
    public var description: String {
        violations.map(\.description).joined(separator: "; ")
    }
}

extension GuideViolations {
    /// Checks an answer's text against the guides of the request's schema.
    ///
    /// A schema that can't be encoded passes, and so does a response that isn't JSON when the schema's root isn't an
    /// object or an array, such as a string Foundation Models decodes from plain text.
    ///
    /// - Parameters:
    ///   - responseText: The text of the answer's response entry, or empty when the answer ended in tool calls.
    ///   - schema: The request's schema.
    ///   - id: The request's id, whose start names the request in the log.
    /// - Throws: `GeneratedContent.ParsingError`, naming each value that breaks a guide, with the ``GuideViolations``
    ///   as its `underlyingError`, when one does, or when an object or array answer isn't complete JSON, since
    ///   decoding would fill in what's missing.
    package static func check(_ responseText: String, against schema: GenerationSchema, request id: UUID) throws {
        guard !responseText.isEmpty, let json = try? JSONValue(schema, strict: true) else { return }
        guard let answer = try? JSONValue(json: Data(responseText.utf8)) else {
            guard let root = json["type"]?.stringValue, [JSONValue.SchemaType.object, JSONValue.SchemaType.array].contains(root)
            else { return }
            throw GeneratedContent.ParsingError(rawContent: responseText, debugDescription: "The answer isn't complete JSON.")
        }
        let violations = answer.violations(of: json)
        guard !violations.isEmpty else { return }
        // The log names where each value is and the guide it breaks, never the value, which is part of the answer.
        let places = violations.map { "\($0.path.isEmpty ? "the answer" : $0.path) (\($0.keyword))" }.joined(separator: ", ")
        let request = LanguageModelsLogging.requestName(id)
        PackageLogger.languageModels(.error)?.error(
            "Request \(request, privacy: .public): the answer breaks its schema's guides at \(places, privacy: .public).")
        throw GeneratedContent.ParsingError(
            rawContent: responseText, underlyingError: GuideViolations(violations),
            debugDescription: "The answer breaks its schema's guides: \(GuideViolations(violations)).")
    }
}
