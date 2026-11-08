# Reasoning with OpenAI models

See which models reason, what a reasoning level becomes, and how reasoning comes back and goes out again.

## Overview

Foundation Models sets how much a model reasons with `ContextOptions.ReasoningLevel`, as
<doc:/LanguageModels/ReasoningLevels> describes. An OpenAI model's ``OpenAIModel/reasoning`` says whether it reasons at
all, and its ``OpenAIModel/reasoningEfforts`` which levels it accepts:

@Snippet(path: "swift-language-models/Snippets/OpenAIReasoning", slice: "level")

### Which models reason

``OpenAIModel/reasoning`` is one of these ``ModelReasoning`` values:

- `unsupported`: the model doesn't reason, such as GPT-4.1, and a request sends no `reasoning`.
- `onByDefault`: the model accepts `none`, so a request can turn its reasoning off, such as GPT-6 Luna and GPT-5.5.
  The catalog records it as reasoning by default, since OpenAI's API description gives `medium` as the default effort,
  although a model's own default can differ, as GPT-5.4 mini's does.
- `mandatory`: the model always reasons, since it doesn't accept `none`, such as GPT-6 Astra and GPT-5.5 Pro.

A model that reasons has `.reasoning` in its ``OpenAIModel/capabilities``. Its
``OpenAIModel/defaultReasoningEffort`` is the default effort that OpenAI's API description gives, `medium` for every
model that accepts it, and not always the effort the model uses when a request doesn't set one.

### What a level becomes

- A model's own level, from ``DetailedLanguageModel/reasoningLevel(_:)`` or
  ``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)``, goes out as `reasoning.effort` as it is.
  `off` goes out as `none`, OpenAI's word for it.
- Apple's `.light`, `.moderate` and `.deep` ask for `low`, `medium` and `high`, and go out as the nearest effort the
  model accepts, the lower one on a tie. GPT-5 Pro accepts only `high`, so `.light`, `.moderate` and `.deep` all go out
  as `high`. A level sent as another effort is logged, and a debug build shows a runtime warning for it.
- Only `off` turns reasoning off. A model asked to reason keeps reasoning. A model that always reasons gets its lowest
  effort for `off` instead, such as `low` for GPT-6 Astra and `minimal` for GPT-5.
- A request that sets no level leaves `reasoning.effort` out, so the model uses its default effort.
- A model that doesn't reason gets no `reasoning`, whatever the level.

### Sampling while a model reasons

A model that reasons takes `temperature` and `top_p` only while its effort is `none`. A request that sets another
level leaves them out, even when the model lists them, as GPT-5.4 does, and so does any request to a model that always
reasons, such as GPT-5 nano. A request that sets no level sends them to a model that can stop reasoning, since the
catalog's ``OpenAIModel/defaultReasoningEffort`` doesn't always match the model's own: GPT-5.4 mini takes them, although
its catalog default is `medium`. OpenAI rejects them when the model's default isn't `none`. Each setting left out is
logged, and a debug build shows a runtime warning for it.

### Instructions

The instructions go out as a `developer` message to a model that reasons, and as a `system` message to one that
doesn't.

### Read the model's reasoning

The model's reasoning arrives in the transcript as a reasoning entry, before the answer's text. Reasoning that arrives
after the answer's text starts, as between a `commentary` message and the final answer, isn't shown, but its
`reasoning` items still go back on later turns. The entry's text is the summary of its reasoning that the model writes,
when ``OpenAIOptions/reasoningSummary`` asks for one, or the model's reasoning text, when the model sends it. Each part
of a summary starts after a blank line. The answer's usage counts the reasoning tokens in `output.reasoningTokenCount`.

``OpenAIOptions/reasoningSummary`` has no default: without one, the request asks for no summary, and the reasoning entry
has no text, but still carries the reasoning, encrypted, so it goes back on later turns.
``OpenAIOptions/ReasoningSummary/auto`` asks for the most detailed summary the model writes, and
``OpenAIOptions/ReasoningSummary/concise`` and ``OpenAIOptions/ReasoningSummary/detailed`` for a short and a detailed
one. It goes out as `reasoning.summary`:

@Snippet(path: "swift-language-models/Snippets/OpenAIReasoning", slice: "summary")

### Reasoning on later turns

Every request to a model that reasons asks for its reasoning encrypted, with `include` set to
`reasoning.encrypted_content`. The answer's `reasoning` items, as OpenAI sent them, become the reasoning entry's
signature. Each request sends the transcript, and with it the reasoning of earlier answers:

- An answer's `reasoning` items go back as they came, in their places between its messages, function calls and server
  tools' calls.
- They go back only to the model that wrote them, or to the model it's a dated snapshot of, since encrypted reasoning
  suits only that model. The reasoning entry names the model that answered, such as `gpt-5-nano-2025-08-07`, so its
  reasoning goes back to `gpt-5-nano` too, and not to another model the session moves to.
- An answer with nothing after its reasoning, such as one cut off while it reasoned, sends no reasoning back.
- Reasoning that another provider module wrote, in a transcript that moved between models, isn't sent.

### Store responses or not

``OpenAIOptions/storage`` says whether OpenAI keeps each response, as `store`:

- ``OpenAIOptions/Storage/automatic`` leaves `store` out, so OpenAI's default applies, which keeps responses.
- ``OpenAIOptions/Storage/stored`` sends `store: true`.
- ``OpenAIOptions/Storage/notStored`` sends `store: false`. A `reasoning` item that carries no encrypted reasoning is
  left out of the request, since OpenAI can't look it up by its id.

The package sends the whole transcript, and every reasoning item goes back encrypted, so later turns work the same
whether or not OpenAI keeps the response, apart from a generated image, whose call goes back only while OpenAI keeps
the responses, as <doc:ServerTools> describes. A session that moves from stored to not stored responses keeps answering.

### Message phases

A model can write an answer as several messages, each with a `phase`, such as `commentary` or `final_answer`. The
answer's text joins them, and the entry that ends the answer keeps the `phase` of each message, with the length of its
text, which ``OpenAIResponseMetadata/messages`` reads as a list of ``OpenAIResponseMetadata/Message`` values, each with
its ``OpenAIResponseMetadata/Message/phase`` and ``OpenAIResponseMetadata/Message/length``. On later turns, each message
goes back as an `assistant` message of its own, with its `phase`, as OpenAI asks. When the lengths don't add up to the
answer's text, as when the text changed, the messages held out of the text go back first, then the whole text as one
message with the phase of the last message shown in it.

A guided answer decodes only its first message with no phase or the `final_answer` phase. The text of its other
messages, such as a `commentary` preamble, stays out of the answer's text, and
``OpenAIResponseMetadata/Message/heldText`` keeps it, with a ``OpenAIResponseMetadata/Message/length`` of 0, so it goes
back in its place.

### OpenAI's guides

- [Reasoning models](https://developers.openai.com/api/docs/guides/reasoning), on efforts, summaries and encrypted
  reasoning
- [Conversation state](https://developers.openai.com/api/docs/guides/conversation-state), on `store` and message phases
