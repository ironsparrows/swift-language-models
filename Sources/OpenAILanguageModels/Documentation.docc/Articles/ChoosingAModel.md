# Choosing a model

Pick a model from the typed catalog or at runtime, and see what it supports.

## Overview

Each model in the catalog is a static member of ``OpenAIModel``, with its context size, request settings, input kinds
and reasoning levels:

@Snippet(path: "swift-language-models/Snippets/OpenAICatalog", slice: "details")

A catalog model's effort type lists exactly the levels it accepts, so `model.reasoningLevel(_:)` offers only those
levels.

### Pick a model at runtime

For a model picked at runtime, such as from a list people choose from, ``OpenAIModel/catalogModels`` lists every model,
sorted by id, and ``OpenAIModel/init(catalogID:)`` finds one by its id:

@Snippet(path: "swift-language-models/Snippets/OpenAICatalog", slice: "pick")

Both give models whose efforts are in their open form, `ContextOptions.ReasoningLevel`, so models with different effort
types fit in one list; ``OpenAIModel/init(_:)`` turns a catalog model into that form, and
``OpenAILanguageModel/init(_:)`` does the same for a language model.
``FoundationModels/ContextOptions/ReasoningLevel/effortWord`` reads a level's word in that form, such as `xhigh`, to
show it. A model that isn't in the catalog yet takes its details from
``OpenAIModel/init(id:displayName:releaseDate:knowledgeCutoff:expirationDate:contextSize:inputModalities:supportedParameters:reasoning:reasoningEfforts:defaultReasoningEffort:)``.

### Dated snapshots

The catalog lists a model's dated snapshots as members of their own, such as `.gpt5_5_2026_04_23` for
`gpt-5.5-2026-04-23`, next to `.gpt5_5` for `gpt-5.5`. A snapshot that the catalog's descriptions don't cover takes
its model's details, and its model's name with its day, such as GPT-5.5 (2026-04-23).

An answer names the model that answered, which can be a dated snapshot of the one the request named, such as
`gpt-5-nano-2025-08-07` for `gpt-5-nano`. The entry that ends the answer keeps it, and
``OpenAIResponseMetadata/model`` reads it, as <doc:ErrorsAndMetadata> shows. Reasoning that a snapshot wrote goes back
on later turns to the model it's a snapshot of, as <doc:Reasoning> describes. To keep the model the same from run to
run, name a dated snapshot, as <doc:RepeatableRuns> describes.

### How the catalog stays current

The catalog comes from three lists:

- OpenAI's OpenAPI description, which names the effort words.
- OpenAI's list of the models it serves, `GET /v1/models`, with the day each one shuts down.
- [models.dev](https://models.dev), which describes each model: its name, context size, input kinds and knowledge
  cutoff, whether it calls tools, holds its answers to a schema and takes a temperature, and whether it reasons, with
  its efforts.

None of them gives the effort a model uses when a request doesn't set a level, so every model's
``OpenAIModel/defaultReasoningEffort`` is `nil`.

A model is in the catalog when OpenAI serves it and models.dev describes it as a model that answers in text, unless
its id says it works only with an endpoint other than the Responses API, as the search, audio, realtime, transcription
and speech models do. A model that only works with a tool of its own is left out, and so is one whose shutdown day has
passed, although OpenAI may still list it. A bot in the package's repository reads the lists, and a change to them
ships in a new release of the package.

A model with a shutdown day, which ``OpenAIModel/expirationDate`` gives, is marked `deprecated` with "OpenAI retires
this model on" that day, so code that names it warns before it stops working. Members without one, such as `.gpt6Luna`
and `.gpt5_5`, aren't. A model that leaves the catalog keeps its member, marked `deprecated` with "Removed from OpenAI"
and the day, which ``OpenAIModel/removalDate`` gives, and ``OpenAIModel/catalogModels`` and
``OpenAIModel/init(catalogID:)`` leave it out. A request that still names it logs an error and, in a debug build, shows
a runtime warning. <doc:/LanguageModels/ModelCatalogs> says how every provider module's catalog changes, and which
release each change needs.

### What a model supports

``OpenAIModel/capabilities`` come from what the model lists: tool calling from `tools`, guided generation from
`structured_outputs`, reasoning from ``OpenAIModel/reasoning``, and vision from image input. Its
``OpenAIModel/supportedParameters`` come from models.dev:

- `max_output_tokens`, for every model.
- `tools`, `tool_choice` and `parallel_tool_calls`, for a model that calls tools.
- `structured_outputs`, for a model that holds its answers to a schema.
- `temperature` and `top_p`, for a model that takes a temperature.
- `reasoning`, for a model that reasons.

A setting the catalog lists per model, such as `temperature`, goes out only when the model lists it. A setting left
out is logged, and a debug build shows a runtime warning in Xcode for it. A model that reasons takes `temperature` and
`top_p` only while it doesn't reason, as <doc:Reasoning> describes. Tools and schemas are the exception: Foundation
Models checks a request against the model's capabilities before anything is sent, so a session with tools on a model
that doesn't list `tools`, or a guided request to one that doesn't list `structured_outputs`, throws
`LanguageModelError.unsupportedCapability`. <doc:Mapping> lists what each setting becomes.

``OpenAIModel/inputModalities`` says which attachments a model takes, as <doc:Attachments> describes: GPT-6 Luna takes
text, images and PDFs, and GPT-5.2 takes text and images.

### What a request costs

The catalog keeps no prices. What the answer's usage counts:

- **Input.** Each request sends the whole transcript, so earlier prompts and attachments count as input again with
  every later request of the session. The usage counts the input tokens, and the ones OpenAI read from its prompt
  cache, as <doc:Caching> describes.
- **Output.** The usage counts the answer's tokens, its reasoning tokens among them.
- **Tool calls.** Each round of tool calls is a request of its own, and a response's usage reports only the last one.
- **Server tools.** A web search costs by the call, which ``OpenAIUsageMetadata/webSearchCount`` counts, an image at
  the prices of the model that draws it, and a file search by the call and the storage it searches, on top of the
  tokens, as <doc:ServerTools> describes.

``OpenAIOptions/serviceTier`` picks a processing tier, which trades speed against price, and the answer's metadata names
the tier that served it.

### OpenAI's guides

- [Models](https://developers.openai.com/api/docs/models)
- [Deprecations](https://developers.openai.com/api/docs/deprecations), on the shutdown dates the catalog marks
