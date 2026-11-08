# Judging and generating samples with OpenRouter models

Rate a feature's answers, check its tool arguments and grow its dataset with models on OpenRouter.

## Overview

Apple's [Evaluations](https://developer.apple.com/documentation/evaluations) framework measures how well a feature
built on a language model does its job. It takes a model in three places: a `ModelJudgeEvaluator` rates answers with
a judge model, a `ToolCallEvaluator` checks tool calls, with an argument-match model for arguments described in words,
and a `SampleGenerator` writes new samples with the model of a session it's given. Each takes any `LanguageModel`, so an
``OpenRouterLanguageModel`` fits in any of them, whether the feature runs on Apple's on-device model, on OpenRouter or
on another provider.

The examples here evaluate the recipes a meal planner suggests with GPT-5 mini. The evaluation's models get an app of
their own, which keeps their usage apart from the shipping app's:

@Snippet(path: "swift-language-models/Snippets/Judging", slice: "models")

Running one evaluation against several models, labeling the runs and reading the results is in
<doc:/LanguageModels/EvaluatingAcrossModels>.

### Pick a judge

Apple's advice is a judge at least as capable as the model under test, from another model family: models tend to rate
their own family's answers higher, and a stronger judge weighs substance over style. So a model never judges its own
family. For a feature on GPT-5 mini, a Claude model judges, as here; for a feature on Claude, a model from another
vendor does.

The judge returns its rating as a score from the scale and a rationale. With a model whose
``OpenRouterLanguageModel/capabilities`` include `.guidedGeneration`, which an OpenRouter model has when it lists
`structured_outputs`, the judge sends a schema, and the host holds the answer to it. Without it, the judge's prompt
asks for the rating as JSON text, and a reply that doesn't decode counts as an evaluator failure, so pick a judge with
`.guidedGeneration`.

@Snippet(path: "swift-language-models/Snippets/Judging", slice: "capabilities")

It isn't guaranteed that every model and host accepts the judge's schema. Run a new judge on a few samples and read
its rationales before a full run; `judgePrompt(for:output:)` shows the prompt the judge gets.

Always pass `judge:`. Without it, a `ModelJudgeEvaluator` uses `SystemLanguageModel()`, Apple's on-device model, which
goes against that advice when it judges a larger remote model, and isn't available on every Mac or CI machine.

Keep the judge the same from run to run, as the model under test: a catalog model rather than an alias, and no
fallbacks, so the same model rates every sample. <doc:RepeatableRuns> describes how.

### Write the scale and the dimensions

- Use an even scale, such as 1 to 4, so the judge can't settle on a middle score, and describe at each level what an
  answer shows rather than a degree such as "good" or "very good". A check with one right answer takes
  `.passFail(passDescription:failDescription:)`, and levels of your own take a `ScoreLevel` type through `.custom(_:)`.
- Split a broad question into `ScoreDimension` values that each ask one thing. One judge call scores all the
  dimensions of an evaluator, and Apple suggests three or four in a call.
- A `ModelJudgePrompt` tells the judge what it needs to know: `reference` returns labeled facts, such as the sample's
  expected value, and `instructions` replaces the default instructions rather than adding to them.
- Read the rationales: a judge may be following a level written too broadly.

@Snippet(path: "swift-language-models/Snippets/Judging", slice: "evaluation")

A test runs the evaluation. It skips itself without the key, and `.enabled(if:)` is checked before any test runs, so
a skipped test sends no requests. It checks the run's errors as well as its scores, because a sample whose request
fails is left out of the scores:

@Snippet(path: "swift-language-models/Snippets/Judging", slice: "test")

`swift test` passes the environment to tests as it is, while `xcodebuild test` needs a `TEST_RUNNER_` prefix, as
<doc:/LanguageModels/EvaluatingAcrossModels>
describes.

### Compare two answers

`ModelJudgeEvaluator.pairwise` asks the judge which of two answers is better: the subject's, or the baseline in the
sample's expected value, such as the answer of the shipping prompt or model, saved earlier. The scale is a comparison,
and on a 1-to-4 scale a mean above 2.5 means the new answers win:

@Snippet(path: "swift-language-models/Snippets/Judging", slice: "pairwise")

A judge may favor whichever answer it reads first. Apple suggests judging both orders and trusting only the verdicts
that agree, which takes a second evaluation with the two answers swapped. A pairwise judge builds its own prompt, so a
`ModelJudgePrompt` doesn't apply to it.

### Calibrate the judge

A judge's scores mean something once they agree with people's. Two or three people score 20 to 50 answers on the same
scale, the judge scores the same answers, and the levels or instructions change where the two disagree. Agreement is
measured with Cohen's kappa rather than the share of equal scores, which misleads when most answers get the same
score, and Apple's Book Tracker sample trusts a judge from a kappa above 0.6. A calibration holds for the judge model
and the prompt it measured, so it's done again when either changes.

