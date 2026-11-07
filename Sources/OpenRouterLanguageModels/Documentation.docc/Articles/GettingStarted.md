# Getting started

Create a model, say how its requests authenticate, and name the app to OpenRouter.

## Overview

``OpenRouterLanguageModel`` takes a model from the catalog and an ``OpenRouterAuthentication``, such as an API key
that a closure returns. A session uses it as it uses Apple's on-device model:

@Snippet(path: "swift-language-models/Snippets/QuickStart", slice: "session")

This module is all a file needs besides `FoundationModels`, and `Foundation` for types such as `URL`. It re-exports
`LanguageModels`, so typed efforts and ``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)``,
``FileAttachment`` and the model details come with it, as do ids and other words written as string literals, such as
`"anthropic/claude-haiku-5.5"`.

Sessions, streaming, tools, guided generation and profiles work as Apple's
[Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
and [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) describe.

### Keep the key out of the app

``OpenRouterAuthentication/apiKey(_:)`` reads an API key for every request and never stores it. A bundled key is
extractable from a shipping app, so use one only during development:

@Snippet(path: "swift-language-models/Snippets/QuickStart", slice: "apiKey")

The other examples call `keyStore.openRouterKey()`, which stands for the app's own Keychain wrapper. To ship without a
key, let each person sign in, or send requests through your own server, as <doc:Authentication> shows.

### Name the app

``OpenRouterApp`` names the app in each request's headers, which credits its usage in OpenRouter's rankings and app
marketplace. OpenRouter credits an app only when its ``OpenRouterApp/url`` is set; the name alone changes nothing:

@Snippet(path: "swift-language-models/Snippets/QuickStart", slice: "attribution")

### Send requests your own way

The model's URL session sends each request: `.shared` unless the model is created with a session of your own. A session
of your own brings its configuration, such as a proxy or protocol classes, but the package still sets these on each
request:

- The headers: those of the model's ``OpenRouterAuthentication``, the app's attribution in `HTTP-Referer` and the
  `X-OpenRouter-Title`, `X-OpenRouter-Categories` and `X-OpenRouter-App-Visibility` headers, `User-Agent`,
  `Content-Type`, `Accept`, and the headers of the response cache and router metadata. Each replaces a header of the
  same name in the configuration's `httpAdditionalHeaders`.
- The timeout: with ``OpenRouterConfiguration/idleTimeout`` set, each request for an answer waits that long for the
  next data, instead of the configuration's `timeoutIntervalForRequest`. It limits the wait for the next data, not the
  whole answer. The calls of <doc:ModelAndProviderInfo> keep the configuration's own timeout.
- Redirects only to the same scheme, URL host and port, through a delegate of each request's own. A background session
  doesn't support a request's own delegate, so there the session's own redirect policy applies.

The model's ``OpenRouterLanguageModel/configuration``, an ``OpenRouterConfiguration``, holds how the package sends
requests, apart from what they ask OpenRouter for: the idle timeout, the ``RequestRetries`` of a request that fails
before any data arrives, the ``ImageEncoding`` of image attachments, and how long the answers of
<doc:ModelAndProviderInfo> are kept. Set it when creating the model, or change it later; a change applies to the
next request:

```swift
var model = OpenRouterLanguageModel(
    .anthropicClaudeHaiku5_5,
    configuration: OpenRouterConfiguration(idleTimeout: .seconds(60), retries: RequestRetries(limit: 1)),
    auth: .apiKey { try await keyStore.openRouterKey() }
)
model.configuration.images.maximumSide = 1_024
```

The package logs what each request sends and leaves out, its retries, which model and host answered, and how it ended,
without keys, prompts or answers.
<doc:/LanguageModels/Logging> says
how to watch the messages and how to log less.

### Next steps

- <doc:Authentication>: shipping without a key.
- <doc:ChoosingAModel>: the catalog, models picked at runtime, and what a request costs.
- <doc:RoutingAndFallbacks>: the hosts that serve a model, and models to try when it fails.
- <doc:Caching>: paying less for prompts a host has seen.
- <doc:ErrorsAndMetadata>: the errors a request throws, and what OpenRouter reports about each answer.

### OpenRouter's guides

- [App Attribution](https://openrouter.ai/docs/app-attribution)
