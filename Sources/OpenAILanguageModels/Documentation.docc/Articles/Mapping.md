# Mapping

How Foundation Models requests become OpenAI Responses requests, and how OpenAI's answers come back.

## Overview

Each request is a `POST` to `responses` with `stream` set to `true`. A setting the catalog lists per model, such as
`temperature`, `top_p`, `max_output_tokens`, `tools`, `tool_choice`, `reasoning` or `parallel_tool_calls`, reaches the
model only when the model lists it in ``OpenAIModel/supportedParameters``; otherwise it's left out, so a model that
doesn't take it isn't sent it. A model that reasons takes `temperature` and `top_p` only while its effort is `none`,
so a request that sets another effort, or goes to a model that always reasons, leaves them out. A request that sets no
effort sends them to a model that can stop reasoning, since the catalog's default effort doesn't always match the
model's own: GPT-5.4 mini takes them, although its catalog default is `medium`. The tables say which settings go out
whatever the model lists, such as `service_tier` and `text.verbosity`.

A setting left out is logged, and a debug build shows a runtime warning for it. The Responses API has no `top_k` and
no `seed`, so `.random(top:seed:)` and the seeds of sampling modes never reach OpenAI, as <doc:RepeatableRuns>
explains.

Data attachments need iOS, macOS, visionOS or watchOS 27.2 at run time, and Xcode 27.2 at build time, since earlier
SDKs lack them. Built with an earlier Xcode, the package takes no data attachments.

### Requests

| Foundation Models | OpenAI |
|---|---|
| Instructions | A `developer` message for a model that reasons, and a `system` message for one that doesn't |
| Prompt | A `user` message with `input_text` parts |
| One answer | Its `reasoning` items, an `assistant` message for each of its messages, with its text and `phase`, and a `function_call` item for each tool call, in the order they came |
| An answer's reasoning | The `reasoning` items it came as, with their encrypted reasoning, sent back only to the model that wrote them, or to the model it's a dated snapshot of. An answer with neither text nor tool calls sends no reasoning back |
| Tool output | A `function_call_output` item, matched to its call by `call_id` |
| Attachment label | An `input_text` part just before the attachment |
| Image attachment | An `input_image` part with a JPEG data URL: upright, on white, scaled down to at most 2,048 pixels on its longer side, without the image's metadata, and `detail` `auto`; an image at an http or https address goes as that address |
| Image data attachment, in any kind ImageIO reads | An `input_image` part, as for an image attachment |
| PDF data attachment | An `input_file` part with `filename`, the label with `.pdf` added when it doesn't end in `.pdf`, or `document.pdf` without a label, and `file_data`, a data URL |
| Plain-text data attachment | An `input_text` part |
| A tool output with attachments | The `function_call_output` item's `output` as parts |
| An image attachment when the model doesn't take images | `LanguageModelError.unsupportedCapability` with `.vision`, before any request, as Foundation Models throws |
| A data attachment the model doesn't take, such as audio or video; an attachment in the instructions | `LanguageModelError.unsupportedTranscriptContent`, before any request |
| An answer's attachments, generated data entries | Left out |
| Response schema | `text.format`: `json_schema` with `strict` set to `true`; a request is refused before it's sent, with `LanguageModelError.unsupportedCapability` and `.guidedGeneration`, unless the model lists `structured_outputs`, as Foundation Models checks the model's capabilities |
| Guides on a schema | The full schema; when OpenAI rejects one of its constraints, with a 400 whose message names a constraint keyword and says it isn't supported, permitted or allowed, the request goes once more with the portable schema, whose constraints move into the description |
| `includeSchemaInPrompt` | The schema also goes in the prompt that asked for it |
| Tools | `tools` entries of type `function`, with `strict` set to `false`, so OpenAI keeps each tool's schema as it is |
| `temperature` | `temperature`, clamped to 0–2: for a model that reasons, only with the effort `none`, or with no effort set when the model can stop reasoning |
| `samplingMode` `.greedy` | `temperature` 0 |
| `samplingMode` `.random(top:seed:)` | Nothing; `top_k` and `seed` are left out and logged |
| `samplingMode` `.random(probabilityThreshold:seed:)` | `top_p`, clamped to 0–1; `seed` is left out and logged |
| `maximumResponseTokens` | `max_output_tokens`, at least 16, the fewest OpenAI takes; a lower limit is raised and logged |
| `toolCallingMode` | `tool_choice`: `auto` or `required`, sent only with the session's tools. A session with tools on a model that doesn't take them throws `LanguageModelError.unsupportedCapability` with `.toolCalling` before any request, as Foundation Models checks the model's capabilities |
| `reasoningLevel` | `reasoning.effort`, moved to the nearest effort the model accepts, and logged when it moves; `.off` goes as `none` where the model takes it. Every request of a model that reasons also sends `include` with `reasoning.encrypted_content` |
| Request metadata | `metadata`, string values within OpenAI's limits; the keys past them are left out and logged |

