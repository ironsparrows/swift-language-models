// snippet.hide
import Evaluations
import Foundation
import FoundationModels
import OpenRouterLanguageModels
import Testing

// snippet.show
// snippet.models
/// The key for live runs, read from the environment for every request. Tests without it skip themselves.
nonisolated var openRouterKey: String? { ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] }

/// Credits the evaluation's requests to an app of their own, apart from the shipping app's.
let evaluationApp = OpenRouterApp(
    name: "Meal Planner evaluations",
    url: URL(string: "https://evals.example.com"),
    isHidden: true
)

/// The model the feature ships with: OpenAI's GPT-5.4 mini.
let recipeModel = OpenRouterLanguageModel(.openaiGpt5_4Mini, app: evaluationApp, auth: .apiKey { openRouterKey ?? "" })

/// A larger model from another family, Anthropic's, to judge it.
let judge = OpenRouterLanguageModel(.anthropicClaudeSonnet5_5, app: evaluationApp, auth: .apiKey { openRouterKey ?? "" })
// snippet.end

// snippet.hide
func checkJudge() {
    // snippet.show
    // snippet.capabilities
    let ratesWithSchema = judge.capabilities.contains(.guidedGeneration)  // true: it lists `structured_outputs`
    // snippet.end
    // snippet.hide
    _ = ratesWithSchema
}

// snippet.show
// snippet.evaluation
struct RecipeEvaluation: Evaluation {
    static let usefulness = ScoreDimension(
        "Usefulness",
        description: "Whether someone could cook the recipe tonight for what they asked.",
        scale: .numeric([
            4: "A recipe for exactly what was asked, with every ingredient's amount and every step.",
            3: "A complete recipe that strays from part of the request.",
            2: "A recipe that leaves out amounts or steps.",
            1: "Not a recipe for what was asked.",
        ])
    )
    static let clarity = ScoreDimension(
        "Clarity",
        description: "How easy the steps are to follow while cooking.",
        scale: .numeric([
            4: "Numbered steps in cooking order, one action each.",
            3: "Steps in cooking order, some with several actions.",
            2: "Steps out of order, or run together in a paragraph.",
            1: "No steps a cook could follow.",
        ])
    )

    let model: any LanguageModel
    let judge: any LanguageModel

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: [
            ModelSample(prompt: "Something with lentils.", expected: "A lentil dish, such as a soup or a dal."),
            ModelSample(prompt: "A quick vegan breakfast.", expected: "A vegan breakfast ready in 15 minutes."),
        ])
    }

    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        let session = LanguageModelSession(model: model, instructions: "Suggest one recipe.")
        return ModelSubject(value: try await session.respond(to: sample.prompt).content)
    }

    var evaluators: Evaluators {
        // One judge call per sample scores both dimensions.
        ModelJudgeEvaluator(
            judge: judge,
            dimensions: [Self.usefulness, Self.clarity],
            prompt: ModelJudgePrompt(reference: { sample, _ in ["A good answer": sample.expected ?? ""] })
        )
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.usefulness.metric)
        aggregator.computeMean(of: Self.clarity.metric)
    }
}
// snippet.end

// snippet.test
@Test(
    .enabled(if: openRouterKey != nil, "Set OPENROUTER_API_KEY to run this test"),
    .evaluates(
        RecipeEvaluation(model: recipeModel, judge: judge),
        info: ["model": recipeModel.details.id.rawValue, "judge": judge.details.id.rawValue, "prompt": "v1"]
    )
)
func recipesAreUseful() {
    let result = EvaluationContext.current.result
    // A sample whose request failed is left out of the scores, so a run with failures measured less.
    #expect(result.errors.inferenceFailureCount == 0)
    #expect(result.aggregateValue(.mean(of: RecipeEvaluation.usefulness.metric)) >= 3)
}
// snippet.end

// snippet.hide
func pairwise() {
    // snippet.show
    // snippet.pairwise
    // Each sample's expected value is the baseline to beat, such as the shipping prompt's answer, saved earlier.
    let preference = ModelJudgeEvaluator<ModelSample<String>>.pairwise(
        "Preference",
        scale: .numeric([
            4: "The response is a much better recipe for the request than the baseline.",
            3: "The response is a slightly better recipe than the baseline.",
            2: "The baseline is a slightly better recipe than the response.",
            1: "The baseline is a much better recipe than the response.",
        ]),
        judge: judge
    )
    // snippet.end
    // snippet.hide
    _ = preference
}

