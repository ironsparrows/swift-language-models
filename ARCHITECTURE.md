# Architecture

A map of the code for contributors: which module depends on which, how one request travels from an app to a provider
and back, and what a provider says about how it differs from a format. [CONTRIBUTING](CONTRIBUTING.md) has the rules:
where shared code goes, how a file is laid out and how it's tested.

Each word below means one thing, here, in code comments and in the docs:

| Word | Means | In code |
|---|---|---|
| **provider** | Whose API an app's requests go to. One module of this package is for one provider. | `OpenRouterLanguageModels`; `model.providerName`, the log's category |
| **host** | The company whose servers ran the model for one answer. With OpenAI that's OpenAI. With OpenRouter it's whoever OpenRouter routed to. A URL's host is always written "URL host". | `AnswerAdditions.host`; the log's `host …` |
| **format** | A wire format more than one provider accepts: Chat Completions, Responses. | the namespaces `ChatCompletions`, `Responses` |
| **shared model** | A `LanguageModel` that speaks one format with any provider. | `ChatCompletions.Model`, `Responses.Model` |
| **provider's model** | The public `LanguageModel` an app creates. | `OpenRouterLanguageModel`, `OpenAILanguageModel` |
| **model details** | A catalog entry: an id and what that model can do. | `OpenRouterModel`, `OpenAIModel` |
| **exchange** | One request and its answer. A provider's part in it is a value that lives as long as the exchange. | `ChatCompletions.Exchange`, `OpenRouterExchange` |
| **member** | One key and its value in a JSON body. | `ChatCompletions.Member`, `request.members` |
| **facts** | What an answer reports beyond its content: model, host, cost, usage. | `AnswerAdditions`, `providerMetadata` |

OpenRouter's public types say "provider" for the host, as OpenRouter's API does: `OpenRouterProviderName`,
`OpenRouterResponseMetadata.provider`. The stored metadata key is `provider` too, and never changes.

## Modules

```mermaid
block-beta
    columns 2
    app["Your app"]:2
    openrouter["OpenRouterLanguageModels · product"] openai["OpenAILanguageModels · product"]
    models["LanguageModels · product, all package but one line"]:2
    core["LanguageModelsCore · product, re-exported"]:2
    apple["FoundationModels · Apple"]:2
    space:2

    style app fill:#ffffff,stroke:#8a8f98,color:#1d1d1f
    style openrouter fill:#e8f0fe,stroke:#3b6fd8,color:#1d1d1f
    style openai fill:#e8f0fe,stroke:#3b6fd8,color:#1d1d1f
    style core fill:#e8f0fe,stroke:#3b6fd8,color:#1d1d1f
    style models fill:#f1ecfb,stroke:#7c5cc4,color:#1d1d1f
    style apple fill:#f2f2f2,stroke:#6e6e73,color:#1d1d1f
```

Each layer builds on the ones below it. Blue: what apps can use. Purple: a product whose own declarations apps never
see. Gray: Apple.

| Target | Holds | Access |
|---|---|---|
| `LanguageModelsCore` | The public contract every provider shares: `DetailedLanguageModel`, model details, efforts, configuration values, vocabulary, attachments, typed facts, guide violations, the logging switch. And the few internals those need: ordered JSON, the package logger, removed-model reports. | `public`, plus `package` for what the other targets call. |
| `LanguageModels` | The two shared models, and what they share: sending requests, reading Foundation Models' request, writing its channel, failures before a provider maps them. One line re-exports the core. The contract's DocC catalog lives here. | `package` for what a provider writes, the rest internal. The re-export is its one `public` line, and CI checks that. |
| `OpenRouterLanguageModels`, `OpenAILanguageModels` | What only that provider has: its public types, its exchange, its catalog and info calls. | `public`, the rest internal. |

- An app imports only the provider modules it uses. Each one re-exports `LanguageModels`, so efforts,
  `DetailedLanguageModel` and logging come with it.
- A library that needs only the contract depends on `LanguageModelsCore` alone, and compiles no HTTP code.
- OpenRouter speaks OpenAI's Chat Completions format, and OpenAI its Responses format. A provider depends on
  `LanguageModels` and nothing else of this package.
- `LanguageModelsCore` never imports `LanguageModels`. Inside `LanguageModels`, files import the core with `import` or
  `package import`, and only `Exports.swift` says `public`.
