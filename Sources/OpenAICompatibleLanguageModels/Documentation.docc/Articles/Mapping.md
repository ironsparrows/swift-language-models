# Mapping

How Foundation Models requests become requests in OpenAI's formats, and how a provider's answers come back.

## Overview

A request goes to `chat/completions` or `responses` under the provider's URL, as its
``OpenAICompatibleProvider/format`` says, and its answer streams back as server-sent events. The tables below show what
the module sends to a provider you describe; a preset changes some of it for its provider, such as members it leaves
out, the token limit's member and how reasoning goes back, and <doc:Providers> lists each one.

A member the provider doesn't take, which a preset lists, is left out and logged, with a runtime warning in a debug
build, and so is a `top_k` or a seed the format has no member for. ``OpenAICompatibleOptions/additionalMembers`` replace
the module's members of the same keys, and go out even where a preset leaves that member out.

Data attachments need iOS, macOS, visionOS or watchOS 27.2 at run time, and Xcode 27.2 at build time, since earlier
SDKs lack them.

### Requests

| Foundation Models | Chat Completions | Responses |
|---|---|---|
| Instructions | `system` message | `developer` message |
| Prompt | `user` message | `user` message |
| Reasoning, response and tool calls of one answer | One `assistant` message, with `tool_calls`, and the reasoning member or thought signature its provider reads back, as <doc:Reasoning> describes | Its `reasoning` items, `message` and `function_call` items, in order |
| Tool output | `tool` message, matched by call id | `function_call_output`, matched by call id |
| Attachments | Parts, as <doc:Attachments> lists | Parts, as <doc:Attachments> lists |
| Tools | `tools`, each a `function` with its name, description and argument schema | The same, as `function` tools |
| `toolCallingMode` | `tool_choice`: `auto` or `required`, only with the session's tools; when disallowed, no tools at all | The same |
| Response schema | `response_format` `json_schema` with `strict`; once more with the portable schema when the provider rejects a constraint | `text.format`, the same way |
| `includeSchemaInPrompt` | The schema also goes in the prompt that asked for it | The same |
| `temperature` | `temperature`, clamped to 0–2 | The same |
| `samplingMode` `.greedy` | `temperature` 0 | The same |
| `samplingMode` `.random(top:seed:)` | `top_k` where the preset sends it, otherwise left out and logged; `seed` | `top_k` the same way; the seed left out and logged |
| `samplingMode` `.random(probabilityThreshold:seed:)` | `top_p`, and `seed` | `top_p`; the seed left out and logged |
| `maximumResponseTokens` | `max_tokens`, or `max_completion_tokens` for Groq and vLLM | `max_output_tokens`, at least 16: a smaller limit is raised to 16 and logged |
| `reasoningLevel` | `reasoning_effort`, the nearest effort the model accepts, and DeepSeek's `thinking` | `reasoning.effort`, the same way |
| Request metadata | `metadata`: up to 16 string values, with keys of up to 64 characters and values of up to 512; the rest is left out and logged | The same |
| The usage | `stream_options.include_usage`, except to Groq and Mistral, which send usage unasked | Sent unasked |

### The module's settings

| Swift | Sent |
|---|---|
| ``OpenAICompatibleOptions/additionalMembers`` | Each member as written, in place of the module's member of the same key, the others after the module's, sorted by key; never the model id, `messages` or `input`, `stream` or `tools` |
| ``OpenAICompatibleOptions/cacheKey`` | `prompt_cache_key`, where the provider takes it, as <doc:Caching> describes |
| ``OpenAICompatibleOptions/storage`` | `store` in Responses: left out, `true` or `false`; for xAI, `false` when left automatic |
| ``OpenAICompatibleProvider/keyHeader`` with ``OpenAICompatibleAuthentication/apiKey(_:)`` | `Authorization: Bearer` and the key, or the key in the named header; none for an empty key |
| ``OpenAICompatibleProvider/headers`` | Each header, on every request; an authentication header of the same name, whatever its case, replaces one |
| ``OpenAICompatibleAuthentication/proxied(baseURL:headers:)`` | Its headers, to the same paths under its base URL |
| ``OpenAICompatibleAuthentication/proxied(headers:)`` | Its headers, to the provider's URL |
| The package and the app | `User-Agent` header: `swift-language-models ({bundleID}/{appVersion}; Swift/{swiftVersion}; {os}/{osVersion})`; outside an app bundle, without the app |
| ``OpenAICompatibleConfiguration/idleTimeout`` | The `timeoutInterval` of each request |
| ``OpenAICompatibleConfiguration/retries`` | Nothing the provider sees: how many times, and after what wait, a failed request is sent again |
| ``OpenAICompatibleConfiguration/images`` | The longest side and JPEG quality of each image sent as data |

