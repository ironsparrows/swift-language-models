import Foundation
package import FoundationModels
import LanguageModelsCore

/// Foundation Models' sampling options as the settings a provider sends.
package struct Sampling {
    package var temperature: Double?
    package var topP: Double?
    package var topK: Int?
    package var seed: UInt64?
    /// Whether the options ask for greedy sampling, which a provider may also send as `top_k` 1 where it rules out no
    /// host.
    package var isGreedy = false

    /// Greedy sampling becomes temperature 0. Temperatures are clamped to the provider's range, and probability
    /// thresholds to 0 to 1.
    ///
    /// - Parameters:
    ///   - options: The request's generation options.
    ///   - temperatureRange: The temperatures the provider takes, such as 0 to 2.
    package init(_ options: GenerationOptions, temperatureRange: ClosedRange<Double>) {
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
    package static func json(seed: UInt64) -> JSONValue {
        let folded = seed & UInt64(Int64.max)
        return Int(exactly: folded).map(JSONValue.integer) ?? .largeInteger(Decimal(folded))
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
