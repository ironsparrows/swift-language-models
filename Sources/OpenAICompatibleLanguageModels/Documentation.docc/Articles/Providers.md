# Providers

Use a model on Gemini, Groq, DeepSeek, Mistral or xAI, or on an Ollama, LM Studio or vLLM server, through its preset,
and know what each preset does differently.

## Overview

A preset is a provider the module knows: a static member of ``OpenAICompatibleProvider``, such as
``OpenAICompatibleProvider/gemini``, with its provider's URL and what that provider does differently from the format.
Name the model as its provider's API does, and the preset does the rest:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleQuickStart", slice: "preset")

A preset's model takes the preset's defaults for what its details leave out, such as the efforts it accepts. Requests
leave out the members the tables below list for the provider, ones it refuses, ignores or doesn't document, and log
them, put the token limit in the member the provider reads, ask for a usage chunk only where the provider needs the
ask, send reasoning back the way the provider reads it, and refuse before sending a request the provider is known to
refuse. A failure throws the provider's words, with the member a rejection names in
``OpenAICompatibleError/parameter``. An answer names the company that ran the model as its host, in
`providerMetadata.host`; a server's preset names none.

``OpenAICompatibleProvider/at(_:)`` points a preset at another address, such as a gateway in front of the provider, one
of its regional servers, or a server on another Mac or port, and keeps everything else.

This page describes the presets as of 9 November 2026. Gemini's, Groq's and Ollama's ran against Gemini's free tier,
Groq's free plan and Ollama 0.40.15 on 8 and 9 November 2026, on `gemini-3.1-flash-lite`, `openai/gpt-oss-20b`,
`qwen/qwen3.8-27b` and `qwen3:0.6b`: a text answer, a tool round, a guided answer, an answer that reasons and a failure
went through each of the three presets and are kept as the module's recorded tests, and each preset's live tests ran
against its provider. The rest of what this page says of the three was seen in requests sent to them by hand on those
days, outside the module's tests, such as Ollama's answers on `qwen3.5:4b` to images, schemas and a required tool call;
each provider's part below says what wasn't seen. Of xAI's, only the error for an incorrect key was seen, in a request
sent by hand. DeepSeek's, Mistral's and xAI's follow their providers' documentation and SDKs, LM Studio's its
documentation, and vLLM's its server's source at v0.33.0 and its documentation, with what their users report, and
haven't been run against their APIs or servers yet. Providers change what they take, so a preset can fall behind: a
member a provider starts to refuse throws its error, and a member it starts to take goes out through
``OpenAICompatibleOptions/additionalMembers``.

### At a glance

| | Gemini | Groq | DeepSeek | Mistral | xAI |
|---|---|---|---|---|---|
| Base URL | `https://generativelanguage.googleapis.com/v1beta/openai/` | `https://api.groq.com/openai/v1` | `https://api.deepseek.com` | `https://api.mistral.ai/v1` | `https://api.x.ai/v1` |
| Format | Chat Completions | Chat Completions | Chat Completions | Chat Completions | Responses |
| Reasons | unless a request turns it off, on a model that can | when a request asks | unless a request turns it off | when a request asks | unless a request turns it off |
| Efforts | `high`, `medium`, `low`, `minimal`, `none` | `high`, `medium`, `low`, `none` | `max`, `high`, `medium`, `low`, `none` | `max`, `xhigh`, `high`, `medium`, `low`, `minimal`, `none` | `xhigh`, `high`, `medium`, `low`, `none` |
| Guided generation | yes | yes, but not with tools | no | yes | yes |
| Token limit | `max_tokens` | `max_completion_tokens` | `max_tokens` | `max_tokens` | `max_output_tokens` |
| Usage | asked for | sent unasked | asked for | sent unasked | sent unasked |
| `top_k` | left out | left out | left out | left out | sent |
| Left out and logged | `seed`, `metadata` | `metadata` | `seed`, `metadata` | `seed` | `metadata` |
| Cache key | left out and logged | left out and logged | left out and logged | sent | sent |
| Reasoning back | its thought signature, to the model that wrote it | `reasoning`, to the model that wrote it | `reasoning_content` | none | its encrypted reasoning, to the model that wrote it |
| Refused before sending | | a schema with tools | a required tool call while the model reasons | | |
| Finish words of its own | | | `insufficient_system_resource` and `aborted` fail the answer | `model_length` counts as the token limit | |
| Responses kept | | | | | only when the options ask |
| Retries | none | up to twice | up to twice | none | up to twice, only after a rate limit |
| Wait for the next data | 10 minutes | 60 seconds | 10 minutes | 300 seconds | 10 minutes |
| Host | `Google AI Studio` | `Groq` | `DeepSeek` | `Mistral` | `xAI` |

