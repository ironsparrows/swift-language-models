# Reasoning

Say whether a model reasons and at which levels, and see how its reasoning comes back and goes out again.

## Overview

Foundation Models sets how much a model reasons with `ContextOptions.ReasoningLevel`, as
<doc:/LanguageModels/ReasoningLevels> describes. There's no catalog behind this module, so an
``OpenAICompatibleModel`` says what you know: whether the model reasons, in `reasoning:`, and the levels it accepts,
highest first, in `efforts:`. Each one left out takes the provider's default, which a preset sets for its provider:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleReasoning", slice: "level")

### Which models reason

``OpenAICompatibleModel/reasoning`` is one of these ``ModelReasoning`` values:

- `unsupported`: the model doesn't reason. It accepts no level, and Foundation Models refuses a request that sets one
  before it's sent.
- `offByDefault`: the model reasons only when a request asks it to. It's the default on a provider you describe, and on
  Groq, Mistral, Ollama, LM Studio and vLLM.
- `onByDefault`: the model reasons unless a request turns it off. It's the default on Gemini, DeepSeek and xAI.
- `mandatory`: the model always reasons, such as `openai/gpt-oss-20b` on Groq, which takes no `none`.

A model that reasons has `.reasoning` in its ``OpenAICompatibleModel/capabilities``. Its
``OpenAICompatibleModel/defaultReasoningEffort`` is `nil`, since the module doesn't know the effort a model uses when a
request doesn't set one.

A preset's efforts are what its provider documents, and a model's own often differ: Groq's `openai/gpt-oss-20b` takes
`high`, `medium` and `low`, while the preset lists `none` too. Name a model's own with `efforts:`, since a word the model
doesn't take fails with the provider's error. <doc:Providers> lists each preset's efforts.

### What a level becomes

- A Chat Completions request sends the level as `reasoning_effort`, and a Responses request in `reasoning.effort`.
- A level the model accepts goes as it is, such as `.medium` as `medium`. Apple's `.light`, `.moderate` and `.deep` ask
  for `low`, `medium` and `high`. A level the model doesn't accept goes as the nearest one it does, the lower one on a
  tie, and the move is logged, with a runtime warning in a debug build.
- Only `.off` turns reasoning off, as `none`. A model asked to reason keeps reasoning, and a model that doesn't accept
  `none` gets its lowest level for `.off` instead.
- A request that sets no level sends no effort, so the model reasons as its provider decides.
- A model whose reasoning is `unsupported` gets no effort, whatever the level.
- An app's own `reasoning_effort` in ``OpenAICompatibleOptions/additionalMembers`` replaces the level's.

DeepSeek also reads `thinking`, which decides whether its models reason, so its preset sends `thinking` beside the
effort: disabled for `.off` and enabled for any other level. A model you describe on DeepSeek with `reasoning:
.unsupported` sends `thinking` disabled with every request. An app's own `reasoning_effort` goes without the preset's
`thinking`, and an app's own `thinking` replaces it. <doc:Providers> says what each provider does
with an effort, such as DeepSeek taking `medium` as `high`, and LM Studio being reported to ignore efforts in this
format.

### Read the model's reasoning

The model's reasoning arrives in the transcript as a reasoning entry, before the answer's text:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleReasoning", slice: "reading")

- In Chat Completions, it's read from each delta's `reasoning_content` or, when that holds no text, its `reasoning`, so
  a provider that sends the same text in both shows it once, and from the text parts inside `thinking` parts of the
  delta's content, as Mistral sends them. A `<think>` or `<thinking>` block that opens the answer's text is read as
  reasoning too.
- In Responses, it's the reasoning items' summary or text, when the provider sends either.
- Some providers send none: `gemini-3.1-flash-lite` sent no reasoning text, also when asked for its thoughts, so its
  reasoning entries hold only their signatures.

The answer's usage counts the reasoning tokens in `output.reasoningTokenCount`, as the provider reports them in
`completion_tokens_details.reasoning_tokens` or, in Responses, `output_tokens_details.reasoning_tokens`. Gemini reports
none, and counts its models' reasoning only in `total_tokens`, so its preset counts the tokens of the total beyond the
input and the output as reasoning, among the output tokens. A provider that reports reasoning tokens elsewhere, or not
at all, reads as 0: Ollama reported none, so its models' reasoning counts among the output tokens alone.

### Reasoning on later turns

Each request sends the whole transcript. Whether an answer's reasoning goes with it depends on how its provider reads
it back, so each preset sends it the way its provider does:

| Provider | Reasoning back |
|---|---|
| Gemini | Each answer's thought signature, as `extra_content.google.thought_signature`, on its first tool call, or on its message when it has no call |
| Groq, Ollama, vLLM | The assistant message's `reasoning` |
| DeepSeek | The assistant message's `reasoning_content` |
| xAI, and any provider on Responses | The answer's `reasoning` items, as they came |
| Mistral, LM Studio, and any provider you describe on Chat Completions | None |

- Reasoning goes back only to the model that wrote it, or to the model it's a dated version of, since another model may
  refuse it or read it as its own; DeepSeek's goes to any of its models. The reasoning entry names the model as its
  provider named it in its answer, so name a model by that id: under an alias the provider answers with another name,
  its reasoning doesn't go back.
- Reasoning that another provider wrote, in a transcript that moved between models, never goes back. Each provider's
  reasoning carries its ``OpenAICompatibleProvider/name``, so keep a provider's name the same from one version of the
  app to the next.
- A first tool call that another provider or another Gemini model made goes back to Gemini with the placeholder
  `skip_thought_signature_validator`, which Gemini takes in place of a signature.
- A `<think>` block goes back at the start of the answer's text, as it came, where the table sends reasoning back and
  to the same models.

### Store responses or not

A provider on Responses keeps each response as its `store` says, which ``OpenAICompatibleOptions/storage`` sets:

- ``OpenAICompatibleOptions/Storage/automatic`` leaves `store` out, so the provider's default applies, except on xAI,
  whose preset sends `store: false`.
- ``OpenAICompatibleOptions/Storage/stored`` sends `store: true`.
- ``OpenAICompatibleOptions/Storage/notStored`` sends `store: false`. A `reasoning` item that carries no encrypted
  reasoning is left out of the request, since the provider can't look it up by its id.

xAI's preset asks a model that reasons for each answer's reasoning encrypted, in `include`, so it goes back whether or
not xAI keeps the response. A provider you describe on Responses gets no `include`, so its reasoning items go back with
their ids for the provider to look up, and with ``OpenAICompatibleOptions/Storage/notStored`` they're left out. Chat
Completions has no `store`, and the module never sends it there.
