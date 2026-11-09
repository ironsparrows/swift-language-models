# ``OpenAICompatibleLanguageModels``

@Metadata {
    @PageImage(
        purpose: icon,
        source: "openai-compatible-language-models-page-icon",
        alt: "The Swift Language Models icon."
    )
    @PageImage(
        purpose: card,
        source: "openai-compatible-language-models-card",
        alt: "The Swift Language Models icon on an indigo and magenta background."
    )
}

Use models of any provider whose API speaks OpenAI's Chat Completions or Responses format in Foundation Models sessions.

## Overview

![The Swift Language Models icon: a network of model providers on an indigo background.](openai-compatible-language-models-icon)

``OpenAICompatibleLanguageModel`` plugs a model into Foundation Models from a provider you describe: its name, the base
URL of its API and the format it speaks. Sessions, prompts, tools, guided generation, profiles and reasoning levels work
as they do with Apple's own models:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleQuickStart", slice: "session")

Each request is a `POST` to the format's path under the provider's URL, `chat/completions` or `responses`, and its answer
streams back as server-sent events. Every request sends the whole transcript.

There's no catalog behind the module. ``OpenAICompatibleModel`` holds what you say about a model: its id, its context
size, whether it reasons and the reasoning levels it accepts. The provider has the last word at run time: a setting it
rejects throws ``OpenAICompatibleError`` with the provider's own words.

Model details, reasoning levels and logging live in the [`LanguageModels` module](doc:/LanguageModels), which this
module re-exports.

## Topics

### Essentials

- <doc:GettingStarted>
- ``OpenAICompatibleLanguageModel``
- ``OpenAICompatibleModel``
- ``OpenAICompatibleProvider``
- ``OpenAICompatibleAuthentication``

### Models

- ``OpenAICompatibleModelID``

### Attachments

- ``FileAttachment``

### Request settings

- ``OpenAICompatibleOptions``
- ``OpenAICompatibleConfiguration``
- ``RequestRetries``
- ``ImageEncoding``

### Results and errors

- ``FoundationModels/Transcript/Response/openAICompatible``
- ``FoundationModels/Transcript/ToolCalls/openAICompatible``
- ``FoundationModels/LanguageModelSession/Usage/openAICompatible``
- ``FoundationModels/LanguageModelError/openAICompatible``
- ``OpenAICompatibleResponseMetadata``
- ``OpenAICompatibleUsageMetadata``
- ``OpenAICompatibleErrorMetadata``
- ``OpenAICompatibleError``
- ``OpenAICompatibleError/Code``
