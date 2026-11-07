# Writing a provider module

Connect another service's models to Foundation Models.

## Overview

A provider module connects one service's models to Foundation Models. Its model conforms to
``DetailedLanguageModel``, and nests an `Executor` that conforms to Foundation Models' `LanguageModelExecutor`, as Apple's
[Running a Core AI model in a Foundation Models session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session)
shows for a model of your own. A provider module re-exports this module with `@_exported public import LanguageModels`,
so a file that imports the provider module can use the core's types too.

This package's own provider modules are added as
[CONTRIBUTING.md](https://github.com/ironsparrows/swift-language-models/blob/main/CONTRIBUTING.md) describes.

### Describe the models

The model's details type conforms to ``ModelDetails``. Its `id` has a type of the provider module's own that conforms
to ``ProviderVocabulary``, and so does every other word from the service's API, such as a parameter name. Each of
those types declares only `rawValue` and `init(rawValue:)`: string literals and `description` come from the protocol.

The details' ``ModelDetails/removalDate`` is the day the service stopped listing the model, as the module's catalog
records it, or `nil` for a model the catalog doesn't record as removed. The model's
``DetailedLanguageModel/fallbacks`` are the models the service tries when it fails, or none.

The details' ``ModelDetails/Effort`` lists the levels a model accepts: ``Efforts/Of`` with a type for each model
that conforms to ``Efforts/List``, which this package's generator writes with a static member for each level, an
enum of your own that conforms to ``ModelEffort``, or `ContextOptions.ReasoningLevel` for a model known only at
runtime. A module outside this package lists a model's levels with an enum of its own.
``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)`` takes an effort of that type, so a profile
takes only the levels the model accepts.

### Send requests

Foundation Models creates the model's `Executor` from the model's `executorConfiguration`, and calls its `respond` for
each answer. It calls ``DetailedLanguageModel/reportRemovedModels(for:)`` first, which logs an error and, in a debug
build, shows a runtime warning for each removed model the request may reach. Then it sends the request and streams the
answer into the channel. Last it calls ``DetailedLanguageModel/checkGuides(ofResponseText:for:)`` with the answer's
response text, or empty text when the answer ends in tool calls. For a request with a schema, that checks the text
against the schema's guides, since a host may drop or ignore a constraint, and throws `GeneratedContent.ParsingError`
when a value breaks one. Nothing makes a module call them, so a module that leaves one out goes without that check. Keep
secrets, such as the API key closure, on the model rather than in the configuration.

- Send a reasoning level as the nearest effort the model accepts, as <doc:ReasoningLevels> describes, and leave out
  every setting the model doesn't list.
- Report `.guidedGeneration` only for a model whose service holds the answer to the schema, such as with strict
  structured outputs. JSON mode alone often returns JSON that doesn't match the schema, which then throws instead of
  answering.
- Check the response text exactly as the response entry got it, without reasoning, so the check sees what Foundation
  Models decodes.
- Throw `LanguageModelError` wherever it has a case, so the same `catch` works for every model, and an error type of
  the module's own for the rest. Foundation Models 2.1.14, in Xcode 27.2, drops the `metadata` argument of
  `LanguageModelError.ContextSizeExceeded`'s initializer, so set `metadata` after creating it.
- Follow redirects only to the same host, so credentials never reach another server.

Give the model a configuration of the module's own, such as `VendorConfiguration`, for how the package sends its
requests, apart from the options that go in them. Build it from the core's pieces, and only those the module uses:
``RequestRetries`` when its requests retry, ``ImageEncoding`` when they send images, and an idle timeout, with
defaults that suit the service. Never declare a retry, timeout or image setting of the module's own. Give the model a
settable `configuration` that its `executorConfiguration` is made from, so an app changes a setting the same way for
every provider:

```swift
public struct VendorConfiguration: Sendable, Hashable {
    public var idleTimeout: Duration?
    public var retries: RequestRetries

    public init(idleTimeout: Duration? = .seconds(300), retries: RequestRetries = .standard) {
        self.idleTimeout = idleTimeout
        self.retries = retries
    }
}
```