### OpenAI settings

| Swift | OpenAI |
|---|---|
| ``OpenAIOptions/storage`` | `store`: left out with ``OpenAIOptions/Storage/automatic``, so OpenAI keeps the response; `true` with ``OpenAIOptions/Storage/stored``; `false` with ``OpenAIOptions/Storage/notStored``, and later turns then send back only the reasoning items that carry their reasoning encrypted |
| ``OpenAIOptions/reasoningSummary`` | `reasoning.summary`, for a model that reasons |
| ``OpenAIOptions/verbosity`` | `text.verbosity`, as set, to every model; models older than GPT-5, such as o3 and GPT-4.1, take only `medium` and reject any other value with a 400 |
| ``OpenAIOptions/serviceTier`` | `service_tier` |
| ``OpenAIOptions/parallelToolCalls`` | `parallel_tool_calls`, `true` or `false`, with the session's tools when the model lists it; left out with ``OpenAIOptions/ParallelToolCalls/automatic`` |
| ``OpenAIOptions/cacheKey`` | `prompt_cache_key`: the id of the session's first prompt for ``OpenAIOptions/CacheKey/session``, or the app's own key for ``OpenAIOptions/CacheKey/named(_:)`` |
| ``OpenAIOptions/endUserID`` | `safety_identifier` |
| ``OpenAIAuthentication/apiKey(organization:project:_:)`` | `Authorization: Bearer` header, with `OpenAI-Organization` and `OpenAI-Project` when they're set, to `https://api.openai.com/v1/` |
| ``OpenAIAuthentication/apiKey(baseURL:organization:project:_:)`` | The same headers, to `responses` under its base URL |
| ``OpenAIAuthentication/proxied(baseURL:headers:)`` | Its headers, to `responses` under its base URL, instead of `https://api.openai.com/v1/` |
| The package and the app | `User-Agent` header: `swift-language-models ({bundleID}/{appVersion}; Swift/{swiftVersion}; {os}/{osVersion})`, such as `swift-language-models (com.example.Planner/2.3; Swift/6.4; iOS/27.0.1)`; outside an app bundle, without the app |
| ``OpenAIConfiguration/idleTimeout`` | The request's `timeoutInterval` |
| ``OpenAIConfiguration/retries`` | Nothing OpenAI sees: how many times, and after what wait, a failed request is sent again |
| ``OpenAIConfiguration/images`` | The longest side and JPEG quality of each `input_image` data URL |

### Answers

