/// A change a request makes to what the app asked for, so that its models and the provider take it.
///
/// Each one is likely a mistake in the app, so the request logs it.
package enum RequestAdjustment: Equatable, Sendable {
    /// Settings left out because the model, or a fallback when the request has one, doesn't list their parameters, by
    /// key, in the order the body has them.
    case unlistedParameters([String])

    /// Request metadata left out, by key: pairs past the limits of 16 pairs, 64-character keys and 512-character
    /// values, and pairs whose value isn't a string.
    case droppedMetadata(keys: [String])

    /// A reasoning level sent as another effort, the nearest that every model accepts, or left out when no effort
    /// they accept is near it.
    case movedEffort(requested: String, sent: String?)

    /// Settings the request doesn't send, by the names the format gives them: ones the format has no member for, such
    /// as a `seed`, and ones the provider doesn't take with the request's other settings, such as `temperature` while a
    /// model reasons.
    case unsentSettings([String])

    /// A token limit below the fewest output tokens the provider takes, sent as that fewest instead.
    case raisedTokenLimit(requested: Int, sent: Int)

    /// The adjustments in the order the log reports them: settings left out, then the token limit, then metadata, then
    /// the reasoning effort, each kind in the order the request made them.
    ///
    /// - Parameter adjustments: The request's adjustments, in the order it made them.
    /// - Returns: The same adjustments, in the log's order.
    package static func inLogOrder(_ adjustments: [RequestAdjustment]) -> [RequestAdjustment] {
        (0...3).flatMap { rank in adjustments.filter { $0.logRank == rank } }
    }

    /// The adjustment's place in the log.
    private var logRank: Int {
        switch self {
        case .unlistedParameters, .unsentSettings: 0
        case .raisedTokenLimit: 1
        case .droppedMetadata: 2
        case .movedEffort: 3
        }
    }
}
extension RequestAdjustment {
    /// What the request changed, for the log, without the metadata's keys, which the app may have made from personal
    /// data.
    ///
    /// - Parameters:
    ///   - model: The id of the model the request names first.
    ///   - provider: The provider's name, such as `OpenRouter`.
    /// - Returns: A sentence that names the model.
    package func message(model: String, provider: String) -> String {
        switch self {
        case .unlistedParameters(let parameters):
            return """
                The request to \(model) leaves out \(parameters.joined(separator: ", ")), which the model, or a fallback when the \
                request has one, doesn't list.
                """
        case .droppedMetadata:
            return """
                The request to \(model) leaves out metadata that \(provider) doesn't take: values that aren't strings, and \
                pairs past its limits of 16 pairs, keys up to 64 characters and values up to 512.
                """
        case .movedEffort(let requested, let sent?):
            return "The request to \(model) sends the reasoning level \(requested) as \(sent), the nearest effort its models accept."
        case .movedEffort(let requested, nil):
            return "The request to \(model) leaves out the reasoning level \(requested), since its models accept no effort near it."
        case .unsentSettings(let settings):
            return
                "The request to \(model) leaves out \(settings.joined(separator: ", ")), which \(provider) doesn't take for this request."
        case .raisedTokenLimit(let requested, let sent):
            return "The request to \(model) sends a token limit of \(sent), the fewest \(provider) takes, instead of \(requested)."
        }
    }

    /// The runtime warning: the message, and the keys of metadata left out, which the warning's log entry keeps
    /// private.
    ///
    /// - Parameters:
    ///   - model: The id of the model the request names first.
    ///   - provider: The provider's name, such as `OpenRouter`.
    /// - Returns: The message, and the keys after it.
    package func warning(model: String, provider: String) -> String {
        guard case .droppedMetadata(let keys) = self else { return message(model: model, provider: provider) }
        return "\(message(model: model, provider: provider)) Keys: \(keys.joined(separator: ", "))."
    }
}