- The generator and its plugin are build tools: they write each module's `Generated/` sources and never ship.

## The two models

`ChatCompletions.Model` and `Responses.Model` are `LanguageModel`s that work alone: pointed at a server that takes the
format as it is, a shared model answers with no provider code at all, through its `PlainExchange`. That's what the tests
of a format run on.

A shared model owns the whole exchange. Its `respond` reports removed models, calls its private `run`, and checks the
answer against the schema's guides. `run` is one method, in six numbered steps: read the request, let the exchange
prepare it, build the body, send it, stream the answer, end it.

A provider's model is a different type. An app creates it, and its nested `Executor` is the `LanguageModelExecutor`
Foundation Models calls. `respond` there is one line: it derives a shared model and hands the request on.

```swift
try await model.chatCompletions(configuration).respond(to: request, streamingInto: channel)
```

## One request

A Chat Completions request, from OpenRouter's model:

```mermaid
sequenceDiagram
    autonumber
    participant S as LanguageModelSession (Apple)
    participant EX as OpenRouterLanguageModel.Executor
    participant M as ChatCompletions.Model
    participant X as OpenRouterExchange
    participant CN as Connection
    participant ST as ChatCompletions.Stream
    participant CH as AnswerChannel
    participant OR as OpenRouter

    S->>EX: respond(to:model:streamingInto:)
    EX->>EX: model.chatCompletions(configuration)
    EX->>M: respond(to:streamingInto:)
    M->>M: report removed models
    M->>X: 1 read the request: checkAttachment, replays, replayMembers
    M->>X: 2 prepare(&request)
    M->>M: 3 request.body(): members in order, the unsupported ones left out
    M->>CN: 4 openEventStream (one more attempt with the portable schema)
    CN->>OR: POST chat/completions, with retries, redirects only to the same URL host
    OR-->>CN: server-sent events
    loop each event
        M->>ST: 5 receive(event)
        ST->>X: read(extras)
        ST->>CH: text, reasoning, tool calls, data
        CH-->>S: channel events
    end
    M->>ST: 6 finish
    ST->>X: additions(header:)
    ST->>CH: finish: metadata and usage on the entry that ends the answer
    M->>M: check the answer against the schema's guides
    M-->>EX: returns
```

Where each step lives:

| Step | File |
|---|---|
| OpenRouter's entry | `Sources/OpenRouterLanguageModels/OpenRouterLanguageModel.swift`, `Executor.respond` |
| OpenRouter as a Chat Completions provider, and all it does in a request | `Sources/OpenRouterLanguageModels/OpenRouterExchange.swift` |
| The checks and the exchange | `Sources/LanguageModels/Models/ChatCompletions/ChatCompletionsModel.swift` |
| 1 and 3: the request and its body | `ChatCompletionsRequest.swift`, with the transcript in `ChatCompletionsTranscript.swift` |
| 4: sending | `Sources/LanguageModels/Shared/Connection.swift`, `HTTPClient.swift` |
| 5 and 6: the stream | `ChatCompletionsStream.swift` |
| Channel events, facts, usage | `Sources/LanguageModels/Shared/AnswerChannel.swift` |
| Failures | `RequestFailure` in `Shared/RequestFailure.swift`; the mapping in `OpenRouterError.swift` |

## A Responses request

OpenAI's model takes the same path, with the other shared model in the middle:

```mermaid
sequenceDiagram
    autonumber
    participant EX as OpenAILanguageModel.Executor
    participant M as Responses.Model
    participant X as OpenAIExchange
    participant CN as Connection
    participant ST as Responses.Stream
    participant CH as AnswerChannel
    participant OA as OpenAI

    EX->>M: respond(to:streamingInto:), on model.responses(configuration)
    M->>X: 1 read the input: checkAttachment, replays
    M->>X: 2 prepare(&request): storage, encrypted reasoning, reasoning, text members
    M->>M: 3 request.body(): leave out unsupported and unsent members
    M->>CN: 4 openEventStream POST responses (retries as the official SDKs retry, then one with the portable schema)
    CN->>OA: request
    OA-->>CN: server-sent events
    loop each event
        M->>ST: 5 receive(event)
        ST->>CH: text, reasoning summaries, function calls by output index, citations
    end
    Note over ST: response.completed or response.incomplete ends the answer, error or response.failed throws
    M->>ST: 6 finish
    ST->>X: additions(header:)
    ST->>CH: finish: reasoning items in their order as the signature, message phases, metadata, usage
```

