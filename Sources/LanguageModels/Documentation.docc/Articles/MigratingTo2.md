# Migrating to 2.0

Update your code from 1.x of this package to 2.0.

## Overview

2.0 reads what a provider reports through typed values, and a provider module of your own writes Foundation Models'
executor itself. Requests, answers, retries, errors and logs stay as they were, and a transcript you saved with 1.x keeps
working: its metadata is stored under the same keys.

### Reading what a provider reports

`LanguageModelMetadataKey`, `OpenRouterMetadataKey` and `OpenAIMetadataKey` are gone. Read a fact through
`providerMetadata` in code that works with any model, as <doc:ReadingWhatAProviderReports> describes, and through
`openRouter` or `openAI` for what only that provider reports:

```diff
-answer.metadata[LanguageModelMetadataKey.model]
-response.usage.metadata[LanguageModelMetadataKey.cost]
-answer.metadata[OpenRouterMetadataKey.responseCacheStatus]
+answer.providerMetadata.model
+response.usage.providerMetadata.cost
+answer.openRouter.responseCacheStatus
```

Each value comes typed: a cost is a `Decimal`, a finish reason a ``FinishReason`` and a citation a ``Citation``, so the
code that decoded them goes too. `answer` here is a `Transcript.Response`;
``FoundationModels/Transcript/ToolCalls/providerMetadata`` reads the same facts for a request that ended in tool calls,
and `openRouter` and `openAI` read them there too.

| `LanguageModelMetadataKey` | Read it as |
|---|---|
| `model` | `answer.providerMetadata.model` |
| `provider` | `answer.providerMetadata.host`, or `error.providerMetadata.host` |
| `responseID` | `answer.providerMetadata.responseID` |
| `requestID` | `answer.providerMetadata.requestID`, or `error.providerMetadata.requestID` |
| `finishReason` | `answer.providerMetadata.finishReason` |
| `serviceTier` | `answer.providerMetadata.serviceTier` |
| `citations` | `answer.providerMetadata.citations` |
| `cost` | `usage.providerMetadata.cost` |
| `cacheWriteTokenCount` | `usage.providerMetadata.cacheWriteTokenCount` |
| `webSearchCount` | `usage.providerMetadata.webSearchCount` |
| `status` | `error.providerMetadata.status` |
| `errorCode` | `error.providerMetadata.code` |

| `OpenRouterMetadataKey` | Read it as |
|---|---|
| `responseCacheStatus` | `answer.openRouter.responseCacheStatus` |
| `responseCacheAge` | `answer.openRouter.responseCacheAge`, a `Duration` |
| `responseCacheSourceID` | `answer.openRouter.responseCacheSourceID` |
| `routingStrategy` | `answer.openRouter.routingStrategy` |
| `routingAttempt` | `answer.openRouter.routingAttempt` |
| `routingAttempts` | `answer.openRouter.routingAttempts` |
| `routingEndpoints` | `answer.openRouter.routingEndpoints` |
| `routingPipeline` | `answer.openRouter.routingPipeline` |
| `region` | `answer.openRouter.region` |
| `generationTime` | `answer.openRouter.generationTime`, a `Duration` |
| `isBYOK` | `usage.openRouter.isBYOK` |
| `upstreamInferenceCost` | `usage.openRouter.upstreamInferenceCost` |
| `upstreamInferencePromptCost` | `usage.openRouter.upstreamInferencePromptCost` |
| `upstreamInferenceCompletionCost` | `usage.openRouter.upstreamInferenceCompletionCost` |
| `serverToolCost` | `usage.openRouter.serverToolCost` |
| `requestedServerToolCallCount` | `usage.openRouter.requestedServerToolCallCount` |
| `executedServerToolCallCount` | `usage.openRouter.executedServerToolCallCount` |
| `limitSource` | `error.openRouter.limitSource` |

| `OpenAIMetadataKey` | Read it as |
|---|---|
| `phases` | `answer.openAI.messages` |

### Errors

An error's metadata says `host` for the company that ran the model, and `code` for what the errors themselves call a
code. `OpenRouterError` says `provider`, as OpenRouter's other types do:

```diff
-error.providerMetadata.provider
-error.providerMetadata.errorCode
-error.openRouter.errorCode
-error.openAI.errorCode
+error.providerMetadata.host
+error.providerMetadata.code
+error.openRouter.code
+error.openAI.code
```

```diff
-OpenRouterError(message: message, providerName: host)
-error.providerName
+OpenRouterError(message: message, provider: host)
+error.provider
```

### The idle timeout

The deprecated initializers that took `idleTimeout:` are gone, and so is the model's `idleTimeout` property. Pass a
configuration, and read the timeout there. The same goes for OpenAI's model, with `OpenAIConfiguration`:

```diff
-OpenRouterLanguageModel(details, idleTimeout: .seconds(60), auth: auth)
-model.idleTimeout
+OpenRouterLanguageModel(details, configuration: OpenRouterConfiguration(idleTimeout: .seconds(60)), auth: auth)
+model.configuration.idleTimeout
```

### Generic request settings

`ConfigurableLanguageModel`, `RetryingConfiguration` and `ImageEncodingConfiguration` are gone. Both models keep their
`configuration` property, so write generic code for the provider's model instead:

