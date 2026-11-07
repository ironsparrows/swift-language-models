import Foundation
import FoundationModels
import LanguageModels
import Testing

@Suite("Sampling")
struct SamplingTests {
    @Test func `greedy sampling is temperature 0 alone`() {
        let sampling = Sampling(GenerationOptions(samplingMode: .greedy, temperature: 0.7), temperatureRange: 0...2)

        #expect(sampling.temperature == 0)
        #expect(sampling.topK == nil)
        #expect(sampling.topP == nil)
        #expect(sampling.seed == nil)
    }

    @Test func `random sampling keeps its own settings and seed`() {
        let topK = Sampling(GenerationOptions(samplingMode: .random(top: 40, seed: 7)), temperatureRange: 0...2)
        let topP = Sampling(GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9, seed: 8)), temperatureRange: 0...2)

        #expect(topK.topK == 40)
        #expect(topK.seed == 7)
        #expect(topP.topP == 0.9)
        #expect(topP.seed == 8)
    }

    @Test(arguments: [(-1.0, 0.0), (0.4, 0.4), (3, 2)])
    func `a temperature is clamped to 0 through 2`(requested: Double, sent: Double) {
        #expect(Sampling(GenerationOptions(temperature: requested), temperatureRange: 0...2).temperature == sent)
    }

    @Test(arguments: [(-0.5, 0.0), (1.5, 1.0)])
    func `a probability threshold is clamped to 0 through 1`(requested: Double, sent: Double) {
        let sampling = Sampling(GenerationOptions(samplingMode: .random(probabilityThreshold: requested)), temperatureRange: 0...2)

        #expect(sampling.topP == sent)
    }

    @Test(arguments: [(UInt64(42), JSONValue.integer(42)), (1 << 63, .integer(0)), (.max, .integer(Int(Int64.max)))])
    func `a seed is sent as a signed 64-bit number, without its top bit`(seed: UInt64, sent: JSONValue) {
        #expect(Sampling.json(seed: seed) == sent)
    }
}