### Check tool calls

`ToolCallEvaluator` compares the tool calls in the transcript that the subject returns with each sample's
`TrajectoryExpectation`, so the subject returns its session's `transcript.structuredTranscript`. A `naturalLanguage`
matcher asks a model whether an argument meets its criteria, and
`ToolCallEvaluator(allPass:percentagePass:argumentMatchModel:)` names that model. It's the only initializer on watchOS;
the other one leaves the model to the framework.

@Snippet(path: "swift-language-models/Snippets/Judging", slice: "toolCalls")

OpenRouter runs its server tools, such as a web search, within the request, so they never become tool calls in the
transcript and `ToolCallEvaluator` can't check them. The answer's usage counts them instead:
``OpenRouterUsageMetadata/requestedServerToolCallCount``, ``OpenRouterUsageMetadata/executedServerToolCallCount`` and
``OpenRouterUsageMetadata/webSearchCount``. To check them, the subject returns them in its value, and a code evaluator
scores them:

@Snippet(path: "swift-language-models/Snippets/Judging", slice: "serverTools")

### Generate samples

`SampleGenerator` writes samples like the seeds it's given, in batches of up to ten for each model call, until the
dataset reaches `targetCount`, which counts the seeds. Without a `sessionProvider`, it uses a default model;
with one, the model and instructions of the session it returns.

The generator calls `sessionProvider` when it starts, and again whenever the session runs out of context. The new
session knows nothing of the earlier session, so its instructions stand alone: what the feature does, what a sample
holds and the rules each sample follows. For samples with tool expectations, they also name each tool and when it's
called, since the generator's model doesn't know them.

A validator rejects samples that break a rule, and `invalidSamples` keeps them for review:

@Snippet(path: "swift-language-models/Snippets/Judging", slice: "generator")

A validator checks one sample at a time, so it can't catch near-duplicates or a lopsided mix; read the accepted samples
too.

### Budget for the runs

Every request is billed: the subject's requests for each sample, a judge call for each judge evaluator on each sample,
the argument-match model's calls and the generator's calls. Apple's examples run their judges and generators on
Apple's own models, which have no per-token price, so they leave cost out. Start with a golden set of 10 to 20
samples, as Apple's
[Designing effective evaluations](https://developer.apple.com/documentation/evaluations/designing-effective-evaluations)
suggests, and grow it to 30 to 50 once the evaluation measures what it should.

The evaluators keep the answers of the judge and the argument-match model to themselves, so their usage never reaches
your code. OpenRouter tells apps apart by their URL, so an ``OpenRouterApp`` with a URL of its own, as the evaluation's
models have here, keeps their usage apart from the shipping app's in OpenRouter's analytics, and
``OpenRouterApp/isHidden`` keeps that app out of OpenRouter's public rankings. A subject's own cost is in its answer's
usage, which <doc:RepeatableRuns> records for each sample.

### Apple's guides

- [Evaluations](https://developer.apple.com/documentation/evaluations)
- [Designing datasets to test your feature](https://developer.apple.com/documentation/evaluations/designing-evaluation-datasets)
- [Designing effective model-judge evaluators](https://developer.apple.com/documentation/evaluations/designing-effective-model-judges)
- [ModelJudgeEvaluator](https://developer.apple.com/documentation/evaluations/modeljudgeevaluator),
  [ToolCallEvaluator](https://developer.apple.com/documentation/evaluations/toolcallevaluator) and
  [SampleGenerator](https://developer.apple.com/documentation/evaluations/samplegenerator)
- [Scoring with model-judge evaluators](https://developer.apple.com/documentation/evaluations/scoring-with-model-as-judge-evaluators)
- [Evaluating tool-calling behavior](https://developer.apple.com/documentation/evaluations/evaluating-tool-calling-behavior)
- [Generating synthetic datasets](https://developer.apple.com/documentation/evaluations/generating-synthetic-evaluation-datasets)
- [Book Tracker: Using Evaluations to evaluate an intelligent feature](https://developer.apple.com/documentation/evaluations/book-tracker-using-evaluations-to-evaluate-an-intelligent-feature),
  a sample with judges, synthetic data and tool-call checks
- [Meet the Evaluations framework](https://developer.apple.com/videos/play/wwdc2026/298/), from WWDC26
- [Create robust evaluations for agentic apps](https://developer.apple.com/videos/play/wwdc2026/299/), from WWDC26, on
  generating samples and checking tool calls
- [Improve your prompts by hill-climbing with Evaluations](https://developer.apple.com/videos/play/wwdc2026/335/), from
  WWDC26, on calibrating a judge
