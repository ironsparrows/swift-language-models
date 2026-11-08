# ``OpenRouterLanguageModels``

@Metadata {
    @PageImage(
        purpose: icon,
        source: "openrouter-language-models-page-icon",
        alt: "The Swift Language Models icon."
    )
    @PageImage(
        purpose: card,
        source: "openrouter-language-models-card",
        alt: "The Swift Language Models icon on an indigo and magenta background."
    )
}

Use any model on OpenRouter in Foundation Models sessions.

## Overview

![The Swift Language Models icon: a network of model providers on an indigo background.](openrouter-language-models-icon)

``OpenRouterLanguageModel`` plugs an OpenRouter model into Foundation Models, so sessions, prompts, tools, guided
generation, profiles and reasoning levels work as they do with Apple's own models:

@Snippet(path: "swift-language-models/Snippets/QuickStart", slice: "session")

Every model in the catalog is a static member of ``OpenRouterModel``, with its context size, parameters, input and
output kinds and reasoning levels. Its effort type lists exactly the levels the model accepts, so
`model.reasoningLevel(_:)` offers only those levels.

What changes often, such as a model's prices and the health of each host that serves it, comes from OpenRouter when
an app asks, as <doc:ModelAndProviderInfo> shows.

Model details, typed reasoning efforts and logging live in the
[`LanguageModels` module](doc:/LanguageModels),
which this module re-exports.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Authentication>
- <doc:ChoosingAModel>
- ``OpenRouterLanguageModel``
- ``OpenRouterModel``
- ``OpenRouterAuthentication``

### Models

- ``OpenRouterModelID``
- ``OpenRouterCatalog``
- ``OpenRouterParameter``
- ``OpenRouterInputModality``
- ``OpenRouterOutputModality``
- ``OpenRouterPricing``
- ``OpenRouterPricing/Override``
- ``OpenRouterPricing/Override/Condition``
- ``OpenRouterPricing/TimeWindow``

### Tools, guided generation and reasoning

- <doc:ToolsAndGuidedGeneration>
- <doc:Reasoning>

### Model and provider info

- <doc:ModelAndProviderInfo>
- ``OpenRouterEndpoint``
- ``OpenRouterCurrentDetails``

### Routing and fallbacks

- <doc:RoutingAndFallbacks>
- ``OpenRouterRouting``
- ``OpenRouterProviderName``
- ``OpenRouterQuantization``

### Caching

- <doc:Caching>
- ``OpenRouterCacheControl``
- ``OpenRouterCacheControl/TimeToLive``
- ``OpenRouterResponseCache``
- ``OpenRouterResponseCache/Status``

### Server tools

- <doc:ServerTools>
- ``OpenRouterServerTool``
- ``OpenRouterWebSearchEngine``
- ``OpenRouterWebSearchMode``
- ``OpenRouterSearchContextSize``
- ``OpenRouterWebFetchEngine``

### Attachments

- <doc:Attachments>
- ``FileAttachment``

### Request settings

- ``OpenRouterOptions``
- ``OpenRouterServiceTier``
- ``OpenRouterApp``
- ``OpenRouterApp/Category``
- ``OpenRouterPlugin``
- ``OpenRouterConfiguration``
- ``RequestRetries``
- ``ImageEncoding``

### Results and errors

- <doc:ErrorsAndMetadata>
- ``FoundationModels/Transcript/Response/openRouter``
- ``FoundationModels/Transcript/ToolCalls/openRouter``
- ``FoundationModels/LanguageModelSession/Usage/openRouter``
- ``FoundationModels/LanguageModelError/openRouter``
- ``OpenRouterResponseMetadata``
- ``OpenRouterResponseMetadata/RoutingStrategy``
- ``OpenRouterResponseMetadata/RoutingAttempt``
- ``OpenRouterResponseMetadata/RoutingEndpoint``
- ``OpenRouterResponseMetadata/PipelineStage``
- ``OpenRouterResponseMetadata/PipelineStage/Kind``
- ``OpenRouterUsageMetadata``
- ``OpenRouterErrorMetadata``
- ``OpenRouterErrorMetadata/LimitSource``
- ``OpenRouterError``
- ``OpenRouterError/Code``

### Testing and evaluation

- <doc:JudgingAndGeneratingSamples>
- <doc:RepeatableRuns>

### Reference

- <doc:Mapping>
