# ``LanguageModels``

@Metadata {
    @PageImage(
        purpose: icon,
        source: "swift-language-models-page-icon",
        alt: "The Swift Language Models icon."
    )
    @PageImage(
        purpose: card,
        source: "swift-language-models-card",
        alt: "The Swift Language Models icon on an indigo and magenta background."
    )
}

Describe provider modules' models and choose their reasoning level in Foundation Models sessions.

## Overview

![The Swift Language Models icon: a network of model providers on an indigo background.](swift-language-models-icon)

Each provider module plugs a provider's models into Foundation Models:

| Provider | Module |
|---|---|
| [OpenRouter](https://openrouter.ai) | [`OpenRouterLanguageModels`](https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels) |
| [OpenAI](https://openai.com/api/) | [`OpenAILanguageModels`](https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels) |
| Any provider whose API speaks OpenAI's Chat Completions or Responses format | [`OpenAICompatibleLanguageModels`](https://ironsparrows.github.io/swift-language-models/documentation/openaicompatiblelanguagemodels) |

This module holds what the provider modules share. A provider module's model conforms to ``DetailedLanguageModel``,
so it carries ``ModelDetails``: its name, capabilities, context size, the reasoning levels it accepts and the kinds of
data it takes as attachments and generates. Foundation Models asks the model for its capabilities and data kinds. The
model answers from its details, and for the data it generates, also from the server tools it's given, such as OpenAI's
image generation.
From OS 27.2, ``FileAttachment`` attaches a file, such as a PDF, to a prompt.

Each catalog model's details name an effort type that lists the model's levels.
``DetailedLanguageModel/reasoningLevel(_:)`` takes only those levels:

@Snippet(path: "swift-language-models/Snippets/Effort", slice: "modelLevel")

``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)`` sets a level for a whole session the same
way, and Apple's `.light`, `.moderate` and `.deep` still work with every model, as <doc:ReasoningLevels> describes.

The package logs each request to the unified logging system, never with API keys, prompts or answers, as
<doc:Logging> describes.

## Topics

### Essentials

- <doc:ReasoningLevels>
- <doc:ReadingModelDetails>
- <doc:KeepingAPIKeysOutOfTheApp>

### Models

- <doc:ModelCatalogs>
- ``DetailedLanguageModel``
- ``ModelDetails``
- ``ModelReasoning``
- ``ProviderVocabulary``

### Request configuration

- ``RequestRetries``
- ``ImageEncoding``

### Reasoning level

- ``DetailedLanguageModel/reasoningLevel(_:)``
- ``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)``
- ``ModelEffort``
- ``Efforts``
- ``FoundationModels/ContextOptions/ReasoningLevel``

### Answer metadata

- <doc:ReadingWhatAProviderReports>
- ``FoundationModels/Transcript/Response/providerMetadata``
- ``FoundationModels/Transcript/ToolCalls/providerMetadata``
- ``ProviderResponseMetadata``
- ``FoundationModels/LanguageModelSession/Usage/providerMetadata``
- ``ProviderUsageMetadata``
- ``FoundationModels/LanguageModelError/providerMetadata``
- ``ProviderErrorMetadata``
- ``Citation``
- ``FinishReason``

### Guided answers

- ``GuideViolations``
- ``GuideViolation``
- ``GuideViolation/Keyword``

### Attachments

- ``FileAttachment``
- ``FileAttachment/UnknownTypeError``

### Logging

- <doc:Logging>
- ``LanguageModelsLogging``

### Testing and evaluation

- <doc:EvaluatingAcrossModels>
- <doc:TestingWithAScriptedModel>

### Provider modules

- <doc:WritingAProvider>
- ``DetailedLanguageModel/reportRemovedModels(for:)``
- ``DetailedLanguageModel/checkGuides(ofResponseText:for:)``

### Migration guides

- <doc:MigratingTo2>
