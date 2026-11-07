/// The constraints of a response schema that some hosts reject.
package enum SchemaConstraint {
    /// Whether a host rejected a constraint of the response schema: a 400 whose message names a constraint keyword,
    /// one the portable schema moves into descriptions, and says it isn't supported, permitted or allowed. Seed sends
    /// "Keyword 'maxItems' is not supported for type 'array'", and Cohere "received non-supported constraint for type:
    /// 'array'. constraint: 'minItems'".
    ///
    /// - Parameters:
    ///   - status: The response's HTTP status.
    ///   - message: The response's error, such as its body's text.
    /// - Returns: Whether the request may go again with the portable schema.
    package static func isRejected(status: Int, message: String) -> Bool {
        guard status == 400 else { return false }
        let constraint =
            #/
            \b(minItems | maxItems | uniqueItems | minimum | maximum | exclusiveMinimum | exclusiveMaximum | multipleOf
            | minLength | maxLength | pattern)\b
            /#
        return message.contains(constraint) && message.contains(/(?i)not supported|non-supported|unsupported|not permitted|not allowed/)
    }
}