The servers' presets reach a server at its default local address, and take no key unless the server asks for one;
`at(_:)` reaches one elsewhere, as <doc:Attachments#Reach-a-server-on-your-own-network> describes for a device:

| | Ollama | LM Studio | vLLM |
|---|---|---|---|
| Base URL | `http://localhost:11434/v1/` | `http://localhost:1234/v1` | `http://localhost:8000/v1` |
| Efforts | `max`, `xhigh`, `high`, `medium`, `low`, `minimal`, `none` | `xhigh`, `high`, `medium`, `low`, `minimal`, `none` | `max`, `xhigh`, `high`, `medium`, `low`, `minimal`, `none` |
| Token limit | `max_tokens` | `max_tokens` | `max_completion_tokens` |
| `top_k` | left out | left out | sent |
| Left out and logged | `metadata`, `tool_choice` | `metadata` | `metadata` |
| Cache key | left out and logged | left out and logged | left out and logged |
| Reasoning back | `reasoning`, to the model that wrote it | none | `reasoning`, to the model that wrote it |
| Refused before sending | an image at a web address, a required tool call | | |
| Finish words of its own | | | `abort` fails the answer, `repetition` counts as the token limit |
| Retries | none | up to twice | up to twice |
| Wait for the next data | 10 minutes | 10 minutes | 10 minutes |

On every server, a model is taken to reason only when a request asks it to, and to take tools, guided generation and
images, unless its details say otherwise, and requests ask for a usage chunk. A server runs models of every kind, so
describe each one, such as whether it reasons. Ollama lets a model that thinks reason when a request sends no effort,
unless the model's own settings turn its thinking off by default: `qwen3:0.6b` reasoned so in the module's recordings,
so describe such a model with `reasoning: .onByDefault`.

Every Chat Completions preset sends a reasoning level as `reasoning_effort`, and xAI's in `reasoning`, with the nearest
effort the model accepts. A `top_k` that sampling asks for is left out and logged where the table says so: Gemini and
Groq refuse it, Ollama ignores it, and DeepSeek, Mistral and LM Studio don't say what it does there. A model's own
efforts often differ from its preset's: name them with `efforts:` on
``OpenAICompatibleModel/init(_:on:displayName:capabilities:contextSize:reasoning:efforts:attachments:)``. The model's
``OpenAICompatibleLanguageModel/configuration`` replaces the preset's retries and wait.

Each Chat Completions request of a session repeats the one before it byte for byte up to its new turn, so a provider
that caches a repeated prefix can read it from its cache, and the answer's `usage.input.cachedTokenCount` counts the
tokens it read there, as the provider reports them in `prompt_tokens_details.cached_tokens`, or in Responses
`input_tokens_details.cached_tokens`; a provider that reports them in another member, such as a `cached_tokens` beside
the others, reads as 0. ``OpenAICompatibleOptions/cacheKey`` goes out as `prompt_cache_key` where the tables say it's
sent, and to a provider the app describes itself, which may refuse it as a member it doesn't know; the other presets
leave it out and log it, since their providers refuse it, ignore it or don't document it. <doc:Caching> says what each
provider caches.

