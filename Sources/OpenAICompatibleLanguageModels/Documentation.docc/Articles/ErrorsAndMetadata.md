# Errors and metadata

Handle failures, and read what a provider reports about each answer.

## Overview

Rate limits, oversized contexts, content filters, refusals, timeouts and images a provider can't use throw Foundation
Models' own `LanguageModelError`, so the same `catch` works for every model. Anything else, such as a rejected API key
or a quota that ran out, throws ``OpenAICompatibleError``, which names the provider that failed in
``OpenAICompatibleError/providerName`` and keeps its ``OpenAICompatibleError/message``, ``OpenAICompatibleError/status``,
``OpenAICompatibleError/code``, ``OpenAICompatibleError/errorType``, ``OpenAICompatibleError/parameter``,
``OpenAICompatibleError/requestID`` and ``OpenAICompatibleError/retryAfter``:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleErrors", slice: "errors")

A connection that fails, other than by timing out, throws its `URLError`. For a server on the same Mac, that usually
means it isn't running, or listens on another port than the provider's URL names.

### What a failure becomes

| The provider's failure | Thrown |
|---|---|
| `context_length_exceeded`, or a 400 or a failure in the stream whose message names the context or, for a preset, its words for an oversized prompt | `LanguageModelError.contextSizeExceeded`, with the sizes when the message names them |
| 429, or `rate_limit_exceeded` on any status but 413 | `LanguageModelError.rateLimited`, with the reset date from `retry-after-ms` or `Retry-After`, or from the wait Gemini names in its body. On Gemini's free tier, a single prompt over its input tokens a minute is a 429 too, which throws this although no wait lets that prompt through |
| A 413 with `rate_limit_exceeded`, such as Groq's for a request over the account's tokens a minute | ``OpenAICompatibleError``, since no wait lets that request through |
| A 402, or `insufficient_quota` as the code or type | ``OpenAICompatibleError`` with ``OpenAICompatibleError/isQuotaExhausted`` set, even when it arrives as a 429, since waiting doesn't clear it |
| `content_policy_violation`, `content_filter`, or DeepSeek's words for content its filter refused | `LanguageModelError.guardrailViolation` |
| A refusal in the answer | `LanguageModelError.refusal` |
| 408, 504, 524, or a timed-out connection | `LanguageModelError.timeout` |
| `invalid_image`, `image_too_large` and the other codes of an image the provider can't use | `LanguageModelError.unsupportedTranscriptContent`, naming the entries with images |
| A guided answer Groq finds breaks its schema | `GeneratedContent.ParsingError`, with what the model generated as its raw content |
| A stream cut off before its end, an event that can't be read, a tool call without a name, or with arguments that are neither a whole JSON object nor only whitespace, or that reached the token limit | ``OpenAICompatibleError`` with ``OpenAICompatibleError/Code/invalidResponse`` |
| Anything else | ``OpenAICompatibleError`` |

The code is the provider's, when its error names one, such as `invalid_api_key` or `tool_use_failed`; otherwise the
package's word for the HTTP status, such as ``OpenAICompatibleError/Code/authentication`` for a 401 or
``OpenAICompatibleError/Code/notFound`` for a 404; otherwise the provider's error type, for a status with no word of its
own, such as a 400. A failure in the stream that names neither has ``OpenAICompatibleError/Code/server``. A preset's
words for a refused key make a 400 ``OpenAICompatibleError/Code/authentication``, as Gemini's and xAI's are. Each
provider spells its errors its own way, so the module reads an error nested under `error`, in a list, flat, as text, or
as a `detail` list, and takes the member a message quotes, such as Gemini's `Unknown name "x"`, as the
``OpenAICompatibleError/parameter`` when the body names none. A body with no error the module reads gives up to 1,000
characters of its text as the message, or for an empty or HTML body, the status with its content type and size.

An error in the stream arrives after HTTP 200, so its ``OpenAICompatibleError/status`` is the one its error names, if
any, such as vLLM's `code`. <doc:Providers> lists each preset's failures, as seen or as its provider documents them.

### Retries

A failed connection, but not to xAI, and a failed response whose status the provider retries, are sent again before any
data arrives, as the model's ``OpenAICompatibleConfiguration/retries`` allow, and never after: a request whose answer
has started streaming isn't sent again. For a provider you describe, the statuses are 408, 409, 429 and any from 500 up,
and any status whose `x-should-retry` is `true`; `x-should-retry: false` throws without a retry. A wait the provider
asks for in `retry-after-ms` or `Retry-After` is taken, unless it's longer than ``RequestRetries/longestServerWait``,
which throws at once with the wait on the error. The presets retry and wait this way:

