# Model and provider info

Read a model's hosts and what OpenRouter lists for it now, such as today's prices.

## Overview

The catalog holds what changes rarely about a model, such as its context size and parameters. What changes often comes
from OpenRouter when an app asks: each host that serves the model, such as Google Vertex or Amazon Bedrock, with its
prices, limits and recent health, and the model's current prices. OpenRouter calls these hosts providers.

The calls belong to a model: ``OpenRouterModel/endpoints(auth:session:configuration:)``,
``OpenRouterModel/currentDetails(auth:session:configuration:)`` and
``OpenRouterModel/currentPricing(auth:session:configuration:)``.
They need no API key, and take an optional ``OpenRouterAuthentication`` and URL session. On
``OpenRouterLanguageModel``, ``OpenRouterLanguageModel/endpoints()``, ``OpenRouterLanguageModel/currentDetails()`` and
``OpenRouterLanguageModel/currentPricing()`` read them for the model's ``OpenRouterLanguageModel/details`` with the
model's own authentication and session, so they go to the same server as its requests, such as its proxy.

### List a model's endpoints

Each ``OpenRouterEndpoint`` is one endpoint of a host: the host's ``OpenRouterEndpoint/name``, and the
``OpenRouterEndpoint/tag`` that sets the endpoint apart, such as `google-vertex/europe` for Google's European region.
A host can serve a model at several endpoints, in different regions, service tiers or precisions, so it can appear
more than once. Each endpoint has its own context size, output limit, prices, discount, request parameters and recent
uptime, and ``OpenRouterEndpoint/supportsImplicitCaching`` says whether it caches prompts without marks:

@Snippet(path: "swift-language-models/Snippets/ModelInfo", slice: "modelEndpoints")

OpenRouter reports each endpoint's latency to the first token and its throughput, at the 50th, 75th, 90th and 99th
percentiles of the last 30 minutes, only to a call with a key. Without one,
``OpenRouterEndpoint/latencyLast30Minutes`` and ``OpenRouterEndpoint/throughputLast30Minutes`` are `nil`.

An alias, such as `~anthropic/claude-haiku-latest`, has no endpoints of its own;
``OpenRouterCurrentDetails/aliasTarget`` names the model whose endpoints serve it.

### Route to the hosts you pick

``OpenRouterRouting/order`` takes an endpoint's tag, so a list of endpoints turns into a routing preference, such as
for the hosts in one region:

@Snippet(path: "swift-language-models/Snippets/ModelInfo", slice: "route")

With ``OpenRouterRouting/fallbackProviders`` set to ``OpenRouterRouting/Permission/disallowed``, a request goes to
no other host when the listed ones are unavailable. <doc:RoutingAndFallbacks> describes the other routing
settings.

### Read today's prices

The catalog keeps no prices, since OpenRouter changes them often.
``OpenRouterModel/currentDetails(auth:session:configuration:)`` reads what OpenRouter lists for a model now: its
prices, context size, output limit, request parameters, whether the host OpenRouter ranks first moderates content, and
the day OpenRouter retires it. ``OpenRouterModel/currentPricing(auth:session:configuration:)`` reads only the prices, as
``OpenRouterPricing``, whose ``OpenRouterPricing/prices(forPromptTokens:at:)`` applies the overrides for long prompts
and off-peak hours:

@Snippet(path: "swift-language-models/Snippets/ModelInfo", slice: "pricing")

The prices include the prompt cache's: ``OpenRouterPricing/cacheRead`` for a prompt token read from the cache, and
``OpenRouterPricing/cacheWrite`` and ``OpenRouterPricing/cacheWriteOneHour`` for one written to it, when writing costs
extra. <doc:Caching> says which hosts cache on their own and which need marks. ``OpenRouterPricing/webSearch`` is the
price of one search that the model or its host runs, and an ``OpenRouterPricing/Override`` applies while its
``OpenRouterPricing/Override/Condition`` holds.

A router, such as `openrouter/auto`, has no prices of its own, since the model it picks sets them, so its pricing is
`nil`. Either way, the answer's usage reports what a request actually cost, in ``OpenRouterUsageMetadata/cost``.

### Caching and failures

Each answer is kept in memory for a minute by default, by its URL and the authentication headers it was read with, so
calling these often, such as from each row of a list, doesn't fetch them again. The cache keeps a digest of the
headers, never the headers themselves, and never keeps a failure.

An ``OpenRouterConfiguration`` changes how long an answer is kept, with its
``OpenRouterConfiguration/infoCacheLifetime``, and how a call retries. Its ``OpenRouterConfiguration/idleTimeout``
doesn't apply to these calls: they wait as long as the URL session's own timeout says. A language model's calls use its
``OpenRouterLanguageModel/configuration``, and a catalog model's take one of their own, such as to keep prices for 10
seconds:

```swift
let configuration = OpenRouterConfiguration(infoCacheLifetime: .seconds(10))
let pricing = try await OpenRouterModel.anthropicClaudeHaiku5_5.currentPricing(configuration: configuration)
```

An answer lasts as long as the call that fetched it said, so a shorter lifetime doesn't drop one already kept.

A call fails as a session's request does: a model OpenRouter doesn't list throws ``OpenRouterError`` with
``OpenRouterError/Code/notFound``, a rate limit throws `LanguageModelError.rateLimited`, and a failed connection or
any status from 500 to 599 is retried as the configuration's ``OpenRouterConfiguration/retries`` say, up to twice by
default, and so is any status whose `x-should-retry` is `true`. A failure whose `x-should-retry` is `false` isn't
retried, and one that asks for a wait longer than 2 minutes throws at once, with the wait on its error.
A call sends the headers of its ``OpenRouterAuthentication``, none without one, and follows a redirect only to the same
scheme, URL host and port.