### Gemini

- **Thought signatures.** Gemini signs its reasoning, checks the signatures of the tool calls of the current turn when
  they go back, and refuses one it can't read anywhere in the transcript. Each answer's signature goes back with it, as
  `extra_content.google.thought_signature`, to the model that wrote it, as Gemini names it in its answers: on its first
  tool call, or on its message when it has no call. A first tool call that another provider or another model made goes
  back with the placeholder `skip_thought_signature_validator`, which Gemini takes in place of a signature, and a text
  answer of another model's goes back without one; `gemini-3.5-flash-lite` went on with a tool round from a transcript
  `gemini-3.1-flash-lite` wrote, its calls carrying the placeholder. So name a model by the id Gemini answers with, such
  as `gemini-3.1-flash-lite`: under an alias it answers with another name, its signatures don't go back. With parallel
  calls, Gemini signs only the first, so the others go back without one, which Gemini takes.
- **Reasoning text.** `gemini-3.1-flash-lite` sent none, also when asked for its thoughts, so its answers' reasoning
  entries hold only their signatures. It took the effort `none`, which by Gemini's documentation turns reasoning off on
  Gemini 2.5 Flash and Flash-Lite, while Gemini 2.5 Pro and Gemini 3 models can't turn it off, so on them the level
  ``FoundationModels/ContextOptions/ReasoningLevel/off`` doesn't stop the model reasoning.
- **A schema with tools.** Gemini takes both, and once answered with a call to the session's tool whose arguments held
  the schema's answer. In a session with tools and a schema, a tool may be called with arguments it can't use.
- **Usage.** Gemini reports no reasoning tokens, and leaves them out of the output tokens, counting them only in the
  total: at the effort `high`, `gemini-3.1-flash-lite` reported 15 input and 290 output tokens with a total of 1,184.
  So an answer's usage counts the total's tokens beyond the input and the output as its reasoning, among its output
  tokens: 1,169 output tokens, 879 of them reasoning, for that answer.
- **Failures.** A missing key is a 400 with the code ``OpenAICompatibleError/Code/authentication``, as a 401 is, and
  so is an invalid key, which Gemini answers with "Please pass a valid API key". A rate limit's reset date comes from
  the wait Gemini names in its body, since it sends no `Retry-After`. A member Gemini doesn't know, an effort the model
  doesn't take and a temperature out of range name the member in ``OpenAICompatibleError/parameter``. An overloaded
  model's 503 isn't sent again. A prompt over the model's context throws `LanguageModelError.contextSizeExceeded`
  with the sizes Gemini names, in words that weren't seen: on the free tier, whose limit is 250,000 input tokens a
  minute, Gemini answers such a prompt with a 429 first, so it throws `LanguageModelError.rateLimited`, although no wait
  lets a single prompt over that limit through.
- **Caching.** Gemini caches a repeated prefix by itself: after the same instructions of about 6,000 tokens, a second
  request to `gemini-3.1-flash-lite` read 2,033 of its 6,030 input tokens from the cache, and the first reported none.
  Gemini reports them on the answer's last chunk. It takes no cache key: `prompt_cache_key` is a 400, so requests leave
  ``OpenAICompatibleOptions/cacheKey`` out.
- **Images** at a web address are taken. Gemini has no Responses format.

### Groq

- **Efforts** differ by model: `openai/gpt-oss-20b` takes `high`, `medium` and `low`, and `qwen/qwen3.8-27b` takes
  `none` as well, as Groq's 400 for any other says.
- **Reasoning** arrives as each delta's `reasoning`, and goes back as the assistant message's `reasoning`, to the model
  that wrote it only, since a model that doesn't reason may refuse it. Groq took it on both models checked, with tool
  calls and without; whether it changes their answers isn't known. Asked for two calls at once, `openai/gpt-oss-20b`
  made one in each of two rounds.
