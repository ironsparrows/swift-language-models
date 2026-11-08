# ``OpenAILanguageModels``

@Metadata {
    @PageImage(
        purpose: icon,
        source: "openai-language-models-page-icon",
        alt: "The Swift Language Models icon."
    )
    @PageImage(
        purpose: card,
        source: "openai-language-models-card",
        alt: "The Swift Language Models icon on an indigo and magenta background."
    )
}

Use OpenAI's models in Foundation Models sessions, through the Responses API.

## Overview

![The Swift Language Models icon: a network of model providers on an indigo background.](openai-language-models-icon)

``OpenAILanguageModel`` plugs an OpenAI model into Foundation Models, so sessions, prompts, tools, guided generation,
profiles and reasoning levels work as they do with Apple's own models:

@Snippet(path: "swift-language-models/Snippets/OpenAIQuickStart", slice: "session")

Each request is a `POST` to OpenAI's Responses API, `responses`, and its answer streams back as server-sent events.
Every request sends the whole transcript, and a model's reasoning goes back on later turns encrypted, so a session
works the same whether or not OpenAI keeps its responses, apart from a generated image, as <doc:ServerTools>
describes.

Every model in the catalog is a static member of ``OpenAIModel``, with its context size, request settings, input kinds
and reasoning levels. Its effort type lists exactly the levels the model accepts, so `model.reasoningLevel(_:)` offers
only those levels. The catalog lists the models OpenAI still serves through the Responses API, and keeps no prices,
as <doc:ChoosingAModel> describes.

Model details, typed reasoning efforts and logging live in the [`LanguageModels` module](doc:/LanguageModels), which
this module re-exports.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Authentication>
- <doc:ChoosingAModel>
- ``OpenAILanguageModel``
- ``OpenAIModel``
- ``OpenAIAuthentication``

### Models

- ``OpenAIModelID``
- ``OpenAICatalog``
- ``OpenAIParameter``
- ``OpenAIInputModality``

### Tools, guided generation and reasoning

- <doc:ToolsAndGuidedGeneration>
- <doc:Reasoning>

### Server tools

- <doc:ServerTools>
- ``OpenAIServerTool``
- ``OpenAISearchContextSize``
- ``OpenAIImageModel``
- ``OpenAIImageQuality``
- ``OpenAIImageComplexity``
- ``OpenAIImageSize``
- ``OpenAIImageFormat``
- ``OpenAIImageBackground``
- ``OpenAIImageModeration``

### Caching

- <doc:Caching>
- ``OpenAIOptions/CacheKey``

### Attachments

- <doc:Attachments>
- ``FileAttachment``

### Request settings

- ``OpenAIOptions``
- ``OpenAIServiceTier``
- ``OpenAIConfiguration``
- ``RequestRetries``
- ``ImageEncoding``

### Results and errors

- <doc:ErrorsAndMetadata>
- ``FoundationModels/Transcript/Response/openAI``
- ``FoundationModels/Transcript/ToolCalls/openAI``
- ``FoundationModels/LanguageModelSession/Usage/openAI``
- ``FoundationModels/LanguageModelError/openAI``
- ``OpenAIResponseMetadata``
- ``OpenAIResponseMetadata/Message``
- ``OpenAIResponseMetadata/Phase``
- ``OpenAIServerToolCall``
- ``OpenAIFileCitation``
- ``FoundationModels/Transcript/DataEntry/openAI``
- ``OpenAIDataMetadata``
- ``OpenAIUsageMetadata``
- ``OpenAIErrorMetadata``
- ``OpenAIError``
- ``OpenAIError/Code``

### Testing and evaluation

- <doc:JudgingAndGeneratingSamples>
- <doc:RepeatableRuns>

### Reference

- <doc:Mapping>