### Answers

| Chat Completions | Responses | Foundation Models |
|---|---|---|
| `delta.content` | `response.output_text.delta` | Response text; in Chat Completions, a list of parts gives the text of each `text` part, with the text parts inside a `thinking` part as reasoning |
| `delta.reasoning_content`, `delta.reasoning`, and a `<think>` or `<thinking>` block that opens the text | The reasoning items' summary and text | Reasoning text, in the order it arrives |
| `extra_content.google.thought_signature` on a delta or its first tool call | The reasoning items, with their encrypted reasoning when asked for | The reasoning entry's signature, sent back on later turns where <doc:Reasoning> says |
| `delta.tool_calls` | `function_call` items | One tool-calls entry per answer, so parallel calls make one round |
| `delta.annotations` of type `url_citation` | `url_citation` annotations | ``Citation`` values on the response entry |
| `usage` | `usage` | Usage: input, cached, output and reasoning tokens, as <doc:ErrorsAndMetadata> describes |
| `model`, `id`, `finish_reason` | `model`, `id`, and as the finish reason `stop` or `tool_calls` for a completed response, or an incomplete one's `incomplete_details.reason`, or `incomplete` without one | Metadata of the entry that ends the answer, which ``OpenAICompatibleResponseMetadata`` reads |
| `finish_reason: length` | `response.incomplete` with the reason `max_output_tokens`, read as `length` | An answer cut short at its token limit, which ends without an error; a guided answer cut short throws `GeneratedContent.ParsingError`, and one cut short inside its tool calls throws ``OpenAICompatibleError`` with `invalid_response` |
| `finish_reason: content_filter` | `response.incomplete` with the reason `content_filter` | `LanguageModelError.guardrailViolation` |
| A finish reason of a preset's own, such as Mistral's `model_length` | | The word it stands for, as <doc:Providers> lists |
| An event named `ping` | The same | Passed over |

### Metadata

``OpenAICompatibleResponseMetadata``, ``OpenAICompatibleUsageMetadata`` and ``OpenAICompatibleErrorMetadata`` read what
a provider reports about a response entry, a usage and a failure as typed properties. Saved transcripts keep these
facts.

| Provider | Reader |
|---|---|
| `model` | ``OpenAICompatibleResponseMetadata/model``; the reasoning entry keeps the model too |
| `id` | ``OpenAICompatibleResponseMetadata/responseID`` |
| The request id header, such as `x-request-id` | ``OpenAICompatibleResponseMetadata/requestID`` |
| `finish_reason`, as the provider sent it | ``OpenAICompatibleResponseMetadata/finishReason`` |
| `url_citation` annotations | ``OpenAICompatibleResponseMetadata/citations`` |
| `prompt_tokens_details.cache_write_tokens`, or in Responses `input_tokens_details.cache_write_tokens` | ``OpenAICompatibleUsageMetadata/cacheWriteTokenCount`` |
| The company that ran the model, from the preset | `providerMetadata.host`; none for a server's preset or a provider you describe |
| A failure's provider, HTTP status, code and request id | ``OpenAICompatibleErrorMetadata/providerName``, ``OpenAICompatibleErrorMetadata/status``, ``OpenAICompatibleErrorMetadata/code`` and ``OpenAICompatibleErrorMetadata/requestID``, on the `LanguageModelError` it becomes |

### Errors

<doc:ErrorsAndMetadata> lists what each failure becomes and how a request is retried. An error in the stream is a
chunk's `error` object, a chunk whose `type` is `error`, an event named `error`, or in Responses an `error` event, an
event with no `type` that carries an `error`, an event of a type the format doesn't read that carries a non-empty
`error`, or a failed response. When an error object other than a failed response's has no message, or its data isn't
JSON, its text is the message, up to 1,000 characters, beside the object's other members.

### Apple's guides

- [GenerationOptions](https://developer.apple.com/documentation/foundationmodels/generationoptions) and
  [ContextOptions](https://developer.apple.com/documentation/foundationmodels/contextoptions)