- **Usage** comes on an answer's last chunk without the ask, which the preset doesn't send.
- **A schema with tools** is refused before it's sent with `LanguageModelError.unsupportedCapability`, since Groq
  answers a request with both with a 400. A schema alone works, streamed.
- **Failures in the stream.** A guided answer that Groq finds breaks its schema ends the stream with an error, which
  throws `GeneratedContent.ParsingError` with what the model generated, if anything, as its raw content. A request that
  requires a tool call, answered without one, throws ``OpenAICompatibleError`` with the code `tool_use_failed`, and so
  does a call Groq can't read: `qwen/qwen3.8-27b`'s calls failed that way in 2 of 9 runs of two tool rounds.
- **Other failures.** A member Groq doesn't take, an effort the model doesn't take and a temperature out of range name
  the member in ``OpenAICompatibleError/parameter``. A request over the account's tokens a minute, which on the free
  plan is 8,000 for `openai/gpt-oss-20b`, is a 413 with the code `rate_limit_exceeded` and a `Retry-After`. It throws
  ``OpenAICompatibleError`` rather than a rate limit, since no wait lets that request through: a smaller one goes once
  the wait in ``OpenAICompatibleError/retryAfter`` has passed. A refused key is a 401 with the code
  ``OpenAICompatibleError/Code/invalidAPIKey``.
- **Caching.** Groq's documentation says `openai/gpt-oss-20b` and `openai/gpt-oss-120b` cache a repeated prefix, but
  on the free plan neither reported any cached tokens for a prompt of about 3,000 tokens sent again seconds later,
  streamed or not. Groq takes no cache key: `prompt_cache_key` is a 400, so requests leave
  ``OpenAICompatibleOptions/cacheKey`` out.
- **Images** under 32 pixels a side are refused by Groq with a 400.

### DeepSeek

- **Reasoning** is on unless a request turns it off. A request that sets a reasoning level also sends `thinking`, which
  DeepSeek reads over the effort: disabled for the level ``FoundationModels/ContextOptions/ReasoningLevel/off`` and
  enabled for any other. A model you describe with `reasoning: .unsupported` sends `thinking` disabled with every
  request. DeepSeek takes `medium` as `high`, so the reasoning level `.moderate` reasons as hard as `.deep`.
- **Left out.** `seed`, request metadata and a cache key, which DeepSeek's documentation doesn't list.
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
- **Caching.** ``OpenAICompatibleOptions/cacheKey`` goes out as `prompt_cache_key`, which Mistral's documentation ties
  its cache to. Mistral documents cached tokens in `prompt_tokens_details.cached_tokens`, which the usage reads; ones
  it sends only as `num_cached_tokens` or in `prompt_token_details`, as it's reported to, read as 0. Neither was seen.
- **Regional servers** are `.mistral.at(_:)` with `https://api.eu.mistral.ai/v1` or `https://api.us.mistral.ai/v1`.

### xAI

- **Responses.** xAI's Chat Completions is deprecated, so the preset speaks Responses. Instructions go in the
  `developer` role, which xAI's API lists; how its models follow them wasn't seen.
- **Kept responses.** Requests send `store: false` unless ``OpenAICompatibleOptions/storage`` asks for stored responses,
  which xAI keeps for 30 days. Every request to a model that reasons asks for each answer's reasoning encrypted, in
  `include`, so the reasoning goes back on later turns whether or not xAI keeps the response: each request sends the
  whole transcript, never a stored response's id.
- **Efforts** differ by model: xAI's newest models can't turn reasoning off, and some don't take `xhigh`. xAI lists a
  model's own at `GET /v1/language-models/{id}`, in `capabilities.reasoning_effort`.
- **Sampling.** A `top_k` that sampling asks for goes out, which xAI documents. A seed is left out and logged, since
  xAI's Responses has no `seed`.
