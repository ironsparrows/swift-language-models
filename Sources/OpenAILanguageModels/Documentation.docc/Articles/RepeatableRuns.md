# Repeatable runs with OpenAI models

Keep the model and its settings the same between evaluation runs, and measure how much the answers vary.

## Overview

An evaluation compares runs: the same samples before and after a change to a prompt, or with one model and then
another. The comparison holds only when nothing else changed between the runs. A remote model's answers vary even when
the request doesn't, so a run pins what it can and measures the rest.

### What sampling settings promise

Greedy sampling picks the most likely token every time. Apple documents it as giving the same output for the same
input on its own model; a remote model makes no such promise. A seed in `.random(top:seed:)` or
`.random(probabilityThreshold:seed:)` is best effort, as Apple's documentation says, and the Responses API has no
`seed` at all.

### What a request sends

- `.greedy` sends `temperature` 0.
- `.random(probabilityThreshold:seed:)` sends `top_p`, and leaves out the seed.
- `.random(top:seed:)` sends nothing, since the Responses API has no `top_k` and no `seed`.
- A temperature sends `temperature`.

Each goes out only when the model lists `temperature` or `top_p` in ``OpenAIModel/supportedParameters``, and to a model
that reasons only while its effort is `none`, or with no level set when it can stop reasoning. So a model that reasons
at any other level, or always reasons, gets none of them, and its answers vary however the request samples. Set the
level `.off` for a model that takes `none`, so the sampling settings reach it whatever its default effort. Every setting
left out is logged, and a debug build shows a runtime warning for it. The catalog says what each model lists:

@Snippet(path: "swift-language-models/Snippets/OpenAIRepeatableRuns", slice: "parameters")

### Pin the model under test

- Name a dated snapshot, such as ``OpenAIModel/gpt5_4Mini2026_03_17``, rather than the name it belongs to, such as
  ``OpenAIModel/gpt5_4Mini``, which OpenAI may point at a newer snapshot.
- Set the reasoning level, and keep it the same from run to run. A level the model doesn't accept moves to the nearest
  one it does, and the log says so.
- Set ``OpenAIOptions/serviceTier`` rather than leaving it to OpenAI, and record the tier that served each answer, from
  ``OpenAIResponseMetadata/serviceTier`` on the entry that ends it.
- Record the model that answered each request, from ``OpenAIResponseMetadata/model``, and OpenAI's id for it, from
  ``OpenAIResponseMetadata/requestID``.

@Snippet(path: "swift-language-models/Snippets/OpenAIRepeatableRuns", slice: "pinned")

The prompt cache serves the start of a prompt, not an answer, so it changes how long a request takes and how many of
its input tokens are cached, not what the model writes. An evaluation's judge needs the same pinning, as
<doc:JudgingAndGeneratingSamples> describes.

### Record usage and latency

The subject returns what each answer counted with its value: the input, cached, output and reasoning tokens from the
response's `usage`, and the time the request took, measured around it. For a subject whose tools run, the response's
usage has only its last request, so read the session's `usage` before and after the sample instead. Code evaluators
score them, and their mean and standard deviation across the samples show how much a run uses and how steady the model
is. The package keeps no prices, so a run's cost comes from these counts and OpenAI's current prices.

### Measure the variance

Instead of asserting that two runs give the same answers, a test runs the evaluation several times and bounds the
worst run and the spread between runs. A sample whose request fails is left out of the scores rather than counted as a
failure, so the test checks each run's `errors` too.

Running one evaluation, labeling runs and comparing them across models is in
<doc:/LanguageModels/EvaluatingAcrossModels>.

### Apple's guides

- [Evaluating language model responses](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses)
- [Designing specific, measurable criteria in an evaluation suite](https://developer.apple.com/documentation/evaluations/designing-evaluation-criteria)
- [Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)
- [Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/), from WWDC25,
  on sampling modes and greedy sampling
- [Improve your prompts by hill-climbing with Evaluations](https://developer.apple.com/videos/play/wwdc2026/335/), from
  WWDC26, on changing one thing at a time and comparing runs

### OpenAI's guides

- [Models](https://developers.openai.com/api/docs/models), on snapshots and the names that point at them
