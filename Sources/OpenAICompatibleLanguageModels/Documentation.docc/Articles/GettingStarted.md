# Getting started

Pick a provider's preset or describe a provider, name a model on it, say how its requests authenticate, and send them
your own way.

## Overview

``OpenAICompatibleLanguageModel`` takes an ``OpenAICompatibleModel``, which names the model and the
``OpenAICompatibleProvider`` it runs on, and an ``OpenAICompatibleAuthentication``, such as an API key that a closure
returns. A session uses it as it uses Apple's on-device model:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleQuickStart", slice: "session")

This module is all a file needs besides `FoundationModels`, and `Foundation` for types such as `URL`. It re-exports
`LanguageModels`, so reasoning levels and ``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)``,
``FileAttachment`` and the model details come with it, as do ids written as string literals, such as `"my-model"`.

Sessions, streaming, tools, guided generation and profiles work as Apple's
[Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
and [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) describe.
<doc:ToolsAndGuidedGeneration>, <doc:Reasoning>, <doc:Attachments> and <doc:Caching> say what the module does with
each across providers, and <doc:Mapping> how each request and answer translates.

### Use a preset

Gemini, Groq, DeepSeek, Mistral and xAI have presets, which carry their URLs and what each does differently, such as
the members it refuses and the efforts its models accept:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleQuickStart", slice: "preset")

So do the servers Ollama, LM Studio and vLLM, at their default local addresses, which take no key unless the server
asks for one: `OpenAICompatibleModel("qwen3:8b", on: .ollama, reasoning: .onByDefault)` with
``OpenAICompatibleAuthentication/unauthenticated``.
<doc:Providers> says what each preset does, and which were checked against their provider.
``OpenAICompatibleProvider/at(_:)`` points a preset at another address, such as a gateway in front of the provider,
and keeps everything else. An app on a device reaches a server on a Mac at the Mac's address on the network, and App
Transport Security needs to allow an IP address, as <doc:Attachments#Reach-a-server-on-your-own-network> describes.

### Describe another provider

An ``OpenAICompatibleProvider`` says where requests go and how:

- ``OpenAICompatibleProvider/name``: the provider's name, which the log's category and the errors name. The reasoning
  of its answers carries it too, so reasoning goes back on later turns only to the provider that wrote it. Keep it the
  same from one version of the app to the next.
- ``OpenAICompatibleProvider/url``: the base URL of its API, with the version its docs give, such as
  `https://llm.example.com/v1`. Requests go to `chat/completions` or `responses` under it, as written.
- ``OpenAICompatibleProvider/format``: ``OpenAICompatibleProvider/Format/chatCompletions``, which nearly every provider
  takes and is the default, or ``OpenAICompatibleProvider/Format/responses``.
- ``OpenAICompatibleProvider/keyHeader``: `Authorization: Bearer` by default, or a header of another name, such as
  `.named("api-key")`.
- ``OpenAICompatibleProvider/headers``: headers every request carries, such as a gateway's routing header. A key never
  goes here.

``OpenAICompatibleProvider/at(_:)`` gives the same provider at another address, such as a server on another port, with
everything else kept.

To a provider described this way, a Chat Completions request asks for a usage chunk with `stream_options`, and sends the
token limit as `max_tokens` and a reasoning level as `reasoning_effort`. A Responses request sends the token limit as
`max_output_tokens` and a reasoning level in `reasoning`. ``OpenAICompatibleOptions/additionalMembers`` can replace one
of these members' values, but not leave the member out, so a server that refuses one needs a preset.

### Describe the model

An ``OpenAICompatibleModel`` takes the model's id, as its provider's API spells it, and what you know about it. Each
value left out takes the provider's default, which a preset sets for its provider. On a provider you describe, a model
takes tools, guided generation and images, reasons only when a request asks it to, and accepts the efforts `xhigh`,
`high`, `medium`, `low`, `minimal` and `none`. Say what differs:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleQuickStart", slice: "localServer")

A request that sets a reasoning level sends the nearest effort the model accepts, and logs the move when it isn't the
level's own. For a model whose reasoning is ``ModelReasoning/unsupported``, Foundation Models refuses a request that
sets one before it's sent. The provider decides what the model does at run time: a setting it rejects throws
``OpenAICompatibleError`` with the provider's message, and with the member the provider names, when it names one, in
``OpenAICompatibleError/parameter``.

### Keep the key out of the app

``OpenAICompatibleAuthentication/apiKey(_:)`` reads an API key for every request, sends it in the provider's key
header, and never stores it. A bundled key is extractable from a shipping app, so use one only during development:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleQuickStart", slice: "apiKey")

To ship without a key, let each person bring their own, or send requests through your own server with
``OpenAICompatibleAuthentication/proxied(baseURL:headers:)``, which adds the key and forwards them. A gateway you
describe as the provider itself takes its headers with ``OpenAICompatibleAuthentication/proxied(headers:)``, and a
server that takes no key, such as one on the same Mac, ``OpenAICompatibleAuthentication/unauthenticated``.

The proxy in <doc:/LanguageModels/KeepingAPIKeysOutOfTheApp>, in Swift, Node.js or Python, takes these settings for a
provider:

| Setting | Value |
|---|---|
| `upstream` | The provider's ``OpenAICompatibleProvider/url``, such as `https://api.groq.com/openai/v1/` for Groq |
| `keyVariable` | The variable that holds the provider's key, such as `GROQ_API_KEY` |
| `authHeader`, `authValue` | `Authorization`, `Bearer {key}`, or the header ``OpenAICompatibleProvider/keyHeader`` names, with `{key}` |
| `paths` | `chat/completions`, or `responses` for a provider on Responses, such as xAI |
| `passHeaders` | The headers below |
| `fixedHeaders` | The provider's ``OpenAICompatibleProvider/headers``, if it has any |

The headers it passes back to the app, which the module reads: the provider's request id header, such as
`x-request-id`, and `retry-after-ms`, `Retry-After` and `x-should-retry`. The module sends `chat/completions` or
`responses` as a `POST`, whose answer streams as server-sent events. It makes no other calls.

### Send settings only the provider has

``OpenAICompatibleOptions/additionalMembers`` go in every request's body as written, such as a setting the module
doesn't write:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleQuickStart", slice: "additionalMembers")

A member replaces the one of the same key the module writes, such as `max_tokens`. The model id, the transcript,
`stream` and `tools` stay the module's: a member with one of those keys is left out, and the request logs it.

### Send requests your own way

The model's URL session sends each request: `.shared` unless the model is created with a session of your own. A session
of your own brings its configuration, such as a proxy or protocol classes, but the package still sets these on each
request:

- The headers: those of the provider and its ``OpenAICompatibleAuthentication``, such as `Authorization`, and
  `User-Agent`, `Content-Type` and `Accept`, which also replace a provider's header of the same name. Each replaces a
  header of the same name in the configuration's `httpAdditionalHeaders`.
- The timeout: with ``OpenAICompatibleConfiguration/idleTimeout`` set, each request waits that long for the next data,
  instead of the configuration's `timeoutIntervalForRequest`. It limits the wait for the next data, not the whole
  answer, and `nil` keeps the session's own timeout.
- Redirects only to the same scheme, URL host and port, through a delegate of each request's own. A background session
  doesn't support a request's own delegate, so there the session's own redirect policy applies.

The model's ``OpenAICompatibleLanguageModel/configuration``, an ``OpenAICompatibleConfiguration``, holds how the package
sends requests, apart from what they ask the provider for: the idle timeout, the ``RequestRetries`` of a request that
fails before any data arrives, and the ``ImageEncoding`` of image attachments. A model created without one takes the
provider's defaults, which for a provider described by its name and URL wait up to 10 minutes for the next data, since a
server loading a model or a model that reasons hard may send nothing for a while, and retry up to twice; a preset's are
in <doc:Providers>. Change one setting on the model, and it keeps the others; a change applies to the next request:

```swift
var model = OpenAICompatibleLanguageModel(details, auth: .apiKey { try await keyStore.gatewayKey() })
model.configuration.idleTimeout = .seconds(60)
model.configuration.images.maximumSide = 1_024
```

The package logs what each request sends and leaves out, its retries, which model answered, and how it ended, without
keys, prompts or answers, in a category named for the provider. <doc:/LanguageModels/Logging> says how to watch the
messages and how to log less.

### When a request fails

Rate limits, an oversized context, content filters, timeouts and images the provider can't use throw
`LanguageModelError`, as with any other model, and for a failure the provider reported,
``FoundationModels/LanguageModelError/openAICompatible`` reads the provider's name, code and request id from it. The
rest throw ``OpenAICompatibleError``, which names the provider that failed and keeps its message, code, error type and
request id, and says whether the account's quota ran out. A connection that fails throws its `URLError`; for a server on
the same Mac, that usually means it isn't running, or listens on another port than the provider's URL names.
<doc:ErrorsAndMetadata> lists what each failure becomes, and how to read what a provider reports about each answer.
