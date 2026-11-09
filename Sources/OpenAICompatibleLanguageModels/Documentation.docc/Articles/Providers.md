# Providers

Use a model on Gemini, Groq, DeepSeek or Mistral through its preset, and know what each preset does differently.

## Overview

A preset is a provider the module knows: a static member of ``OpenAICompatibleProvider``, such as
``OpenAICompatibleProvider/gemini``, with its provider's URL and what that provider does differently from the format.
Name the model as its provider's API does, and the preset does the rest:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleQuickStart", slice: "preset")

A preset's model takes the preset's defaults for what its details leave out, such as the efforts it accepts. Requests
leave out the members the provider refuses or doesn't document, and log them, put the token limit in the member the
provider reads, ask
for a usage chunk only where the provider needs the ask, send reasoning back the way the provider reads it, and refuse
before sending a request the provider is known to refuse. A failure throws the provider's words, with the member a
rejection names in ``OpenAICompatibleError/parameter``. An answer names the company that ran the model as its host, in
`providerMetadata.host`.

``OpenAICompatibleProvider/at(_:)`` points a preset at another address, such as a gateway in front of the provider or
one of its regional servers, and keeps everything else.

This page describes the presets as of 9 November 2026. Gemini's and Groq's were checked against their APIs on 8 and 9
November 2026, on `gemini-3.1-flash-lite`, `openai/gpt-oss-20b` and `qwen/qwen3.8-27b`, apart from what their sections
say wasn't seen there. DeepSeek's and Mistral's follow their providers' documentation and SDKs, and what users of their
APIs report, and haven't been run against their APIs yet. Providers change what they take, so
a preset can fall behind: a member a provider starts to refuse throws its error, and a member it starts to take goes
out through ``OpenAICompatibleOptions/additionalMembers``.

### At a glance

| | Gemini | Groq | DeepSeek | Mistral |
|---|---|---|---|---|
| Base URL | `https://generativelanguage.googleapis.com/v1beta/openai/` | `https://api.groq.com/openai/v1` | `https://api.deepseek.com` | `https://api.mistral.ai/v1` |
| Reasons | unless a request turns it off | when a request asks | unless a request turns it off | when a request asks |
| Efforts | `high`, `medium`, `low`, `minimal`, `none` | `high`, `medium`, `low`, `none` | `max`, `high`, `medium`, `low`, `none` | `max`, `xhigh`, `high`, `medium`, `low`, `minimal`, `none` |
| Guided generation | yes | yes, but not with tools | no | yes |
| Token limit | `max_tokens` | `max_completion_tokens` | `max_tokens` | `max_tokens` |
| Usage | asked for | sent unasked | asked for | sent unasked |
| Left out and logged | `seed`, `metadata` | `metadata` | `seed`, `metadata` | `seed` |
| Reasoning back | its thought signature, to the model that wrote it | `reasoning`, to the model that wrote it | `reasoning_content` | none |
| Refused before sending | | a schema with tools | a required tool call while the model reasons | |
| Finish words of its own | | | `insufficient_system_resource` and `aborted` fail the answer | `model_length` counts as the token limit |
| Retries | none | up to twice | up to twice | none |
| Wait for the next data | 10 minutes | 60 seconds | 10 minutes | 300 seconds |
| Host | `Google AI Studio` | `Groq` | `DeepSeek` | `Mistral` |

Every preset sends a reasoning level as `reasoning_effort`, with the nearest effort the model accepts, and leaves out
a `top_k` sampling asks for, and logs it: Gemini and Groq refuse it, and DeepSeek and Mistral don't say what it does
there. A model's own efforts often differ from its preset's: name them with `efforts:` on
``OpenAICompatibleModel/init(_:on:displayName:capabilities:contextSize:reasoning:efforts:attachments:)``. The model's
``OpenAICompatibleLanguageModel/configuration`` replaces the preset's retries and wait.

### Gemini

- **Thought signatures.** Gemini signs its reasoning, checks the signatures of the tool calls of the current turn when
  they go back, and refuses one it can't read anywhere in the transcript. Each answer's signature goes back with it, as
  `extra_content.google.thought_signature`, to the model that wrote it, as Gemini names it in its answers: on its first
  tool call, or on its message when it has no call. A first tool call that another provider or another model made goes
  back with the placeholder `skip_thought_signature_validator`, which Gemini takes in place of a signature, and a text
  answer of another model's goes back without one. So name a model by the id Gemini answers with, such as
  `gemini-3.1-flash-lite`: under an alias it answers with another name, its signatures don't go back. With parallel
  calls, Gemini signs only the first, so the others go back without one; parallel calls weren't seen.
- **Reasoning text.** `gemini-3.1-flash-lite` sent none, also when asked for its thoughts, so its answers' reasoning
  entries hold only their signatures. It took the effort `none`; what `none` does on a Gemini 3 model isn't known.
- **A schema with tools.** Gemini takes both, and once answered with a call to the session's tool whose arguments held
  the schema's answer. In a session with tools and a schema, a tool may be called with arguments it can't use.