| OpenAI | Foundation Models |
|---|---|
| `response.output_text.delta` | Response text, as it is, even text in `<think>` tags |
| `response.reasoning_summary_text.delta`, `response.reasoning_text.delta` | Reasoning text, in the order it arrives, with a blank line between the parts of a summary |
| `reasoning` items, as `response.output_item.done` carries them | The reasoning entry's signature, with every member OpenAI sent, and with the places of the messages and calls that came between them, so they go back on later turns in their order |
| A `message` item's `phase` | The `phase` and the text's length of each message, which ``OpenAIResponseMetadata/messages`` reads |
| The messages of a guided answer | Only the first message with no phase or the `final_answer` phase is the answer that decodes. The others, such as `commentary`, stay out of the response text, and ``OpenAIResponseMetadata/Message/heldText`` keeps their text, with their phase, so they go back on later turns in their places |
| `function_call` items and `response.function_call_arguments.delta` | One tool-calls entry per answer, so parallel calls make one round; a call whose arguments arrive only in `response.output_item.done` gets them from there |
| `response.output_text.annotation.added` of type `url_citation` | ``Citation`` values on the response entry, which ``OpenAIResponseMetadata/citations`` reads, once each, with offsets that count from the start of the answer's text, or none when the cited message is held out of the text or text that isn't ASCII comes before it; they aren't sent back |
| `response.refusal.delta` | `LanguageModelError.refusal`, with the refusal's text |
| `usage` | Usage: `input_tokens`, `input_tokens_details.cached_tokens`, `output_tokens` and `output_tokens_details.reasoning_tokens`; in its metadata, the prompt tokens written to the cache when OpenAI reports them |
| The response's `id`, `model` and `service_tier`, and the `x-request-id` header | Metadata of the entry that ends the answer, which ``OpenAIResponseMetadata`` reads; `model` also goes on the reasoning entry |
| `response.completed` | Finish reason `stop`, or `tool_calls` when the answer ends in tool calls |
| `response.incomplete` with `incomplete_details.reason` `max_output_tokens` | Finish reason `length`: an answer cut short at its token limit, which ends without an error; a guided answer cut short throws `GeneratedContent.ParsingError`, and one cut short inside its tool calls throws ``OpenAIError`` with ``OpenAIError/Code/invalidResponse`` instead, so no tool runs with partial arguments |
| `response.incomplete` with `incomplete_details.reason` `content_filter` | `LanguageModelError.guardrailViolation` |
| Another `incomplete_details.reason` | The reason as the finish reason, or `incomplete` when there's none |
| An `error` event, `response.failed` | The error its `error` object stands for, as the next table says |

### Metadata

``OpenAIResponseMetadata``, ``OpenAIUsageMetadata`` and ``OpenAIErrorMetadata`` read what OpenAI reports about a
response entry, a usage and a failure as typed properties. Saved transcripts keep these facts. `providerMetadata` reads
the ones any provider can report, the same way for every provider module, as
<doc:/LanguageModels/ReadingWhatAProviderReports> shows.

| OpenAI | Reader |
|---|---|
| `model` | ``OpenAIResponseMetadata/model``, on the entry that ends the answer; its reasoning entry keeps the model too |
| `id` | ``OpenAIResponseMetadata/responseID`` |
| `x-request-id` header | ``OpenAIResponseMetadata/requestID`` |
| Why the answer ended | ``OpenAIResponseMetadata/finishReason`` |
| `service_tier` | ``OpenAIResponseMetadata/serviceTier`` |
| `url_citation` annotations | ``OpenAIResponseMetadata/citations``, on the response entry |
| `usage.input_tokens_details.cache_write_tokens` | ``OpenAIUsageMetadata/cacheWriteTokenCount`` |
| Each message's `phase`, and the text of a guided answer's messages that don't decode | ``OpenAIResponseMetadata/messages``, on the entry that ends the answer |
| A failure's HTTP status, the code an ``OpenAIError`` would have, and the request id | ``OpenAIErrorMetadata/status``, ``OpenAIErrorMetadata/code`` and ``OpenAIErrorMetadata/requestID``, on the `LanguageModelError` it becomes |

### Errors

