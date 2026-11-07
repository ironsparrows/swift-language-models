# Writing a provider module

Connect another provider's models to Foundation Models.

## Overview

A provider module connects one provider's models to Foundation Models. An app uses every provider module the same way,
so each offers the same things:

- A model, which answers in a `LanguageModelSession`.
- Model details, which say what each model can do.
- Authentication, which keeps the app's secrets out of what Foundation Models holds.
- A configuration, for how requests are sent.
- An error, for the failures Foundation Models has no case for.
- Typed facts, which say what happened on each answer.

This article builds them for a made-up provider, Vendor, whose API streams one JSON object a line. All of it is public
API. Depend on the `LanguageModelsCore` product, which holds the whole contract and compiles no HTTP code, and re-export
it with `@_exported public import LanguageModelsCore`, so a file that imports your module can use the contract too.

The code that sends requests for this package's own provider modules isn't public, so a module in another package writes
its own sending, retries and streaming, as Vendor's does. A provider that joins this package is added as
[CONTRIBUTING.md](https://github.com/ironsparrows/swift-language-models/blob/main/CONTRIBUTING.md) describes.

### Describe the models

The model's details type conforms to ``ModelDetails``. Its `id` has a type of the module's own that conforms to
``ProviderVocabulary``, and so does every other word from the provider's API, such as a parameter name. Each of those
types declares only `rawValue` and `init(rawValue:)`: string literals and `description` come from the protocol.

@Snippet(path: "swift-language-models/Snippets/ProviderModule", slice: "details")

``ModelDetails/reasoning`` says whether and when the model reasons, as a ``ModelReasoning``. The details'
``ModelDetails/removalDate`` is the day the provider stopped listing the model, as the module's catalog records it, or
`nil` for a model the catalog doesn't record as removed.

The details' ``ModelDetails/Effort`` lists the levels a model accepts: ``Efforts/Of`` with a type for each model
that conforms to ``Efforts/List``, which this package's generator writes with a static member for each level, an
enum of your own that conforms to ``ModelEffort``, or `ContextOptions.ReasoningLevel` for a model known only at
runtime. A module outside this package lists a model's levels with an enum of its own, and one enum serves only models
that accept the same levels. ``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)`` takes an effort
of that type, so a profile takes only the levels the model accepts.

### Make it a language model

The model conforms to ``DetailedLanguageModel``, which reads its capabilities, and the kinds of data it takes and
generates, from its details and its ``DetailedLanguageModel/fallbacks``: the models the provider tries when it fails, or
none.

@Snippet(path: "swift-language-models/Snippets/ProviderModule", slice: "model")

It nests an `Executor` that conforms to Foundation Models' `LanguageModelExecutor`, as Apple's
[Running a Core AI model in a Foundation Models session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session)
shows for a model of your own. A session creates the executor from the model's `executorConfiguration`, and calls its
`respond` for each answer, passing the model. Keep the executor's `Configuration` small: it has to be hashable, and it
says only where requests go and how they're sent. Keep secrets, such as the API key closure, on the model, which
`respond` receives.

### Answer a request

`respond` does four things, in this order. It calls ``DetailedLanguageModel/reportRemovedModels(for:)``, which logs an
error and, in a debug build, shows a runtime warning for each removed model the request may reach. It sends the request.
It streams the answer's text, reasoning and tool calls into the channel. Last it calls
``DetailedLanguageModel/checkGuides(ofResponseText:for:)`` with the answer's response text, or empty text when the
answer ends in tool calls. For a request with a schema, that checks the text against the schema's guides, since a host
may drop or ignore a constraint, and throws `GeneratedContent.ParsingError` when a value breaks one.

@Snippet(path: "swift-language-models/Snippets/ProviderModule", slice: "executor")

`Event` decodes one line of Vendor's stream, and `Answer` holds the ids of the answer's entries, so each event adds to the
entry it belongs to. `Body` reads what a request carries: the transcript, the session's tools and the schema.

@Snippet(path: "swift-language-models/Snippets/ProviderModule", slice: "body")

Nothing makes a module call the two checks, so a module that leaves one out goes without it. To stay short, Vendor's
executor sends no reasoning level, sends only the text of a transcript, and leaves redirects to the URL session. A real
module does these too:

- Send a reasoning level as the nearest effort the model accepts, as <doc:ReasoningLevels> describes, and leave out
  every setting the model doesn't list.