| Step | File |
|---|---|
| OpenAI's entry | `Sources/OpenAILanguageModels/OpenAILanguageModel.swift`, `Executor.respond` |
| OpenAI as a Responses provider | `Sources/OpenAILanguageModels/OpenAIExchange.swift` |
| The checks and the exchange | `Sources/LanguageModels/Models/Responses/ResponsesModel.swift` |
| 1 and 3: the request and its body | `ResponsesRequest.swift`, over `ResponsesInput.swift` and `ResponsesReplay.swift` |
| 5 and 6: the stream | `ResponsesStream.swift` |

## What a provider states

A provider says how it differs from the plain format in three places. A provider that takes the format as it is states
none of them, apart from the required values on the model and what a failure becomes.

**On the model,** once, in `chatCompletions(_:)` or `responses(_:)`, what's true for every request:

| Value | Format | OpenRouter | OpenAI |
|---|---|---|---|
| `name`, `url`, `connection`, `providerName`, `capabilities`, `reaching:` | both, required | the variant's model id, a proxy's URL, session, auth and timeouts, `OpenRouter` | the model's id, a proxy's URL, session, auth and timeouts, `OpenAI` |
| `memberOrder` | Chat Completions | the member order hosts cache on | |
| `unsupportedMembers` | both | the listed members the model's details don't list | the same |
| `media` | Chat Completions | AIFF, M4A, AAC, FLAC and OGG audio, and video | |
| `images` | both, required | the configuration's `ImageEncoding` | the same |
| `reasoningOrigin` | both, required | `openrouter` | `openai-responses` |
| `instructionsRole` | Responses | | `developer` for a model that reasons, `system` otherwise |
| `phasesKey` | Responses, required | | `openAI.phases` |

**On the exchange,** the methods of `ChatCompletions.Exchange` or `Responses.Exchange`, in the order a request calls them.
The model holds one exchange value, and each request works on a copy, so what one answer reported never reaches the
next. Every method but `error(for:)` has a default that adds nothing:

| Method | Format | OpenRouter | OpenAI |
|---|---|---|---|
| `checkAttachment(_:in:)` | both | which inputs the models take | which inputs the model takes |
| `replays(_:)` | both | only to the model that wrote it, not a fallback | only to the model that wrote it, or to the model it's a dated snapshot of |
| `replayMembers(for:)` | Chat Completions | `reasoning` and `reasoning_details` | |
| `prepare(_:)` | both | the app's name, address and categories, the response cache, router metadata; fallbacks, routing, plugins, reasoning, penalties, server tools, cache marks | the effort, summary and storage, `text.verbosity`, `parallel_tool_calls` with the session's tools, the service tier, cache key and end user, the sampling a reasoning model doesn't take |
| `read(_:)` | Chat Completions | images and reasoning details | |
| `additions(header:)` | both | the host, cost, router report, cache status | the request's id |
| `error(for:)` | both, required | `LanguageModelError` or `OpenRouterError` | `LanguageModelError` or `OpenAIError` |

**On the request,** in `prepare(_:)`, what depends on the one request. Chat Completions has `headers`, `members`,
`sendsSessionTools`, `serverTools`, `tokenLimitMember`, `usesPortableSchema`, `instructionsMark` and `movedEffort`.
Responses has `members`, `sendsSessionTools`, `serverTools`, `reasoning`, `movedEffort`, `storage`,
`asksForEncryptedReasoning`, `textMembers` and `leftOutMembers`. An exchange can't change the messages or the settings
the app asked for.

Implement a method that has a default in the type that declares the conformance: only there does a misspelled one draw a
warning, which CI's `-warnings-as-errors` turns into an error, instead of silently keeping the default.

## Typed facts

Facts are typed in code and flat keys in storage. Foundation Models keeps an answer's facts as flat metadata, and saved
transcripts keep those keys, so their spellings never change. One file per module knows its keys, and they're private
there:

