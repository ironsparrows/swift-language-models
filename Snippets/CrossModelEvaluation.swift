// snippet.hide
import Evaluations
import Foundation
import FoundationModels
import OpenRouterLanguageModels
import Testing

// snippet.show
// snippet.feature
@Generable
enum Cuisine: String, Codable {
    case italian, japanese, mexican, indian
}

/// Tells which cuisine a recipe comes from.
func cuisine(of recipe: String, using model: some LanguageModel) async throws -> Cuisine {
    let session = LanguageModelSession(model: model, instructions: "Name the cuisine that a recipe comes from.")
    return try await session.respond(to: recipe, generating: Cuisine.self).content
}
// snippet.end

// snippet.evaluation
struct CuisineEvaluation: Evaluation {
    let model: any LanguageModel
    let modelID: String

    /// Labels the run in Xcode. A slash would make `swift test` name the results file `untitled`.
    var name: String { "Cuisine (\(modelID.replacing("/", with: "-")))" }

    let correct = Metric("Correct")

    var dataset: ArrayLoader<ModelSample<Cuisine>> {
        ArrayLoader(samples: [
            ModelSample(prompt: "Risotto with porcini and parmesan.", expected: .italian),
            ModelSample(prompt: "Miso soup with tofu and wakame.", expected: .japanese),
            ModelSample(prompt: "Tacos al pastor with pineapple.", expected: .mexican),
            ModelSample(prompt: "Chana masala with basmati rice.", expected: .indian),
        ])
    }

    func subject(from sample: ModelSample<Cuisine>) async throws -> ModelSubject<Cuisine> {
        ModelSubject(value: try await cuisine(of: sample.promptDescription, using: model))
    }

    var evaluators: Evaluators {
        Evaluator { sample, subject in
            subject.value == sample.expected
                ? correct.passing()
                : correct.failing(rationale: "Answered \(subject.value.rawValue).")
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: correct)
    }
}
// snippet.end

// snippet.tests
@Suite struct CuisineEvaluations {
    static let onDevice = CuisineEvaluation(model: SystemLanguageModel.default, modelID: "apple-on-device")

    static let openRouter = CuisineEvaluation(
        model: OpenRouterLanguageModel(
            .openaiGpt5_4Nano,
            auth: .apiKey { ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? "" }
        ),
        modelID: OpenRouterModel.openaiGpt5_4Nano.id.rawValue
    )

    @Test(
        .enabled(if: SystemLanguageModel.default.isAvailable, "Apple Intelligence isn't available."),
        .evaluates(
            Self.onDevice,
            info: ["model": Self.onDevice.modelID, "os": ProcessInfo.processInfo.operatingSystemVersionString]
        )
    )
    func onDeviceModel() {
        check(EvaluationContext.current.result, of: Self.onDevice)
    }

    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] != nil, "Set OPENROUTER_API_KEY."),
        .evaluates(Self.openRouter, info: ["model": Self.openRouter.modelID])
    )
    func openRouterModel() {
        check(EvaluationContext.current.result, of: Self.openRouter)
    }

    private func check(_ result: EvaluationResult, of evaluation: CuisineEvaluation) {
        #expect(result.errors.inferenceFailureCount == 0, "Failed samples are left out of the score.")
        #expect(result.aggregateValue(.mean(of: evaluation.correct)) >= 0.75)
    }
}
// snippet.end