- **The token limit**, `max_output_tokens`, caps the visible answer, not the reasoning or the tool calls.
- **Left out.** Request metadata, which xAI doesn't support.
- **Retries and waits.** A failed request is sent again only after a rate limit, or when its `x-should-retry` is `true`:
  xAI may bill a request that failed once its work began, such as one with a 5xx status, or one whose connection failed
  after it was sent.
  Requests wait up to 10 minutes for the next data, since a model that reasons can send nothing for minutes.
- **Prompt cache.** xAI routes requests that share a `prompt_cache_key` to the same cache, which
  ``OpenAICompatibleOptions/cacheKey`` sends: ``OpenAICompatibleOptions/CacheKey/session`` keeps each conversation on
  one key. This wasn't seen.
- **Failures.** An incorrect key is a 400 with xAI's code `invalid-argument`, which has the code
  ``OpenAICompatibleError/Code/authentication``, as a 401 has; it was seen on xAI's Chat Completions endpoint.

### Ollama

- **Efforts.** Ollama maps each effort onto the model's own levels: `none` turns reasoning off, and on a model without
  levels of its own, `minimal` counts as `low` and `xhigh` as `max`. On `qwen3:0.6b`, only `none` changed what the
  model did.
- **Reasoning** arrives as each delta's `reasoning`, and goes back as the assistant message's `reasoning`, with its tool
  calls, to the model that wrote it only, since another model on the server would read it as its own. Ollama took it on
  later turns, with tool calls and without.
- **Left out.** Request metadata, `tool_choice`, `top_k` and a cache key, which Ollama ignores. It ignores
  `max_completion_tokens` too, so the token limit goes as `max_tokens`.
- **An image at a web address** is refused before it's sent with `LanguageModelError.unsupportedTranscriptContent`,
  since Ollama answers one with a 400: attach the image itself. Every image sent as data goes as JPEG, which Ollama
  takes.
- **A required tool call** is refused before it's sent with `LanguageModelError.unsupportedCapability`, since Ollama
  ignores `tool_choice`: the models checked answered such a request without a call.
- **Usage** comes only when asked, so the preset asks. Ollama reported no reasoning tokens, so a model's reasoning
  counts among the output tokens alone.
- **Caching.** The loaded model reuses what it read of a repeated prefix until it's unloaded: after the same
  instructions of about 2,000 tokens, a second request read 2,020 of its 2,060 input tokens from the cache.
- **Waits and retries.** A failed request isn't sent again, and requests wait up to 10 minutes for the next data,
  since loading a model can take a while. An ``OpenAICompatibleConfiguration/idleTimeout`` of `nil` waits as long as
  the URL session's own timeout, which is 60 seconds for `URLSession.shared`.
- **A long conversation** loses its oldest messages on Ollama's side, with no error, once it's longer than the model's
  context: Ollama keeps the system messages and the latest one, which was read from Ollama's source. A single prompt
  over the context is cut too: Ollama 0.40.15 loaded `qwen3:0.6b` with a context of 32,768 tokens, and read 16,386
  tokens of a prompt of 60,000 words, with no error. This format can't raise a model's context; a Modelfile's `num_ctx`
  does.
- **Failures.** Ollama sends no request id. A model it doesn't have is a 404, with the code
  ``OpenAICompatibleError/Code/notFound``.
- **Server options**, such as `keep_alive`, which Ollama's source reads in this format, go out through
  ``OpenAICompatibleOptions/additionalMembers``; `keep_alive` wasn't sent here.

### LM Studio

- **Not run.** LM Studio's server isn't open source, and none ran here, so the preset follows its documentation and
  what its users report.
- **Reasoning** arrives as `reasoning_content` or `reasoning`, depending on the model, and doesn't go back on later
  turns, since nothing shows LM Studio reads it there.
- **Efforts** are reported to have no effect in this format, and LM Studio is reported to refuse `max`, which the
  preset's efforts leave out.
- **Left out.** Request metadata and a cache key, which LM Studio's documentation doesn't list, and `top_k`, which it
  lists for this format without saying what it does there.
