# Errors and metadata

Handle failures, and read what OpenAI reports about each answer.

## Overview

Rate limits, oversized contexts, content filters, refusals, timeouts and images OpenAI can't use throw Foundation
Models' own `LanguageModelError`, so the same `catch` works for every model. Anything else, such as a rejected API key
or a quota that ran out, throws ``OpenAIError``, with its ``OpenAIError/status``, ``OpenAIError/code``,
``OpenAIError/errorType``, ``OpenAIError/parameter``, ``OpenAIError/requestID`` and ``OpenAIError/retryAfter``:

@Snippet(path: "swift-language-models/Snippets/OpenAIErrors", slice: "errors")

``OpenAIError/isQuotaExhausted`` is `true` whatever OpenAI's code for the limit, such as `insufficient_quota`,
`credit_balance_exhausted` or a project's spending limit. OpenAI sends it as a 429, but waiting doesn't clear it, so it
throws ``OpenAIError`` rather than `LanguageModelError.rateLimited`.

A `LanguageModelError` that a failure becomes carries the HTTP status, the failure's code and OpenAI's id for the
request in its metadata, which its `openAI` reads as ``OpenAIErrorMetadata``, with the code as an ``OpenAIError/Code``,
and its `providerMetadata` reads as ``ProviderErrorMetadata``, the same way for every provider. The code is the one an
``OpenAIError`` would have: OpenAI's code or error type, or else the package's code for the HTTP status, such as
``OpenAIError/Code/unmapped`` for a 408 or 429 without one, and ``OpenAIError/Code/server`` for a status from 500 up or
a failure in the stream that names none. OpenAI's support asks for the request id.

A failed connection, a 408, 409 or 429, and any status from 500 up are retried up to twice, as the official SDKs retry
them, before any data arrives, and so is any status whose `x-should-retry` is `true`. A failure whose `x-should-retry`
is `false` isn't retried, and one that asks for a wait longer than 2 minutes throws at once, with the wait on its error.
<doc:Mapping#Errors> lists what each failure becomes.

### Read an answer's metadata

The entry that ends an answer carries facts about the answer: the model that answered, OpenAI's ids for the response
and the request, why the answer ended, and the service tier that served it. The answer's usage carries the input,
cached, output and reasoning tokens, and the prompt tokens written to the cache when OpenAI reports them. `openAI` on a
response entry reads its facts as ``OpenAIResponseMetadata``, and on a usage as ``OpenAIUsageMetadata``:

@Snippet(path: "swift-language-models/Snippets/OpenAIErrors", slice: "metadata")

A text answer cut off at its token limit doesn't throw; its finish reason is `length`. A guided answer cut off there
throws `GeneratedContent.ParsingError`, and one cut off inside its tool calls throws ``OpenAIError`` with
``OpenAIError/Code/invalidResponse``, so no tool runs with partial arguments.

A request that ends in tool calls has the same facts. Foundation Models keeps no readable metadata on a tool-calls
entry, so they sit on its first call, and `openAI` on the `Transcript.ToolCalls` entry reads them from there, as
``OpenAIResponseMetadata``. A request that asks for several calls at once has one set of facts.

Saved transcripts keep these facts. The ones any provider can report, such as the model and the request id, also read
through `providerMetadata`, as ``ProviderResponseMetadata`` and ``ProviderUsageMetadata``, so code that reads them
works with any language model in this package, as <doc:/LanguageModels/ReadingWhatAProviderReports> shows. The only fact
OpenAI reports that other providers don't is the `phase` of each of an answer's messages, which ``OpenAIResponseMetadata/messages`` reads and <doc:Reasoning> describes.

### Add up a response's usage

Each round of tool calls is a request of its own. A response's `usage` has only its last request's tokens, and a
session's own `usage` adds up the token counts of every request that answered. A request that fails, such as one the
model refuses, reports no usage. The entry that ends each request carries only the prompt tokens written to the cache,
when OpenAI reports them, so to count a whole response, read the session's `usage` before and after it. The package
keeps no prices, so it reports what each request counted, not what it cost.

### Apple's guides

- [LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror)
- [Transcripts](https://developer.apple.com/documentation/foundationmodels/transcripts)
- [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output),
  on guardrail violations and refusals

### OpenAI's guides

- [Error codes](https://developers.openai.com/api/docs/guides/error-codes)
- [Rate limits](https://developers.openai.com/api/docs/guides/rate-limits)
- [Debugging requests](https://developers.openai.com/api/reference/overview#debugging-requests), on the `x-request-id`
  header
