import Foundation
import FoundationModels
import LanguageModelsCore

// MARK: - Sampling

/// Foundation Models' sampling options as the settings a provider sends.
package struct Sampling {
    var temperature: Double?
    var topP: Double?
    package var topK: Int?
    var seed: UInt64?
    /// Whether the options ask for greedy sampling, which a provider may also send as `top_k` 1 where it rules out no
    /// host.
    package var isGreedy = false

    /// Greedy sampling becomes temperature 0. Temperatures are clamped to the provider's range, and probability
    /// thresholds to 0 to 1.
    ///
    /// - Parameters:
    ///   - options: The request's generation options.
    ///   - temperatureRange: The temperatures the provider takes, such as 0 to 2.
    init(_ options: GenerationOptions, temperatureRange: ClosedRange<Double>) {
        temperature = options.temperature.map { $0.clamped(to: temperatureRange) }
        switch options.samplingMode?.kind {
        case .greedy?:
            temperature = 0
            isGreedy = true
        case .randomTopK(let k, let seed)?:
            topK = k
            self.seed = seed
        case .randomProbabilityThreshold(let threshold, let seed)?:
            topP = threshold.clamped(to: 0...1)
            self.seed = seed
        case nil:
            break
        @unknown default:
            break
        }
    }
}

extension Sampling {
    /// A seed as a number that hosts read as a signed 64-bit integer. A seed of 2^63 or more loses its top bit, so
    /// every seed is sent, and each one as the same number on every platform.
    static func json(seed: UInt64) -> JSONValue {
        let folded = seed & UInt64(Int64.max)
        return Int(exactly: folded).map(JSONValue.integer) ?? .largeInteger(Decimal(folded))
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Tool choice

extension GenerationOptions.ToolCallingMode {
    /// Whether the model may or must call the session's tools, as OpenAI's formats spell it in `tool_choice`, or `nil`
    /// for a kind the formats have no word for.
    var toolChoice: JSONValue? {
        let choice: ToolChoice? =
            switch kind {
            case .allowed: .auto
            case .required: .required
            case .disallowed: ToolChoice.none
            @unknown default: nil
            }
        return choice?.json
    }
}

/// Whether the model may or must call the session's tools, as `tool_choice` spells it.
private struct ToolChoice: ProviderVocabulary {
    static let auto: Self = "auto"
    static let required: Self = "required"
    static let none: Self = "none"

    let rawValue: String
}

// MARK: - Metadata

/// Request metadata as OpenAI's formats take it.
enum RequestMetadata {
    /// The limits that OpenAI's formats, and the hosts that follow them, put on request metadata.
    fileprivate enum MetadataLimit {
        static let pairs = 16
        static let keyLength = 64
        static let valueLength = 512
    }

    /// A request's string metadata, sorted by key, within the limits of 16 pairs, keys up to 64 characters and values
    /// up to 512. Pairs past the limits are left out, since a host rejects the whole request for them.
    ///
    /// - Returns: The metadata to send, or `nil` when none is left, and the keys of the pairs left out, sorted.
    static func limited(_ metadata: [String: GeneratedContent]) -> (json: JSONValue?, droppedKeys: [String]) {
        let members = metadata.compactMap { key, value -> JSONObject.Member? in
            guard key.count <= MetadataLimit.keyLength, case .string(let text) = value.kind, text.count <= MetadataLimit.valueLength
            else { return nil }
            return .init(key: key, value: .string(text))
        }
        let limited = JSONObject(members).sortedByKey().members.prefix(MetadataLimit.pairs)
        let keptKeys = Set(limited.map(\.key))
        let droppedKeys = metadata.keys.filter { !keptKeys.contains($0) }.sorted()
        return (limited.isEmpty ? nil : .object(JSONObject(Array(limited))), droppedKeys)
    }
}

// MARK: - Body

/// What a request sends, and what it changed from what the app asked for.
struct RequestBody {
    /// The body of the request's `POST`.
    let json: JSONValue

    /// The same body with its response schema in portable form, to send instead when a host rejects a constraint of the
    /// full schema, or `nil` when there's no other schema to try.
    let portableJSON: JSONValue?

    /// What the request leaves out or changes from what the app asked for, so that its models and the provider take it,
    /// in the log's order.
    let adjustments: [RequestAdjustment]
}

extension JSONObject {
    /// Adds a provider's members to a body the format wrote. A member the format wrote stays as it is.
    ///
    /// - Parameters:
    ///   - members: The provider's members.
    ///   - provider: The provider's name, which a debug build's assertion names.
    mutating func add(_ members: JSONObject, from provider: String) {
        for member in members.members {
            assert(self[member.key] == nil, "\(provider) adds \(member.key), which the format writes.")
            if self[member.key] == nil { self[member.key] = member.value }
        }
    }
}

// MARK: - Adjustments

/// A change a request makes to what the app asked for, so that its models and the provider take it.
///
/// Each one is likely a mistake in the app, so the request logs it.
enum RequestAdjustment: Equatable, Sendable {
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
    static func inLogOrder(_ adjustments: [RequestAdjustment]) -> [RequestAdjustment] {
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
    func message(model: String, provider: String) -> String {
        switch self {
        case .unlistedParameters(let parameters):
            return """
                The request to \(model) leaves out \(parameters.joined(separator: ", ")), which the model, or a fallback when the \
                request has one, doesn't list.
                """
        case .droppedMetadata:
            let limit = RequestMetadata.MetadataLimit.self
            return """
                The request to \(model) leaves out metadata that \(provider) doesn't take: values that aren't strings, and \
                pairs past its limits of \(limit.pairs) pairs, keys up to \(limit.keyLength) characters and values up to \
                \(limit.valueLength).
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
    func warning(model: String, provider: String) -> String {
        guard case .droppedMetadata(let keys) = self else { return message(model: model, provider: provider) }
        return "\(message(model: model, provider: provider)) Keys: \(keys.joined(separator: ", "))."
    }
}