| Module | File | Reader |
|---|---|---|
| `LanguageModelsCore` | `ProviderMetadata.swift` | `providerMetadata`, on `Transcript.Response`, `Transcript.ToolCalls`, `LanguageModelSession.Usage` and `LanguageModelError` |
| `OpenRouterLanguageModels` | `OpenRouterMetadata.swift` | `openRouter`, in the same four places |
| `OpenAILanguageModels` | `OpenAIMetadata.swift` | `openAI`, in the same four places |

A shared model writes what the format knows, such as the model and the finish reason, and an exchange's
`additions(header:)` adds the rest, as an `AnswerAdditions`. `channelMetadata` on `ProviderResponseMetadata` and
`ProviderUsageMetadata`, and `contextMetadata` on `ProviderErrorMetadata`, write a value under its keys.

## Errors

```mermaid
flowchart LR
    rejected["Failed response, after the retries"] --> failure
    event["Error event in the stream"] --> failure
    failed["Answer the host says failed"] --> failure
    unreadable["Event that can't be read"] --> failure
    unusable["Answer cut off, or a tool call that can't run"] --> failure
    failure["RequestFailure"]:::package --> map["exchange.error(for:)"]:::provider
    map --> foundation["LanguageModelError"]:::apple
    map --> own["OpenRouterError · OpenAIError"]:::provider

    classDef package fill:#f1ecfb,stroke:#7c5cc4,color:#1d1d1f
    classDef provider fill:#e8f0fe,stroke:#3b6fd8,color:#1d1d1f
    classDef apple fill:#f2f2f2,stroke:#6e6e73,color:#1d1d1f
```

- A provider is handed one value, a `RequestFailure`, and reads its `kind`, `status`, `body`, `rawBody`, `retryAfter`,
  `message` and `imageEntries`, and any response header through `header(_:)`, whether the response was rejected or failed
  while it streamed. `status` is an `HTTPStatus`, named when a provider or the transport decides something for it, and
  each provider's table switches over it with no `default`.
- Failures Foundation Models has a case for become `LanguageModelError`: a rate limit, an oversized context, a
  guardrail, a refusal, a timeout or an image the host can't use. The rest become the provider's own error, such as a
  rejected key, or credits or a quota that ran out. A `URLError` is rethrown as a failed connection's.
- `run` logs what it throws, through `RequestLog`, whose category is the provider's name. What the log says of an error
  is its kind, HTTP status, code and host, never its message, and a provider's error tells it through `LoggableError`.

## Info calls

```mermaid
flowchart LR
    calls["endpoints() · currentDetails() · currentPricing()"]:::provider --> connection["Connection.cachedValue"]:::shared
    connection --> http["HTTPClient"]:::shared
    http --> api(["OpenRouter"])

    classDef provider fill:#e8f0fe,stroke:#3b6fd8,color:#1d1d1f
    classDef shared fill:#f1ecfb,stroke:#7c5cc4,color:#1d1d1f
```

`OpenRouterLanguageModel` and `OpenRouterModel` read a model's endpoints, current details and pricing through a
`Connection`, like chat requests, with an answer reused for the configuration's `infoCacheLifetime`, a minute by default.
The provider decodes the body and maps a failure, which reaches it as a `RequestFailure` of kind `.rejected`. OpenAI's
model has no info calls.

## The model catalog

```mermaid
flowchart LR
    schedule(["Daily workflow"]) --> fetch["fetch"]:::tool
    fetch --> json["Catalogs/openrouter.json · Catalogs/openai.json"]
    json --> render["render"]:::tool
    render --> generated["Generated/*.swift"]:::provider
    generated --> release(["Pull request → release"])

    classDef tool fill:#f1ecfb,stroke:#7c5cc4,color:#1d1d1f
    classDef provider fill:#e8f0fe,stroke:#3b6fd8,color:#1d1d1f
```

`ModelCatalogGenerator fetch` downloads each source's documents into `Catalogs/`, and `render` turns them into typed
models, efforts, vocabularies and removed models. OpenRouter's come from its model list and API description. OpenAI's
come from three: the ids its API description names for the Responses API, the models its `/v1/models` still serves,
which needs an API key, and what models.dev says each model takes; a model past its shutdown day is left out.
`model-catalog.yml` runs both daily and opens a pull request whose release label `release.yml` reads.
