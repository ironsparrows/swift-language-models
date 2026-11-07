# Judging and generating samples with OpenAI models

Rate a feature's answers, check its tool arguments and grow its dataset with OpenAI's models.

## Overview

Apple's [Evaluations](https://developer.apple.com/documentation/evaluations) framework measures how well a feature
built on a language model does its job. It takes a model in three places: a `ModelJudgeEvaluator` rates answers with
a judge model, a `ToolCallEvaluator` checks tool calls, with an argument-match model for arguments described in words,
and a `SampleGenerator` writes new samples with the model of a session it's given. Each takes any `LanguageModel`, so an
``OpenAILanguageModel`` fits in any of them, whether the feature runs on Apple's on-device model, on OpenAI or on
another provider.

The evaluation's models get a project of their own, which keeps their usage apart from the shipping app's in OpenAI's
usage dashboard:

@Snippet(path: "swift-language-models/Snippets/OpenAIJudging", slice: "models")

Running one evaluation against several models, labeling the runs and reading the results is in
<doc:/LanguageModels/EvaluatingAcrossModels>.

### Pick a judge

Apple's advice is a judge at least as capable as the model under test, from another model family: models tend to rate
their own family's answers higher, and a stronger judge weighs substance over style. So a model never judges its own
family. For a feature on Apple's on-device model or another vendor's model, an OpenAI model judges, as here; for a
feature on an OpenAI model, a model from another vendor does, through its own provider module.

The judge returns its rating as a score from the scale and a rationale. With a model whose
``OpenAILanguageModel/capabilities`` include `.guidedGeneration`, which an OpenAI model has when it lists
`structured_outputs`, the judge sends a schema, and OpenAI holds the answer to it. Without it, the judge's prompt asks
for the rating as JSON text, and a reply that doesn't decode counts as an evaluator failure, so pick a judge with
`.guidedGeneration`:

@Snippet(path: "swift-language-models/Snippets/OpenAIJudging", slice: "capabilities")

Run a new judge on a few samples and read its rationales before a full run; `judgePrompt(for:output:)` shows the
prompt the judge gets.

Always pass `judge:`. Without it, a `ModelJudgeEvaluator` uses `SystemLanguageModel()`, Apple's on-device model, which
goes against that advice when it judges a larger remote model, and isn't available on every Mac or CI machine.

Keep the judge the same from run to run, as the model under test: a dated snapshot rather than the name it belongs
to, and the same reasoning level, so the same model rates every sample. <doc:RepeatableRuns> describes how.

### Write the scale and the dimensions

- Use an even scale, such as 1 to 4, so the judge can't settle on a middle score, and describe at each level what an
  answer shows rather than a degree such as "good" or "very good". A check with one right answer takes
  `.passFail(passDescription:failDescription:)`, and levels of your own take a `ScoreLevel` type through `.custom(_:)`.
- Split a broad question into `ScoreDimension` values that each ask one thing. One judge call scores all the
  dimensions of an evaluator, and Apple suggests three or four in a call.
- A `ModelJudgePrompt` tells the judge what it needs to know: `reference` returns labeled facts, such as the sample's
  expected value, and `instructions` replaces the default instructions rather than adding to them.
- Read the rationales: a judge may be following a level written too broadly.

A test that runs the evaluation skips itself without the key, and checks the run's errors as well as its scores,
because a sample whose request fails is left out of the scores. `swift test` passes the environment to tests as it
is, while `xcodebuild test` needs a `TEST_RUNNER_` prefix, as <doc:/LanguageModels/EvaluatingAcrossModels> describes.

### Compare two answers

`ModelJudgeEvaluator.pairwise` asks the judge which of two answers is better: the subject's, or the baseline in the
sample's expected value, such as the answer of the shipping prompt or model, saved earlier. A judge may favor whichever
answer it reads first. Apple suggests judging both orders and trusting only the verdicts that agree, which takes a
second evaluation with the two answers swapped.

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
`ToolCallEvaluator(allPass:percentagePass:argumentMatchModel:)` names that model, such as an OpenAI model. An answer's
parallel tool calls are one round in the transcript, as ``OpenAIOptions/parallelToolCalls`` allows them.

### Generate samples

`SampleGenerator` writes samples like the seeds it's given, in batches of up to ten for each model call, until the
dataset reaches `targetCount`, which counts the seeds. With a `sessionProvider`, it uses the model and instructions of
the session it returns, such as one on an OpenAI model.

The generator calls `sessionProvider` when it starts, and again whenever the session runs out of context. The new session
knows nothing of the earlier exchange, so its instructions stand alone: what the feature does, what a sample holds and
the rules each sample follows. A validator rejects samples that break a rule, and `invalidSamples` keeps them for
review. A validator checks one sample at a time, so it can't catch near-duplicates or a lopsided mix; read the
accepted samples too.

### Budget for the runs

Every request is billed: the subject's requests for each sample, a judge call for each judge evaluator on each sample,
the argument-match model's calls and the generator's calls. A judge that reasons also bills its reasoning tokens, so a
low reasoning level keeps a judge's runs cheaper where it rates as well. Start with a golden set of 10 to 20 samples,
as Apple's
[Designing effective evaluations](https://developer.apple.com/documentation/evaluations/designing-effective-evaluations)
suggests, and grow it to 30 to 50 once the evaluation measures what it should.

The evaluators keep the answers of the judge and the argument-match model to themselves, so their usage never reaches
your code. A project of their own, as above, shows it in OpenAI's usage dashboard instead. A subject's own usage is in
its answer's usage, which <doc:RepeatableRuns> records for each sample.

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