The dialect makes its connection's retry policy from the configuration's ``RequestRetries`` and the statuses the service
retries, and returns the configuration's ``ImageEncoding`` from its `imageEncoding` hook, which a module without images
leaves at its default.

### Build on an API format

Many services take the same API format, such as OpenAI's Chat Completions and Responses, each with additions of its own.
This package keeps each format in a target of its own, such as `ChatCompletionsAPI` or `ResponsesAPI`, whose executor
does the work a request executor would otherwise repeat: it builds the request body from Foundation Models' request,
authenticates and sends it, retries a brief failure as the provider says and once with the portable schema when a
host rejects a constraint, streams the answer into Foundation Models' channel, maps a failed connection and logs. A
provider module describes how its service speaks the format in a dialect, a type that conforms to the format's dialect
protocol, such as `ChatCompletionsDialect` or `ResponsesDialect`. Its request executor's `execute` is one call,
`respond(to:model:streamingInto:as:)` with the dialect's type; the format creates the dialect from the model and that
request executor, so a request executor can only run a dialect made for its own model.

A dialect names the provider, the model, its base URL and how requests reach it, and turns failures into the provider's
own error; every other hook has a default, so a service that takes the format as OpenAI defines it writes only those. A
service with additions of its own implements just those hooks, each with typed values: its headers, its own members of
the body as an `Encodable` type, the members its models may not take, attachments only it takes, the reasoning it sends
back, and what its chunks carry, as a `Decodable` type it tracks across the answer. The Responses format has fewer: the
body, the members its models take, attachments, the reasoning that goes back, and a state read from the response's
headers, and adds two of its own: the role of the message the instructions go in, and the metadata key that keeps the
phase of each message of an answer. Each hook gets only what it needs, in a value only the format creates, and a
dialect that sets a type without the hook that uses it doesn't compile. The module keeps its dialect in one folder, and
its own types, such as its model, errors and options, never name a format type, so moving the module to another format
replaces only that folder and leaves its public API as it is.
Each format gets its own reasoning origin, since each sends reasoning back in another shape, so reasoning that one
format wrote is skipped rather than sent back in another.

The format targets are `package` code, so only this package's own provider modules build on them.

### Report what happened

Put facts about an answer in the metadata of the entry that ends it, and what it cost and counted in its usage's
metadata. For a fact that any provider module can report, such as the model, the finish reason or the cost, pass the
``ProviderResponseMetadata/channelMetadata`` of a ``ProviderResponseMetadata`` to the channel's `updateMetadata` action,
and the ``ProviderUsageMetadata/channelMetadata`` of a ``ProviderUsageMetadata`` to its `updateUsage` action, so
`providerMetadata` reads them for your model too, with a ``FinishReason`` for why the answer ended and ``Citation``
values for the pages it cites. A fact only one module reports takes a key with the module's prefix, such as `vendor.`,
so keys never collide.

Give apps typed readers for those facts, so they never read metadata as a dictionary, in the same four places for every
provider, each through a property named for the provider: `Transcript.Response` and `Transcript.ToolCalls` read a
`<Provider>ResponseMetadata`, `LanguageModelSession.Usage` a `<Provider>UsageMetadata`, and `LanguageModelError` a
`<Provider>ErrorMetadata`, as `openRouter` and `openAI` do. For the facts any provider module can report about a failure,
such as its HTTP status and code, pass the ``ProviderErrorMetadata/contextMetadata`` of a ``ProviderErrorMetadata`` as
the `metadata` of the `LanguageModelError` you throw, so `providerMetadata` reads them for your model too.

Never log API keys, prompts, answers, tool arguments or outputs, or attachments.

To test the module's behavior without a network, drive a session with a scripted model, as
<doc:TestingWithAScriptedModel> shows.

### Apple's guides

- [Running a Core AI model in a Foundation Models session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session)
- [LanguageModelExecutor](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutor)
- [LanguageModelExecutorGenerationChannel](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel)