- **Tool calls.** LM Studio is reported to make a required call only with its llama.cpp engine, and to answer one
  empty there too.
- **A prompt over the model's context** is cut in the middle to fit, with no error, by LM Studio's default setting.
  With the model's context overflow set to stop at the limit, LM Studio is reported to end the stream with an error,
  after its HTTP 200, which throws `LanguageModelError.contextSizeExceeded` with the sizes LM Studio names.
- **Tool calls as text.** LM Studio is reported to send some models' tool calls as `[TOOL_REQUEST]` text, which reaches
  the app as text.
- **A token.** A server that asks for one, which LM Studio allows since 0.4.0, takes it with
  ``OpenAICompatibleAuthentication/apiKey(_:)``.
- **Caching.** LM Studio is reported to send no cached tokens in this format, so its cache hits read as 0.
- **Server options**, such as `ttl`, go out through ``OpenAICompatibleOptions/additionalMembers``.

### vLLM

- **Not run.** No vLLM server ran here, so the preset follows its server's source at v0.33.0 and its documentation.
- **Tools** need a server started with `--enable-auto-tool-choice` and a `--tool-call-parser`: without both, a request
  with tools is a 400 whose message names a flag, which throws ``OpenAICompatibleError``. gpt-oss models need neither
  flag, and a model with Mistral's tokenizer takes the request without them but sends its calls as text.
- **Reasoning** arrives as each delta's `reasoning` from a server started with `--reasoning-parser`, and goes back as
  the assistant message's `reasoning`, to the model that wrote it only. vLLM answers with the first name the server
  serves the model under, so name the model by that one: under another of its names, its reasoning doesn't go back.
  Without a parser, reasoning stays in the text: a text that opens with a `<think>` or `<thinking>` block has the block
  read as reasoning, which goes back in the text as it came, to the same model, while a template that opens the block in
  the prompt leaves the reasoning in the answer's text.
- **Efforts** reach the model's chat template, which may ignore them; vLLM refuses any other word. A template that
  reads `thinking` rather than `enable_thinking` takes it in `chat_template_kwargs`, through
  ``OpenAICompatibleOptions/additionalMembers``.
- **Sampling.** A `top_k` that sampling asks for goes out. Greedy sampling goes as temperature 0, which vLLM samples
  greedily.
- **The token limit** goes as `max_completion_tokens`, which vLLM reads over `max_tokens`.
- **Left out.** Request metadata and a cache key, which vLLM ignores.
- **Finish words.** An answer that ends with `abort`, which vLLM sends for a request it stopped serving, throws
  ``OpenAICompatibleError`` with the code `server` rather than ending as complete. One that ends with `repetition`,
  which vLLM sends when the repetition detection a request turns on stops a model that repeats itself, counts as one
  that reached its token limit: a guided answer or tool calls cut there throw, and a text
  answer ends with `repetition` as its ``OpenAICompatibleResponseMetadata/finishReason``.
- **Failures in the stream** arrive as an error event whose `code` is the status, which the error's
  ``OpenAICompatibleError/status`` takes.
- **Request ids** come only from a server started with `--enable-request-id-headers`.
- **Caching.** Cached tokens come only from a server started with `--enable-prompt-tokens-details`, and read as 0
  otherwise; the tokens vLLM writes to its cache, as `created_cache_tokens`, aren't read.
- **Images** at a web address are fetched by the server, which waits up to 5 seconds for one by default.

### What a preset can't see

A provider that ignores a member, rather than refusing it, answers as if it were never sent, and nothing in its
answer says so; Ollama and vLLM ignore any member they don't know. A server that cuts a long conversation to fit the
model's context, as Ollama does and LM Studio does by default, answers as if the cut messages were never sent. A
setting that a model of a preset's provider doesn't take, though others do, such as an effort, throws the provider's
error, with the member it names when it names one.