- **Failures.** A missing key is a 400 with the code ``OpenAICompatibleError/Code/authentication``, as a 401 is, and
  so is an invalid key, in the Gemini API's words for one, which weren't seen. A rate limit's reset date comes from the
  wait Gemini names in its body, since it sends no `Retry-After`. A member Gemini doesn't know, an effort the model
  doesn't take and a temperature out of range name the member in ``OpenAICompatibleError/parameter``. An overloaded
  model's 503 isn't sent again. A prompt over the model's context throws `LanguageModelError.contextSizeExceeded`
  with the sizes Gemini names, in words that weren't seen.
- **Images** at a web address are taken. Gemini has no Responses format.

### Groq

- **Efforts** differ by model: `openai/gpt-oss-20b` takes `high`, `medium` and `low`, and `qwen/qwen3.8-27b` takes
  `none` as well, as Groq's 400 for any other says.
- **Reasoning** arrives as each delta's `reasoning`, and goes back as the assistant message's `reasoning`, to the model
  that wrote it only, since a model that doesn't reason may refuse it. Groq took it on both models checked; whether it
  changes their answers isn't known.
- **Usage** comes on an answer's last chunk without the ask, which the preset doesn't send.
- **A schema with tools** is refused before it's sent with `LanguageModelError.unsupportedCapability`, since Groq
  answers a request with both with a 400. A schema alone works, streamed.
- **Failures in the stream.** A guided answer that Groq finds breaks its schema ends the stream with an error, which
  throws `GeneratedContent.ParsingError` with what the model generated, if anything, as its raw content. A request that
  requires a tool call, answered without one, throws ``OpenAICompatibleError`` with the code `tool_use_failed`.
- **Other failures.** A member Groq doesn't take, an effort the model doesn't take and a temperature out of range name
  the member in ``OpenAICompatibleError/parameter``. A request over the account's tokens a minute, reported as a 413
  and not seen, throws ``OpenAICompatibleError`` rather than a rate limit, since no wait lets that request through.
- **Images** under 32 pixels a side are refused by Groq with a 400.

### DeepSeek

- **Reasoning** is on unless a request turns it off. A request that sets a reasoning level also sends `thinking`, which
  DeepSeek reads over the effort: disabled for the level ``FoundationModels/ContextOptions/ReasoningLevel/off`` and
  enabled for any other. A model you describe with `reasoning: .unsupported` sends `thinking` disabled with every
  request. DeepSeek takes `medium` as `high`, so the reasoning level `.moderate` reasons as hard as `.deep`.
- **Left out.** `seed` and request metadata, which DeepSeek's documentation doesn't list.
- **Reasoning back.** DeepSeek's reasoning goes back as the assistant message's `reasoning_content`, which DeepSeek
  needs on every earlier answer of a request with tools. An answer with no reasoning of DeepSeek's own, such as one
  another provider wrote or one with reasoning off, goes back without it, and DeepSeek may refuse a request with tools
  that has one.
- **No guided generation.** DeepSeek takes no JSON Schema for an answer, so a model on it doesn't list guided
  generation, and Foundation Models refuses a request with a schema before it's sent.
- **A required tool call** is refused before it's sent while the model reasons, since DeepSeek takes one only with
  reasoning off: set the reasoning level to ``FoundationModels/ContextOptions/ReasoningLevel/off``.
- **Answers cut short.** An answer DeepSeek's servers stop, which ends with `insufficient_system_resource` or
  `aborted`, throws ``OpenAICompatibleError`` with the code `server` rather than ending as complete.
- **Content filter.** A request DeepSeek's filter refuses throws `LanguageModelError.guardrailViolation`. DeepSeek is
  reported to refuse every later request whose transcript still carries the content, so it has to leave the transcript
  for the conversation to go on.
- **Request ids** are read from `request-id`, `x-request-id` or `x-deepseek-request-id`.

### Mistral

- **Reasoning** arrives in the answer's thinking parts, and doesn't go back on later turns.
- **The model's length.** An answer that ends with `model_length`, which Mistral sends when it reaches the model's
  context, counts as one that reached its token limit: a guided answer or tool calls cut there throw, and a text
  answer ends with `model_length` as its ``OpenAICompatibleResponseMetadata/finishReason``.
- **The seed** is left out, since Mistral's member for it is `random_seed`, and `seed` is reported to be refused; send
  `random_seed` through ``OpenAICompatibleOptions/additionalMembers`` instead. Request metadata goes out.
- **Usage** comes on an answer's last chunk. Mistral is reported to refuse the ask for a usage chunk, so the preset
  doesn't send it.
- **Tool call ids** of nine letters and digits are reported to be the only ones Mistral takes, so a transcript whose
  calls another provider made may fail there, with Mistral's code in ``OpenAICompatibleError/code``.
- **Regional servers** are `.mistral.at(_:)` with `https://api.eu.mistral.ai/v1` or `https://api.us.mistral.ai/v1`.

### What a preset can't see

A provider that ignores a member, rather than refusing it, answers as if it were never sent, and nothing in its
answer says so. A setting that a model of a preset's provider doesn't take, though others do, such as an effort,
throws the provider's error, with the member it names when it names one.