| Preset | Retries | Wait for the next data |
|---|---|---|
| Gemini, Mistral, Ollama | none | 10 minutes; 300 seconds on Mistral |
| Groq, DeepSeek, LM Studio, vLLM | up to twice | 60 seconds on Groq; 10 minutes on the others |
| xAI | up to twice, after a rate limit or an `x-should-retry` of `true`, but after no other failed response or failed connection, since xAI may bill a request that failed once its work began | 10 minutes |

The model's ``OpenAICompatibleLanguageModel/configuration`` replaces a preset's retries and wait.

### Read an answer's metadata

The entry that ends an answer carries facts about it: the model that answered, the provider's ids for the response and
the request, why the answer ended, the pages it cites, and the company that ran the model. The answer's usage carries
the input, cached, output and reasoning tokens. `openAICompatible` on a response entry reads its facts as
``OpenAICompatibleResponseMetadata``:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleErrors", slice: "metadata")

- ``OpenAICompatibleResponseMetadata/model`` is the model as the provider names it in its answer, which can differ from
  the id the request named, such as a dated version of it.
- ``OpenAICompatibleResponseMetadata/requestID`` comes from the header the provider sends it in: `x-request-id`, and
  for DeepSeek also `request-id` or `x-deepseek-request-id`. Groq sent one; Gemini and Ollama sent none, and vLLM sends
  one only from a server started with `--enable-request-id-headers`.
- ``OpenAICompatibleResponseMetadata/finishReason`` keeps a Chat Completions provider's word. In Responses, it's `stop`
  or `tool_calls` for a completed response, `length` for one cut off at `max_output_tokens`, and an incomplete
  response's other reason as it came, or `incomplete` when it gives none. An answer a content filter stopped, with
  `content_filter` in either format, throws `LanguageModelError.guardrailViolation`. A text answer cut off at its token
  limit doesn't throw, so `length` is the way to tell; a guided answer, or tool calls, cut off there throw instead. A
  word of a preset's own counts as the word it stands for, such as Mistral's `model_length` as `length`, and DeepSeek's
  `insufficient_system_resource` and `aborted` and vLLM's `abort` fail the answer.
- `providerMetadata.host` is the company that ran the model, such as `Google AI Studio` or `Groq`, for a remote
  preset. A server's preset, and a provider you describe, name none.
- The usage counts the tokens the provider reports. Gemini's reasoning tokens come from its `total_tokens`, as
  <doc:Reasoning> describes, and <doc:Caching> says where each provider's cached tokens come from.
  ``OpenAICompatibleUsageMetadata/cacheWriteTokenCount`` reads the tokens written to the cache where a provider reports
  them in `prompt_tokens_details.cache_write_tokens`, or in Responses `input_tokens_details.cache_write_tokens`; Gemini,
  Groq and Ollama reported none.

A request that ends in tool calls has the same facts. Foundation Models keeps no readable metadata on a tool-calls
entry, so they sit on its first call, and `openAICompatible` on the `Transcript.ToolCalls` entry reads them from there.

Saved transcripts keep these facts. The ones any provider can report, such as the model, the host and the request id,
also read through `providerMetadata`, as ``ProviderResponseMetadata`` and ``ProviderUsageMetadata``, so code that reads
them works with any language model in this package, as <doc:/LanguageModels/ReadingWhatAProviderReports> shows.

A `LanguageModelError` that a failure the provider reported becomes carries the provider's name, the HTTP status, the
code and the request id in its metadata, which its `openAICompatible` reads as ``OpenAICompatibleErrorMetadata``, and
its `providerMetadata` as ``ProviderErrorMetadata``, with the host. A timed-out connection carries none of these, and an
answer a content filter stopped or the model refused carries only the host. A provider's support asks for the request
id.

### Add up a response's usage

Each round of tool calls is a request of its own. A response's `usage` has only its last request's tokens, and a
session's own `usage` adds up the token counts of every request that answered. A request that fails reports no usage.
The package keeps no prices, so it reports what each request counted, not what it cost.

### Apple's guides

- [LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror)
- [Transcripts](https://developer.apple.com/documentation/foundationmodels/transcripts)
- [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output),
  on guardrail violations and refusals