/// Looks up the person's saved recipes.
struct FindSavedRecipes: Tool {
    let name = "findSavedRecipes"
    let description = "Finds the person's saved recipes that use an ingredient."

    @Generable
    struct Arguments {
        @Guide(description: "The ingredient to look for.")
        var ingredient: String
    }

    func call(arguments: Arguments) async throws -> String {
        "Red lentil soup; Lentil and spinach dal."
    }
}

// snippet.show
// snippet.toolCalls
struct SavedRecipeEvaluation: Evaluation {
    let model: any LanguageModel
    let argumentMatcher: any LanguageModel

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: [
            ModelSample(
                prompt: "What can I make from my saved lentil recipes?",
                expectations: TrajectoryExpectation(
                    expected: "findSavedRecipes",
                    arguments: [.naturalLanguage(argumentName: "ingredient", criteria: "Names lentils.")]
                )
            )
        ])
    }

    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        let session = LanguageModelSession(
            model: model,
            tools: [FindSavedRecipes()],
            instructions: "Help the person cook from their saved recipes."
        )
        let response = try await session.respond(to: sample.prompt)
        return ModelSubject(value: response.content, transcript: session.transcript.structuredTranscript)
    }

    var evaluators: Evaluators {
        ToolCallEvaluator(
            allPass: .toolsAllPass,
            percentagePass: .toolsPercentagePass,
            argumentMatchModel: argumentMatcher
        )
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: .toolsAllPass)
        aggregator.computeMean(of: .toolsPercentagePass)
    }
}
// snippet.end

// snippet.serverTools
/// An answer, with the number of web searches OpenRouter ran for it.
struct SearchedAnswer: Codable, Sendable {
    var text: String
    var webSearches: Int
}

struct WeekendEvaluation: Evaluation {
    static let searched = Metric("Searched")

    /// A model with `.webSearch()` in its server tools.
    let model: any LanguageModel
    // snippet.hide

    var dataset: ArrayLoader<ModelSample<SearchedAnswer>> {
        ArrayLoader(samples: [
            ModelSample(prompt: "Which food markets are open in Athens this weekend?", expected: nil)
        ])
    }
    // snippet.show

    func subject(from sample: ModelSample<SearchedAnswer>) async throws -> ModelSubject<SearchedAnswer> {
        let response = try await LanguageModelSession(model: model).respond(to: sample.prompt)
        let searches = response.usage.openRouter.webSearchCount ?? 0
        return ModelSubject(value: SearchedAnswer(text: response.content, webSearches: searches))
    }

    var evaluators: Evaluators {
        Evaluator { _, subject in
            subject.value.webSearches > 0
                ? Self.searched.passing()
                : Self.searched.failing(rationale: "It answered without a web search.")
        }
    }
    // snippet.hide

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.searched)
    }
    // snippet.show
}
// snippet.end

// snippet.hide
func generateSamples() async throws {
    // snippet.show
    // snippet.generator
    let seeds = [
        ModelSample(prompt: "Something with lentils.", expected: "A lentil dish, such as a soup or a dal."),
        ModelSample(prompt: "A quick vegan breakfast.", expected: "A vegan breakfast ready in 15 minutes."),
    ]
    let writer = OpenRouterLanguageModel(.googleGemini3_5Flash, app: evaluationApp, auth: .apiKey { openRouterKey ?? "" })
    let generator = SampleGenerator<ModelSample<String>>(
        Prompt("Write more requests like these, each with what a good answer to it is."),
        samples: seeds,
        targetCount: 30,
        sessionProvider: {
            // Called again for a fresh session when one runs out of context, so the instructions stand alone.
            LanguageModelSession(
                model: writer,
                instructions: """
                    You write test requests for a meal-planning app. A person types one short request into its recipe \
                    box, and the app suggests one recipe. Each request names a dish, an ingredient, a diet or a time \
                    limit. Its expected value says in one sentence what a good recipe for it is.
                    """
            )
        },
        validator: { sample in sample.promptDescription.count <= 120 }
    )

    for try await sample in generator.run() {
        print(sample.promptDescription)
    }
    print("\(await generator.invalidSamples.count) samples broke the validator's rule.")
    // snippet.end
    // snippet.hide
}
