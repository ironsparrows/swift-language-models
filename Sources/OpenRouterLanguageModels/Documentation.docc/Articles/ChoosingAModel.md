# Choosing a model

Pick a model from the typed catalog or at runtime, and see what it supports and what its requests cost.

## Overview

Each model OpenRouter listed when the catalog was generated is a static member of ``OpenRouterModel``, with its
context size, parameters, input and output kinds and reasoning levels:

@Snippet(path: "swift-language-models/Snippets/Catalog", slice: "catalog")

A catalog model's effort type lists exactly the levels it accepts, so `model.reasoningLevel(_:)` offers only those
levels.

### Pick a model at runtime

For a model picked at runtime, such as from a list people choose from, ``OpenRouterModel/catalogModels`` lists every
model and ``OpenRouterModel/init(catalogID:)`` finds one by its id:

@Snippet(path: "swift-language-models/Snippets/Catalog", slice: "picker")

Both give models whose efforts are in their open form, `ContextOptions.ReasoningLevel`, so models with different effort
types fit in one list; ``OpenRouterModel/init(_:)`` turns a catalog model into that form, and
``FoundationModels/ContextOptions/ReasoningLevel/effortWord`` reads a level's word in it, such as `xhigh`, to show
it. A model that isn't in the catalog yet takes its details from
``OpenRouterModel/init(id:displayName:releaseDate:aliasTarget:knowledgeCutoff:expirationDate:contextSize:inputModalities:outputModalities:supportedParameters:reasoning:reasoningEfforts:defaultReasoningEffort:cachesOnlyMarkedPrompts:)``.

### How the catalog stays current

The catalog comes from OpenRouter's list of models, `GET /api/v1/models`. A bot in the package's repository reads it,
and a change to it ships in a new release of the package. A model OpenRouter will retire, as its
``OpenRouterModel/expirationDate`` says, is marked `deprecated` with that day. A model OpenRouter stops listing keeps
its member, marked `deprecated` with "Removed from OpenRouter" and the day, which ``OpenRouterModel/removalDate``
gives, and ``OpenRouterModel/catalogModels`` and ``OpenRouterModel/init(catalogID:)`` leave it out. A request that
still names it, as its model or a fallback, may fail, so it logs an error and, in a debug build, shows a runtime
warning.
<doc:/LanguageModels/ModelCatalogs>
says how every provider module's catalog changes, and which release each change needs.

A catalog model keeps images among its ``OpenRouterModel/outputModalities`` only when the list names OpenRouter's images
path, `/api/v1/images`, among the paths that serve it. A router such as `openrouter/auto` lists images but isn't served
on that path, so its catalog member records only text, and a request to it doesn't ask for images, nor does one with it
as a fallback.

### Aliases and routers

An alias, such as `~anthropic/claude-haiku-latest`, follows a vendor's newest model, and ``OpenRouterModel/aliasTarget``
names the model it points to now.

A router picks a model for each request. `openrouter/auto` and `openrouter/auto-beta` read
``OpenRouterOptions/autoRouter``: the models they may pick from, by id or by a pattern such as `anthropic/*`, the
models they never pick, and an ``OpenRouterOptions/AutoRouter/CostTier`` that limits them to a band of models by price.
`openrouter/pareto-code` reads ``OpenRouterOptions/paretoRouter``: a minimum coding score, from 0 to 1, which sets
how strong a coder it picks, or a maximum prompt price, which picks the best coder at or under it. A request to any
other model leaves these settings out:

@Snippet(path: "swift-language-models/Snippets/Catalog", slice: "routers")

Either way, the answer's ``OpenRouterResponseMetadata/model`` names the model that answered.

### What a model supports

``OpenRouterModel/capabilities`` come from what the model lists: tool calling from `tools`, guided generation from
`structured_outputs`, reasoning from ``OpenRouterModel/reasoning``, and vision from image input.
<doc:ToolsAndGuidedGeneration> and <doc:Reasoning> say what each means for a request.

A sampling or output setting, such as `temperature`, `stop` or `verbosity`, goes out only when the model lists its
parameter in ``OpenRouterModel/supportedParameters``, so a host never rejects one, and a debug build shows a runtime
warning in Xcode for each setting left out. Required tool calls are the exception: only `tool_choice` makes a model
call a tool, so with `toolCallingMode` set to `.required`, a request throws `LanguageModelError.unsupportedCapability`
before sending anything when the model or a fallback doesn't list `tools`, or lists it without `tool_choice`, as
Amazon's Nova 1.0 models do. <doc:Mapping> lists what each setting becomes.

### What a request costs

OpenRouter bills each request from the account's credits, at the price of the model that answered, which the answer's
``OpenRouterResponseMetadata/model`` names. The catalog keeps no prices, since OpenRouter changes them often.
``OpenRouterModel/currentPricing(auth:session:configuration:)`` reads today's, as <doc:ModelAndProviderInfo> shows, and
the answer's usage reports what the request cost, in ``OpenRouterUsageMetadata/cost``, as <doc:ErrorsAndMetadata> shows.
What else a request costs:

- **Tool calls.** Each round of tool calls is a request of its own, billed on its own, and the answer's usage reports
  only the last. <doc:ErrorsAndMetadata#Add-up-what-a-response-cost> adds them up.
- **Fallbacks.** When a fallback answers, the request is billed at the fallback's price. That holds for a `:free` model
  too, so list only `:free` models to keep requests free.
- **The transcript.** Each request sends the whole transcript, so earlier prompts and attachments are billed as input
  again with every later request of the session. They're the same bytes each time, so a host that caches prompts bills
  the repeat at its cached price; <doc:Caching> says how each host caches.
- **Generated data.** Images a model generates, and any attachment on an answer, stay in the transcript but aren't
  sent back, so they aren't billed again.
- **PDFs.** OpenRouter reads a PDF for a model that can't, with Mistral's OCR,
  ``OpenRouterOptions/PDFEngine/mistralOCR``, at a price per page, unless
  ``OpenRouterOptions/pdfEngine`` picks another engine, such as the free ``OpenRouterOptions/PDFEngine/cloudflareAI``.
- **Server tools.** Web searches and fetches cost extra, on top of the model's tokens, at the engine's price.
  ``OpenRouterWebSearchEngine`` and ``OpenRouterWebFetchEngine`` say how each engine charges. An advisor or a subagent
  is a request to another model, at that model's price. The date and time are free.
- **Variants.** ``OpenRouterRouting/variant`` can bill a request at the rate of the service tier that serves it.
- **The response cache.** An answer that ``OpenRouterResponseCache`` serves costs nothing.

### OpenRouter's guides

- [Models](https://openrouter.ai/docs/guides/overview/models)
- [Latest Model Resolution](https://openrouter.ai/docs/guides/routing/routers/latest-resolution), for aliases
- [Auto Router](https://openrouter.ai/docs/guides/routing/routers/auto-router)
- [Pareto Router](https://openrouter.ai/docs/guides/routing/routers/pareto-router)
