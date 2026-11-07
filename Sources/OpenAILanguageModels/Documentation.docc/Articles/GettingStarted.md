# Getting started

Create a model, say how its requests authenticate, and send them your own way.

## Overview

``OpenAILanguageModel`` takes a model from the catalog and an ``OpenAIAuthentication``, such as an API key that a
closure returns. A session uses it as it uses Apple's on-device model:

@Snippet(path: "swift-language-models/Snippets/OpenAIQuickStart", slice: "session")

This module is all a file needs besides `FoundationModels`, and `Foundation` for types such as `URL`. It re-exports
`LanguageModels`, so typed efforts and ``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)``,
``FileAttachment`` and the model details come with it, as do ids and other words written as string literals, such as
`"gpt-6-luna"`.

Sessions, streaming, tools, guided generation and profiles work as Apple's
[Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
and [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) describe.

### Keep the key out of the app

``OpenAIAuthentication/apiKey(organization:project:_:)`` reads an API key for every request and never stores it. A
bundled key is extractable from a shipping app, so use one only during development:

@Snippet(path: "swift-language-models/Snippets/OpenAIQuickStart", slice: "apiKey")

The other examples call `keyStore.openAIKey()`, which stands for the app's own Keychain wrapper. To ship without a
key, let each person bring their own, or send requests through your own server, as <doc:Authentication> shows.

### Send requests your own way

The model's URL session sends each request: `.shared` unless the model is created with a session of your own. A session
of your own brings its configuration, such as a proxy or protocol classes, but the package still sets these on each
request:

- The headers: those of the model's ``OpenAIAuthentication``, such as `Authorization`, `OpenAI-Organization` and
  `OpenAI-Project`, and `User-Agent`, `Content-Type` and `Accept`. Each replaces a header of the same name in the
  configuration's `httpAdditionalHeaders`.
- The timeout: with ``OpenAIConfiguration/idleTimeout`` set, each request waits that long for the next data, instead of
  the configuration's `timeoutIntervalForRequest`. It limits the wait for the next data, not the whole answer. It's 10
  minutes unless the model is created with another, since a model that reasons hard may send nothing for a while, and
  `nil` keeps the session's own timeout.
- Redirects only to the same scheme, URL host and port, through a delegate of each request's own. A background session
  doesn't support a request's own delegate, so there the session's own redirect policy applies.

The model's ``OpenAILanguageModel/configuration``, an ``OpenAIConfiguration``, holds how the package sends requests,
apart from what they ask OpenAI for: the idle timeout, the ``RequestRetries`` of a request that fails before any data
arrives, and the ``ImageEncoding`` of image attachments. Set it when creating the model, or change it later; a change
applies to the next request:

```swift
var model = OpenAILanguageModel(
    .gpt6Luna,
    configuration: OpenAIConfiguration(idleTimeout: .seconds(60), retries: RequestRetries(limit: 1)),
    auth: .apiKey { try await keyStore.openAIKey() }
)
model.configuration.images.maximumSide = 1_024
```

The package logs what each request sends and leaves out, its retries, which model answered, and how it ended, without
keys, prompts or answers. <doc:/LanguageModels/Logging> says how to watch the messages and how to log less.

### Next steps

- <doc:Authentication>: shipping without a key, and the organization and project a request counts toward.
- <doc:ChoosingAModel>: the catalog, models picked at runtime, and dated snapshots.
- <doc:Reasoning>: what a reasoning level becomes, and how reasoning goes back on later turns.
- <doc:Caching>: helping OpenAI's prompt cache serve the start of a prompt.
- <doc:ErrorsAndMetadata>: the errors a request throws, and what OpenAI reports about each answer.

### OpenAI's guides

- [Developer quickstart](https://developers.openai.com/api/docs/quickstart)
- [Production best practices](https://developers.openai.com/api/docs/guides/production-best-practices), on keeping API
  keys safe
