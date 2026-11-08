# Errors and metadata

Handle failures, and read what OpenRouter reports about each answer.

## Overview

Rate limits, oversized contexts, content filters, refusals, timeouts and attachments a host rejects throw Foundation
Models' own `LanguageModelError`, so the same `catch` works for every model. Anything else, such as a rejected API key
or no credits left, throws ``OpenRouterError``, with its ``OpenRouterError/status``, ``OpenRouterError/code``,
``OpenRouterError/provider`` and ``OpenRouterError/retryAfter``:

@Snippet(path: "swift-language-models/Snippets/Errors", slice: "errors")

``OpenRouterError/isQuotaExhausted`` is `true` when the account ran out of credits or the key reached a spending limit
that never resets, which only adding credits or raising the limit clears.

A `LanguageModelError` that a failure becomes carries the HTTP status, OpenRouter's error code, the host and the budget
the request ran into in its metadata, which its `openRouter` reads as ``OpenRouterErrorMetadata``, in OpenRouter's
types, and its `providerMetadata` reads as ``ProviderErrorMetadata``, the same way for every provider.

A failed connection and any status from 500 to 599 are retried up to twice, before any data arrives, and so is any
status whose `x-should-retry` is `true`. A failure whose `x-should-retry` is `false` isn't retried, and one that asks
for a wait longer than 2 minutes throws at once, with the wait on its error. <doc:Mapping#Errors> lists what each
failure becomes.

### Read an answer's metadata

The entry that ends an answer carries facts about the answer: the model that answered, its host, its response id, why
the answer ended, the service tier that served it, and whether the response cache served it. The answer's usage carries
what it cost and counted: its cost and, when OpenRouter reports them, the host's charge and its parts, whether the
account's own key paid the host, the prompt tokens written to the host's cache, and the server tools' calls.
`openRouter` on a response entry reads its facts as ``OpenRouterResponseMetadata``, and on a usage as
``OpenRouterUsageMetadata``, with each amount in US dollars as a `Decimal`:

@Snippet(path: "swift-language-models/Snippets/Errors", slice: "metadata")

A text answer cut off at its token limit doesn't throw; its finish reason is ``FinishReason/length``. A guided answer
cut off there throws `GeneratedContent.ParsingError`, and one cut off inside its tool calls throws ``OpenRouterError``
with ``OpenRouterError/Code/invalidResponse``, so no tool runs with partial arguments.

A request that ends in tool calls has the same facts. Foundation Models keeps no readable metadata on a tool-calls
entry, so they sit on its first call, and `openRouter` on the `Transcript.ToolCalls` entry reads them from there, as
``OpenRouterResponseMetadata``. A request that asks for several calls at once has one set of facts.

Saved transcripts keep these facts. The ones any provider can report, such as the model, the host and the cost, also
read through `providerMetadata`, as ``ProviderResponseMetadata`` and ``ProviderUsageMetadata``, so code that reads them
works with any language model in this package, as <doc:/LanguageModels/ReadingWhatAProviderReports> shows. OpenRouter
calls the host that serves a model its provider, so ``OpenRouterResponseMetadata/provider`` names the host. The model
and host that answered depend on routing and fallbacks, as <doc:RoutingAndFallbacks> describes, and the response cache's
facts on <doc:Caching#Answer-repeated-requests-from-the-response-cache>.

### Add up what a response cost

Each round of tool calls is a request of its own, billed on its own. A response's `usage` has only its last request's
facts, and a session's own `usage` adds up the token counts of every request that answered, but keeps no metadata. A
request that fails, such as one the model refuses, reports no usage. So each request's usage facts are also on the
entry that ends it, which ``OpenRouterResponseMetadata/usage`` reads, and adding up their costs gives what the whole
response cost:

@Snippet(path: "swift-language-models/Snippets/Errors", slice: "cost")

### See how OpenRouter routed a request

With ``OpenRouterOptions/includesRouterMetadata``, the entry also reports how OpenRouter routed the request: the
strategy, the endpoints it could pick from, each attempt, the edge region, how long the host took, and the plugins that
changed the request or the answer. ``OpenRouterResponseMetadata`` reads them as
``OpenRouterResponseMetadata/routingStrategy``, ``OpenRouterResponseMetadata/routingEndpoints``,
``OpenRouterResponseMetadata/routingAttempts``, ``OpenRouterResponseMetadata/region``,
``OpenRouterResponseMetadata/generationTime`` and ``OpenRouterResponseMetadata/routingPipeline``.

Each attempt is an ``OpenRouterResponseMetadata/RoutingAttempt``, with the host, the model asked of it and the HTTP
status it answered with. Each endpoint is an ``OpenRouterResponseMetadata/RoutingEndpoint``, with the host, its model
and whether OpenRouter picked it. Each plugin is an ``OpenRouterResponseMetadata/PipelineStage``, with its kind, such
as ``OpenRouterResponseMetadata/PipelineStage/Kind/guardrail``, its ``OpenRouterPlugin`` and a summary of what it did.
The strategy is an ``OpenRouterResponseMetadata/RoutingStrategy``, such as
``OpenRouterResponseMetadata/RoutingStrategy/fallback``.

### Apple's guides

- [LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror)
- [Transcripts](https://developer.apple.com/documentation/foundationmodels/transcripts)
- [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output),
  on guardrail violations and refusals

### OpenRouter's guides

- [Errors and Debugging](https://openrouter.ai/docs/api_reference/errors-and-debugging)
- [Router Metadata](https://openrouter.ai/docs/guides/features/router-metadata)
- [BYOK](https://openrouter.ai/docs/guides/overview/auth/byok), for requests that the account's own keys for hosts pay
