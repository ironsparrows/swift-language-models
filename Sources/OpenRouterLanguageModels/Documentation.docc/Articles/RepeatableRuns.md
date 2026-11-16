# Repeatable runs with remote models

Keep the model, its host and its settings the same between evaluation runs, and measure how much the answers vary.

## Overview

An evaluation compares runs: the same samples before and after a change to a prompt, or with one model and then
another. The comparison holds only when nothing else changed between the runs. A remote model's answers vary even
when the request doesn't, and the model and host that serve a request can change from one request to the next, so a
run pins what it can and measures the rest.

### What sampling settings promise

Greedy sampling picks the most likely token every time. Apple documents it as giving the same output for the same
input; a new version of the on-device model, which comes with an OS update, can change that output. A seed in
`.random(top:seed:)` or `.random(probabilityThreshold:seed:)` is best effort, as Apple's documentation says, and
OpenRouter's documentation says that its `seed` doesn't make every model deterministic.

### What a request sends

A request sends a sampling setting only when the model lists its parameter in ``OpenRouterModel/supportedParameters``,
and with ``OpenRouterLanguageModel/fallbacks``, only when every model lists it. Any other setting is left out and
logged, and a debug build shows a runtime warning for it.

- `.greedy` sends `temperature` 0, and `top_k` 1 when the request has no tools or schema and every model lists it.
- `.random(top:seed:)` sends `top_k` and `seed`, and `.random(probabilityThreshold:seed:)` sends `top_p` and `seed`.
- A temperature sends `temperature`.

Claude Haiku 5.5 and Claude Sonnet 5.5 list none of `temperature`, `top_k` and `seed`, so greedy sampling and seeds
never reach them, and GPT-5.4 mini lists `seed` but not `temperature`. The catalog says what each model lists:

@Snippet(path: "swift-language-models/Snippets/RepeatableRuns", slice: "parameters")

A host that doesn't take a parameter ignores it, unless the request asks OpenRouter for hosts that take every parameter
it sends. ``OpenRouterRouting/parameterSupport`` set to ``OpenRouterRouting/Requirement/required`` asks for them,
and a request with tools, server tools or a response schema asks for them on its own.

### Pin the model under test

- Name a catalog model, not an alias such as `~anthropic/claude-haiku-latest`, which follows the vendor's newest model.
- Leave out fallbacks, since any of them may answer.
- Keep the request on fixed hosts with ``OpenRouterRouting/order`` and ``OpenRouterRouting/fallbackProviders`` set to
  ``OpenRouterRouting/Permission/disallowed``. A model's hosts can differ, such as in the precision they run it at,
  which ``OpenRouterRouting/quantizations`` limits.
- Leave the response cache off, as the next section explains.
- Record the model and host that answered each request, from the answer's
  ``OpenRouterResponseMetadata/model`` and ``OpenRouterResponseMetadata/provider``.

@Snippet(path: "swift-language-models/Snippets/RepeatableRuns", slice: "pinned")

An evaluation's judge needs the same pinning, as
<doc:JudgingAndGeneratingSamples> describes.

### Turn the response cache off

With ``OpenRouterLanguageModel/responseCache`` set, a request that repeats an earlier one gets the earlier answer back,
whatever its sampling settings. An evaluation sends the same requests on every run, so the runs within the cache's time
to live repeat the first run's answers, at no cost, and show none of the model's variance. For the model under test,
leave it `nil`, as it is unless the model is created with one. An answer from the cache has
``OpenRouterResponseMetadata/responseCacheStatus`` set to ``OpenRouterResponseCache/Status/hit``.
<doc:Caching#Answer-repeated-requests-from-the-response-cache> describes the cache.

### Record cost and latency

The subject returns what each answer cost and how long the host took with its value: the cost from
``OpenRouterUsageMetadata/cost`` in the response's `usage.openRouter`, and the host's time from
``OpenRouterResponseMetadata/generationTime`` in the answer's `openRouter`, which needs
``OpenRouterOptions/includesRouterMetadata``. Code evaluators score them, and their mean and standard deviation across
the samples show what a run costs and how steady the host is:

@Snippet(path: "swift-language-models/Snippets/RepeatableRuns", slice: "answer")

The result keeps each sample's value, so the model and host that answered stay with the run.

### Measure the variance

Instead of asserting that two runs give the same answers, a test runs the evaluation several times and bounds the
worst run and the spread between runs:

@Snippet(path: "swift-language-models/Snippets/RepeatableRuns", slice: "variance")

A sample whose request fails is left out of the scores rather than counted as a failure, so the test checks each run's
`errors` too.

Labeling runs and comparing them across models is in
<doc:/LanguageModels/EvaluatingAcrossModels>.

### Apple's guides

- [Evaluating language model responses](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses)
- [Designing specific, measurable criteria in an evaluation suite](https://developer.apple.com/documentation/evaluations/designing-evaluation-criteria)
- [Evaluating a Core AI model](https://developer.apple.com/documentation/evaluations/evaluating-a-core-ai-model), a
  sample that evaluates a custom `LanguageModel` beside the default model
- [Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)
- [Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/), from WWDC25,
  on sampling modes and greedy sampling
- [Improve your prompts by hill-climbing with Evaluations](https://developer.apple.com/videos/play/wwdc2026/335/), from
  WWDC26, on changing one thing at a time and comparing runs