```diff
-func withoutRetries<Model: ConfigurableLanguageModel>(_ model: Model) -> Model
-where Model.Configuration: RetryingConfiguration {
+func withoutRetries<Effort>(_ model: OpenRouterLanguageModel<Effort>) -> OpenRouterLanguageModel<Effort> {
     var model = model
     model.configuration.retries = .disabled
     return model
 }
```

If you need these protocols, open an
[issue](https://github.com/ironsparrows/swift-language-models/issues) with what you use them for.

### A provider module of your own

`DetailedLanguageModelExecutor`, `DetailedLanguageModelRequestExecutor`, `DetailedLanguageModelAnswer` and
`DetailedLanguageModelBase` are gone, and ``DetailedLanguageModel`` no longer fixes the model's executor. Your model nests
an `Executor` that conforms to Foundation Models' `LanguageModelExecutor`, and makes the two checks the wrapper made:
``DetailedLanguageModel/reportRemovedModels(for:)`` first, and ``DetailedLanguageModel/checkGuides(ofResponseText:for:)``
last.

```diff
-struct RequestExecutor: DetailedLanguageModelRequestExecutor {
-    func execute(
-        _ request: LanguageModelExecutorGenerationRequest,
+struct Executor: LanguageModelExecutor {
+    func respond(
+        to request: LanguageModelExecutorGenerationRequest,
         model: VendorLanguageModel,
         streamingInto channel: LanguageModelExecutorGenerationChannel
-    ) async throws -> DetailedLanguageModelAnswer {
+    ) async throws {
+        model.reportRemovedModels(for: request)
         let responseText = try await send(request, model: model, into: channel)
-        return DetailedLanguageModelAnswer(responseText: responseText)
+        try model.checkGuides(ofResponseText: responseText, for: request)
     }
 }
```

The `RequestExecutor` type alias on the model goes, and its `executorConfiguration` returns `Executor.Configuration`.
Nothing makes a module call the two checks. A session shows that the guide check runs, and the report only logs, so test
that call as <doc:WritingAProvider> describes, which shows the whole executor.

Write what you used to write under the keys through typed values, which need no key:

```diff
-[LanguageModelMetadataKey.model: model, LanguageModelMetadataKey.finishReason: reason]
+ProviderResponseMetadata(model: model, finishReason: FinishReason(rawValue: reason)).channelMetadata
```

``ProviderUsageMetadata`` has ``ProviderUsageMetadata/channelMetadata`` for a usage, and ``ProviderErrorMetadata`` has
``ProviderErrorMetadata/contextMetadata`` for the `metadata` of a `LanguageModelError`. Foundation Models 2.1.14, in
Xcode 27.2, drops the `metadata` argument of `LanguageModelError.ContextSizeExceeded`'s initializer, so set it afterwards:

```swift
var exceeded = LanguageModelError.ContextSizeExceeded(contextSize: limit, tokenCount: count, debugDescription: message)
exceeded.metadata = ProviderErrorMetadata(status: status, code: code).contextMetadata
throw LanguageModelError.contextSizeExceeded(exceeded)
```

### Naming a provider's executor

Each model's nested `RequestExecutor` is now `Executor`, a `LanguageModelExecutor`, and its `execute(_:model:streamingInto:)`
is `respond(to:model:streamingInto:)`. The contents of `executorConfiguration` don't change:

```diff
-OpenRouterLanguageModel<Effort>.RequestExecutor.Configuration
+OpenRouterLanguageModel<Effort>.Executor.Configuration
```

### A removed OpenRouter model

The 14 models that OpenRouter stopped listing are gone from `OpenRouterModel`, with the `OpenRouterCatalog` enums of
their efforts, and the effort levels of the three that listed any. Their members were deprecated with "Removed from
OpenRouter on" and a date:

- `minimax/minimax-01`
- `minimax/minimax-m2`
- `minimax/minimax-m2-her`
- `minimax/minimax-m2.1`
- `nousresearch/hermes-3-llama-3.1-405b`
- `nousresearch/hermes-3-llama-3.1-70b`
- `nvidia/nemotron-3.5-content-safety:free`
- `poolside/laguna-s-2.1`
- `poolside/laguna-s-2.1:free`
- `poolside/laguna-xs-2.1`
- `poolside/laguna-xs-2.1:free`
- `thinkingmachines/inkling-small:free`
- `thinkingmachines/inkling:free`
- `upstage/solar-pro-3`

Name another model. If one of these still answers for you, describe it by hand with
`OpenRouterModel<ContextOptions.ReasoningLevel>(id:displayName:supportedParameters:)`. Its ``ModelDetails/removalDate`` is
`nil`, so a request to it logs no report.

### Catalog members still deprecated

A member whose provider has announced a retirement date stays, deprecated: 2.0 removes only models OpenRouter had already
stopped listing. <doc:ModelCatalogs> describes when a member goes.

### The contract's module

`import LanguageModels` and every provider module's import work as before. The contract is now declared in a module
named `LanguageModelsCore`, which `LanguageModels` re-exports, so code that prints or stores a type's reflected name sees
`LanguageModelsCore.ImageEncoding` for `ImageEncoding`.

A library that needs only the contract can depend on the `LanguageModelsCore` product alone.