| OpenAI | Thrown |
|---|---|
| `insufficient_quota`, `credit_balance_exhausted`, `organization_spend_limit_exceeded`, `project_spend_limit_exceeded`, `organization_usage_limit_exceeded` | ``OpenAIError`` with ``OpenAIError/isQuotaExhausted`` set, even as a 429 |
| `context_length_exceeded`, a 400 whose message mentions the context length or window | `LanguageModelError.contextSizeExceeded`, with the sizes the message names |
| 429, `rate_limit_exceeded` | `LanguageModelError.rateLimited`, with the reset date from `retry-after-ms` or `Retry-After`, or else the later of `x-ratelimit-reset-requests` and `x-ratelimit-reset-tokens` |
| `content_policy_violation`, `bio_policy`, `misalignment_policy_violation`, `image_content_policy_violation`, an `invalid_prompt` flagged for OpenAI's usage policies | `LanguageModelError.guardrailViolation` |
| `invalid_image`, `invalid_image_format`, `invalid_base64_image`, `invalid_image_url`, `image_too_large`, `image_too_small`, `image_parse_error`, `invalid_image_mode`, `image_file_too_large`, `unsupported_image_media_type`, `empty_image_file` | `LanguageModelError.unsupportedTranscriptContent`, naming the entries with images |
| 408, 504, `vector_store_timeout`, a timed-out connection | `LanguageModelError.timeout` |
| A connection that fails otherwise, such as without a network | Its `URLError`, unchanged |
| A stream that ends before it's complete, an event that can't be read, a tool call without a name, with arguments that aren't a whole JSON object, or that reached the token limit | ``OpenAIError`` with ``OpenAIError/Code/invalidResponse`` |
| Anything else | ``OpenAIError``, with its status, message, code, error type, parameter, request id and retry delay |

An error's ``OpenAIError/code`` is OpenAI's `code`, or else its error `type`, such as `invalid_request_error`, which
``OpenAIError/errorType`` keeps whatever the code. Without either, it's the kind the HTTP status stands for:
``OpenAIError/Code/authentication`` for a 401, ``OpenAIError/Code/permissionDenied`` for a 403,
``OpenAIError/Code/notFound`` for a 404, ``OpenAIError/Code/conflict`` for a 409, ``OpenAIError/Code/unprocessable`` for
a 422 and ``OpenAIError/Code/server`` for a 500 or above. An error in the stream arrives after HTTP 200, so it has no
status, and without a code it's ``OpenAIError/Code/server``.

A failed connection, a 408, 409 or 429, quota included, and any status from 500 up are retried before any data
arrives, and so is any status whose `x-should-retry` is `true`; `x-should-retry: false` throws without a retry. With the
standard ``RequestRetries``, a request is retried up to twice, and a retry waits the `retry-after-ms` or `Retry-After`
that OpenAI asks for when that's more than zero and at most 2 minutes, and otherwise half a second, doubled for each
retry before it up to 8 seconds, and cut by up to a quarter at random. A response that asks for more than 2 minutes
throws at once, with the wait on the error. ``OpenAIConfiguration/retries`` changes the limit, the first wait and the
longest wait OpenAI can ask for. A rate limit's reset date, and no other error's retry delay, falls back to the later
of `x-ratelimit-reset-requests` and `x-ratelimit-reset-tokens`. A 400 that rejects a constraint of the response schema
is sent once more with the portable schema.

### Apple's guides

- [GenerationOptions](https://developer.apple.com/documentation/foundationmodels/generationoptions) and
  [ContextOptions](https://developer.apple.com/documentation/foundationmodels/contextoptions)

### OpenAI's guides

- [Responses API reference](https://developers.openai.com/api/reference/resources/responses)
- [Streaming API responses](https://developers.openai.com/api/docs/guides/streaming-responses)
- [Conversation state](https://developers.openai.com/api/docs/guides/conversation-state), for `store` and reasoning
  items