- Report `.guidedGeneration` only for a model whose provider holds the answer to the schema, such as with strict
  structured outputs. JSON mode alone often returns JSON that doesn't match the schema, which then throws instead of
  answering.
- Send every kind of transcript entry and attachment the provider takes.
- Check the response text exactly as the response entry got it, without reasoning, so the check sees what Foundation
  Models decodes.
- Follow redirects only to the same URL host, so credentials never reach another server.

### Report what happened

Put what the provider reported on the entry that ends the answer, and on its usage. For the facts any provider can
report, pass the ``ProviderResponseMetadata/channelMetadata`` of a ``ProviderResponseMetadata`` to the channel's
`updateMetadata` action, with a ``FinishReason`` for why the answer ended and ``Citation`` values for the pages it cites,
and the ``ProviderUsageMetadata/channelMetadata`` of a ``ProviderUsageMetadata`` to its `updateUsage` action. Then
`providerMetadata` reads them for your model too, as <doc:ReadingWhatAProviderReports> describes. Foundation Models keeps
no readable metadata on a tool-calls entry, so an answer that ends in tool calls puts its facts on the first call.
Citations point into the response's text, so they stay on the response entry:

@Snippet(path: "swift-language-models/Snippets/ProviderModule", slice: "report")

A fact only your module reports takes a key with the module's prefix, such as `vendor.`, so keys never collide. Give apps
typed readers for those facts, so they never read metadata as a dictionary, in the same four places for every provider,
each through a property named for the provider: `Transcript.Response` and `Transcript.ToolCalls` read a
`<Provider>ResponseMetadata`, `LanguageModelSession.Usage` a `<Provider>UsageMetadata`, and `LanguageModelError` a
`<Provider>ErrorMetadata`, as `openRouter` and `openAI` do.

Throw `LanguageModelError` wherever it has a case, so the same `catch` works for every model, and an error type of the
module's own for the rest. Pass the ``ProviderErrorMetadata/contextMetadata`` of a ``ProviderErrorMetadata`` as the
`metadata` of the `LanguageModelError` you throw, so `providerMetadata` reads a failure's facts for your model too.
Foundation Models 2.1.14, in Xcode 27.2, drops the `metadata` argument of `LanguageModelError.ContextSizeExceeded`'s
initializer, so set `metadata` after creating it:

@Snippet(path: "swift-language-models/Snippets/ProviderModule", slice: "failure")

### Offer what the other providers offer

Give the model a settable `configuration` that its `executorConfiguration` is made from, so an app changes a setting the
same way for every provider. Build it from the core's pieces, and only those the module uses: ``RequestRetries`` when its
requests retry, and ``ImageEncoding`` when they send images. Never declare a retry or image setting of the module's own.
Add an `idleTimeout` of type `Duration?`, as every provider's configuration has, with a default that suits the provider.

@Snippet(path: "swift-language-models/Snippets/ProviderModule", slice: "configuration")

- Take an authentication value as `auth:`, as every provider's model does, with credentials as a closure the module calls
  for each request, so an app can fetch them or reach the provider through its own server, as
  <doc:KeepingAPIKeysOutOfTheApp> describes.
- From OS 27.2, a ``FileAttachment`` reaches the executor in the transcript as a `Transcript.DataAttachment`, with its
  bytes and type. List the kinds a model takes in ``ModelDetails/dataAttachmentTypes``.
- Log only at the levels ``LanguageModelsLogging/minimumLevel`` lets through, so one setting quiets every module in an
  app. It runs from `.debug` through `.info`, `.default` and `.error` to `.fault`, which isn't the order of `OSLogType`'s
  raw values. Never log API keys, prompts, answers, tool arguments or outputs, or attachments.

### Test it

To test the module without a network, drive a session with its own model, and give the model a URL session whose
`URLProtocol` answers with what the provider sends. The session runs your executor as an app's does, so the test reads
its transcript, usage and errors. A session shows the guide check too: an answer that breaks a guide throws. Code that
only uses a model, such as an app's features, takes a scripted model instead, as <doc:TestingWithAScriptedModel> shows.

A session can't show the removed-model report, which only logs. A test sees that call only through details of its own
whose computed ``ModelDetails/removalDate`` records each read, so the model has to be generic over its details. Without
that, check the call by reading `respond`.

### Apple's guides

- [Running a Core AI model in a Foundation Models session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session)
- [LanguageModelExecutor](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutor)
- [LanguageModelExecutorGenerationChannel](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel)
