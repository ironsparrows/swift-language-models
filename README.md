<div align="center">

<img src="assets/icon.png" alt="Swift Language Models" width="128" height="128">

# Swift Language Models

**One Foundation Models API for every provider's language models.**

Apple's `LanguageModelSession`, with Claude, GPT, Gemini and more in the same session as the on-device model.

[![CI](https://github.com/ironsparrows/swift-language-models/actions/workflows/ci.yml/badge.svg)](https://github.com/ironsparrows/swift-language-models/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ironsparrows/swift-language-models)](https://github.com/ironsparrows/swift-language-models/releases/latest)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20visionOS%20%7C%20watchOS%2027%2B-blue)](#installation)
[![License](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE)

[Quick start](#quick-start) ·
[Installation](#installation) ·
[Usage](#usage) ·
[OpenRouter](#openrouter) ·
[OpenAI](#openai) ·
[Testing](#testing-and-evaluation) ·
[Docs](#documentation)

</div>

> [!TIP]
> **Two provider modules.** OpenRouter's one API key reaches hundreds of models from Anthropic, OpenAI, Google,
> DeepSeek, Qwen, Meta and Mistral. OpenAI's module reaches GPT models, and o3 until it retires, directly through
> OpenAI's Responses API.

Apps keep Apple's `LanguageModelSession`, with its transcripts, tools, `@Generable` guided generation, Dynamic Profiles
and reasoning levels. Provider modules plug other providers' models into it. Claude, GPT, Gemini, DeepSeek, Qwen, Llama
and Mistral then run in the same session as Apple's on-device model, and switching changes only `model:`.

- **Apple's API, any model.** Sessions, streaming, tools, `@Generable` and Dynamic Profiles work unchanged.
- **Typed model catalogs.** Every OpenRouter and OpenAI model is a static member, with its context size, levels and
  capabilities.
- **Typed reasoning levels.** Each model takes only the levels it accepts, checked when the code compiles.
- **Routing, fallbacks and caching.** Hosts picked by price or data policy, backup models, and cached prompts.
- **Server tools.** Web search, web fetch, advisors and subagents run on OpenRouter while the model answers.
- **Attachments.** Images, and from OS 27.2 PDFs and text, plus audio and video through OpenRouter; generated images
  come back as data.
- **Errors to switch on.** Rate limits, oversized contexts, guardrails and refusals throw Apple's `LanguageModelError`.
- **Testing and evaluation.** Apple's Evaluations framework with any model, and a scripted model for offline tests.

## Quick start

```swift
import FoundationModels
import OpenRouterLanguageModels

// `keyStore` stands for your app's own Keychain wrapper.
let model = OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey { try await keyStore.openRouterKey() })
let session = LanguageModelSession(model: model)  // The same session as with SystemLanguageModel.default
let response = try await session.respond(to: "Plan a three-day trip to Kyoto.")
print(response.content)
```

Never ship an API key inside an app. [Authentication](#authentication) shows how to keep it out.

## Installation

- iOS, macOS, visionOS or watchOS 27.0.
- Xcode 27.0, with Swift 6.4.
- OS 27.2 and Xcode 27.2 for PDF, audio, video and text attachments, and for generated images.

Foundation Models' `LanguageModel` isn't available on tvOS or Linux, so neither is this package.

> [!NOTE]
> **Future server support.** At WWDC26, Apple announced plans to open-source the core Foundation Models framework so
> the same Swift APIs can run on servers. The stated target was “later this summer,” with no specific date
> ([Platforms State of the Union, 12:44](https://developer.apple.com/videos/play/wwdc2026/102/?time=764);
> [What’s new in the Foundation Models framework, 19:55](https://developer.apple.com/videos/play/wwdc2026/241/?time=1195)).
> Until then, this package needs Apple OS 27 or later, and doesn't run on Linux or other servers.

In Xcode, choose **File ▸ Add Package Dependencies…** and enter
`https://github.com/ironsparrows/swift-language-models`. In a `Package.swift`, add the package, and the provider
module's product to each target that uses it:

```swift
dependencies: [
  .package(url: "https://github.com/ironsparrows/swift-language-models", from: "2.0.0")
]
```

```swift
.product(name: "OpenRouterLanguageModels", package: "swift-language-models")
.product(name: "OpenAILanguageModels", package: "swift-language-models")
```

A provider module re-exports `LanguageModels`, which carries the contract every provider shares, so apps import the
provider module alone. A library that needs only the contract can depend on the `LanguageModelsCore` product instead, and
reads the same pages, under `LanguageModels`.

## Usage

Sessions, streaming, tools, guided generation and Dynamic Profiles are Apple's own, so the code is the same for every
model:

```swift
struct WeatherTool: Tool {
    let description = "Gets the current temperature in a city."

    @Generable
    struct Arguments {
        @Guide(description: "The city's name")
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        "It's 21°C in \(arguments.city)."
    }
}

@Generable
struct Itinerary {
    @Guide(description: "One plan per day", .count(3))
    var days: [String]
}

let session = LanguageModelSession(model: model, tools: [WeatherTool()])

for try await snapshot in session.streamResponse(to: "Do I need a jacket in Athens today?") {
    print(snapshot.content)  // The answer so far
}
let itinerary = try await session.respond(to: "Plan three days in Kyoto.", generating: Itinerary.self).content
```

A guided request goes only to a model whose provider enforces the schema, as Tools and guided generation describes
[for OpenRouter][tools] and [for OpenAI][openai-tools]. Some hosts drop guides such as a range or a count, so each
answer is checked against them, and one that breaks a guide throws `GeneratedContent.ParsingError`, whose
`underlyingError` is a `GuideViolations` that lists each value, its path, keyword and limit.

### Reasoning effort

Each catalog model has an effort type with only the levels it accepts. Any other level doesn't compile:

```swift
// Claude Haiku 5.5 takes .max, .xhigh, .high, .medium, .low and .off.
let response = try await session.respond(
    to: "How many weekdays are in March 2027?",
    contextOptions: ContextOptions(reasoningLevel: model.reasoningLevel(.xhigh))
)
```

A Dynamic Profile sets a model and one of its levels for the whole session:

```swift
struct TutorProfile<Model: DetailedLanguageModel>: LanguageModelSession.DynamicProfile {
    let model: Model
    let effort: Model.Details.Effort

    var body: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile { Instructions("You are a careful math tutor.") }
            .model(model, effort: effort)
    }
}

let tutor = LanguageModelSession(profile: TutorProfile(model: model, effort: .xhigh))
```

Apple's `.light`, `.moderate` and `.deep` still work, sent as the nearest level the model accepts. See
[Reasoning levels][reasoning-levels], and Reasoning [with OpenRouter models][openrouter-reasoning] or [with OpenAI
models][openai-reasoning] for what each level becomes.

### Attachments

From OS 27.2, in apps built with Xcode 27.2, `FileAttachment` adds PDFs and text to Apple's images, and audio and
video on OpenRouter:

```swift
if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) {
    let lease = try FileAttachment(contentsOf: leaseURL)
    let response = try await session.respond {
        "When does the lease end?"
        Attachment(lease).label("lease.pdf")
    }
}
```

From OS 27.2, in apps built with Xcode 27.2, a model that draws returns each image as a data entry:

```swift
import UniformTypeIdentifiers

let artist = OpenRouterLanguageModel(.googleGemini2_5FlashImage, auth: .apiKey { try await keyStore.openRouterKey() })
let drawing = try await LanguageModelSession(model: artist).respond(to: "Draw a lighthouse at dusk.")

if #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) {
    for case .data(let image) in drawing.transcriptEntries where image.contentType.conforms(to: .image) {
        print(image.contentType, image.content.count)  // Its type and size in bytes
    }
}
```

See Attachments [for OpenRouter][attachments] and [for OpenAI][openai-attachments], and [Reading model
details][model-details] to check what a model takes.

### Logging

Each request logs what it sends, its retries and how it ended, never keys, prompts or answers.
`LanguageModelsLogging.minimumLevel` sets how much. See [Logging][logging].

## OpenRouter

`OpenRouterLanguageModel` reaches every model on [OpenRouter](https://openrouter.ai) with one API key. Its
[documentation][openrouter-docs] starts with [Getting started][getting-started].

### Authentication

```swift
// An API key, read for every request and never stored. Use it during development, or for a key each person brings.
// A key bundled in an app can be extracted from it, so don't release with one.
OpenRouterLanguageModel(.anthropicClaudeHaiku5_5, auth: .apiKey { try await keyStore.openRouterKey() })

// Your own server adds the key and forwards each request to OpenRouter, so the app ships no key.
// The headers are read for every request, so a token can refresh.
OpenRouterLanguageModel(
    .anthropicClaudeHaiku5_5,
    auth: .proxied(
        baseURL: URL(string: "https://api.yourapp.com/openrouter/")!,
        headers: { ["X-App-Token": try await account.appToken()] }
    )
)
```

`.apiKey(baseURL:_:)` sends the key to another server that speaks OpenRouter's API instead, such as your company's
gateway. See [Authentication][authentication].

### Models

```swift
let haiku = OpenRouterModel.anthropicClaudeHaiku5_5  // Every model OpenRouter lists is a static member
print(haiku.contextSize ?? 0)                  // The context window, in tokens
print(haiku.reasoningEfforts.map(\.rawValue))  // The levels it accepts, highest first

let visionModels = OpenRouterModel.catalogModels.filter { $0.capabilities.contains(.vision) }  // To pick at runtime
let endpoints = try await haiku.endpoints()  // Each host's prices, limits and uptime, live
```

A bot keeps the catalog current. Models OpenRouter retires or stops listing stay, marked deprecated. See
[Choosing a model][choosing-a-model], [Model and provider info][model-info] and [Model catalogs][model-catalogs].

### Routing and fallbacks

```swift
let model = OpenRouterLanguageModel(
    .anthropicClaudeHaiku5_5,
    fallbacks: .openaiGpt5Mini, .googleGemini3_1FlashLite,  // Tried in order when the model fails
    // Only hosts that keep no prompts, lowest price first
    routing: OpenRouterRouting(dataCollection: .deny, zeroDataRetention: .required, sort: .price),
    auth: .apiKey { try await keyStore.openRouterKey() }
)
```

See [Routing and fallbacks][routing].

### Caching

```swift
let model = OpenRouterLanguageModel(
    .anthropicClaudeHaiku5_5,
    cacheControl: .automatic(timeToLive: .oneHour),  // Marks prompts for hosts that cache only marked ones
    responseCache: OpenRouterResponseCache(timeToLive: .seconds(600)),  // Answers a repeated request at no cost
    auth: .apiKey { try await keyStore.openRouterKey() }
)
```

`.automatic` is the default, with a five-minute cache. See [Caching][caching].

### Server tools

Server tools run on OpenRouter while the model answers:

```swift
let model = OpenRouterLanguageModel(
    .openaiGpt5Mini,
    serverTools: [.webSearch(maximumResults: 5), .webFetch(), .datetime(timeZone: .current)],
    auth: .apiKey { try await keyStore.openRouterKey() }
)
let response = try await LanguageModelSession(model: model).respond(to: "What changed in Swift this month?")

for case .response(let answer) in response.transcriptEntries {
    for citation in answer.openRouter.citations {
        print(citation.title ?? "Untitled", citation.url)
    }
}
```

Advisors and subagents are other models the answering model consults or hands tasks to, each billed at its price:

```swift
let researcher = OpenRouterLanguageModel(
    .openaiGpt5Mini,
    serverTools: [
        .advisor(model: "~anthropic/claude-opus-latest", forwardsTranscript: true),  // Consulted while it answers
        .subagent(model: "~anthropic/claude-haiku-latest", tools: [.webSearch()]),  // Takes self-contained tasks
    ],
    auth: .apiKey { try await keyStore.openRouterKey() }
)
```

See [Server tools][server-tools].

### Metadata and errors

```swift
do {
    let response = try await session.respond(to: "Plan dinner.")
    if let dollars = response.usage.openRouter.cost {  // The last request's; each tool round's is on its entry
        print("It cost $\(dollars).")
    }
    if case .response(let answer)? = response.transcriptEntries.last, let host = answer.openRouter.provider {
        print("\(host) answered.")
    }
} catch LanguageModelError.rateLimited(let limit) {
    print("Try again after \(limit.resetDate ?? .now).")
} catch let error as OpenRouterError where error.code == .paymentRequired {
    print("The account is out of credits.")
}
```

| OpenRouter | Thrown |
|---|---|
| A context too long for the model | `LanguageModelError.contextSizeExceeded` |
| 429, or too many requests in flight | `LanguageModelError.rateLimited`, with the reset date |
| A content policy or moderation flag | `LanguageModelError.guardrailViolation` |
| A refusal | `LanguageModelError.refusal` |
| 408, 504, 524, or a timed-out connection | `LanguageModelError.timeout` |
| Anything else, such as 401 or 402 | `OpenRouterError`, with its status, code and host |

See [Errors and metadata][errors-and-metadata], and [Mapping][mapping] for how each
request, answer and error translates.

## OpenAI

`OpenAILanguageModel` reaches OpenAI's models directly, through OpenAI's Responses API. Its [documentation][openai-docs]
starts with [Getting started][openai-getting-started].

```swift
import OpenAILanguageModels

let model = OpenAILanguageModel(.gpt6Luna, auth: .apiKey { try await keyStore.openAIKey() })
let session = LanguageModelSession(model: model)
```

### Authentication

`.apiKey` sends the key as a bearer token, with the organization and project when you set them.
`.proxied(baseURL:headers:)` sends requests to your own server, which adds the key, so the app ships none, and
`.apiKey(baseURL:organization:project:_:)` sends the key to another server that speaks OpenAI's API. See
[Authentication][openai-authentication].

### Models

```swift
let luna = OpenAIModel.gpt6Luna                // One of the catalog's models, each a static member
print(luna.reasoningEfforts.map(\.rawValue))   // The levels it accepts, highest first
let picked = OpenAIModel(catalogID: "gpt-5.5")  // A model picked at runtime, with its efforts in their open form
```

The catalog lists the models OpenAI's API description names for the Responses API and its model list still serves, with
what models.dev says each one takes. A model with a shutdown date stays, marked deprecated, until OpenAI shuts it down.
See [Choosing a model][openai-choosing-a-model].

### Reasoning and storage

A reasoning level goes as the nearest effort the model accepts, and `.off` as `none` where the model takes it. A
request that sets another level, or goes to a model that always reasons, leaves out `temperature` and `top_p`, and logs
that it did. Each answer's reasoning comes back encrypted and goes back on later turns, so a session works whether
OpenAI keeps its responses or not:

```swift
let options = OpenAIOptions(reasoningSummary: .auto, storage: .notStored)
let model = OpenAILanguageModel(.gpt6Luna, options: options, auth: .apiKey { try await keyStore.openAIKey() })
```

See [Reasoning][openai-reasoning] and [Caching][openai-caching].

### Metadata and errors

```swift
do {
    let response = try await session.respond(to: "Plan dinner.")
    if case .response(let answer)? = response.transcriptEntries.last {
        print("OpenAI's id for the request:", answer.openAI.requestID ?? "none")
    }
} catch LanguageModelError.rateLimited(let limit) {
    print("Try again after \(limit.resetDate ?? .now).")
} catch let error as OpenAIError where error.isQuotaExhausted {
    print("The account is out of credits.")
} catch let error as LanguageModelError {
    print("OpenAI's id for the request:", error.openAI.requestID ?? "none")
}
```

| OpenAI | Thrown |
|---|---|
| A context too long for the model | `LanguageModelError.contextSizeExceeded` |
| 429 that isn't a quota | `LanguageModelError.rateLimited`, with the reset date |
| A prompt flagged by OpenAI's usage policies | `LanguageModelError.guardrailViolation` |
| A refusal | `LanguageModelError.refusal` |
| 408, 504, or a timed-out connection | `LanguageModelError.timeout` |
| An image OpenAI can't use | `LanguageModelError.unsupportedTranscriptContent` |
| Anything else, such as 401 or a quota or credits that ran out | `OpenAIError`, with its status, code and request id |

See [Errors and metadata][openai-errors-and-metadata].

## Testing and evaluation

Any model can be the model under test, the judge or the sample generator in Apple's Evaluations framework. A scripted
model keeps unit tests offline.

- [Evaluating a feature across models][evaluating]
- [Testing with a scripted model][scripted-model]
- [Judging and generating samples with OpenRouter models][judging], or [with OpenAI models][openai-judging]
- Repeatable runs [with OpenRouter models][repeatable-runs] or [with OpenAI models][openai-repeatable-runs]

## Example app

[`Example/`](Example) holds Showcase, a macOS command-line tour with one short command file per feature. Its
[README](Example/README.md) says how to run it.

## Documentation

The [documentation][docs] is on the Swift Package Index, for [`OpenRouterLanguageModels`][openrouter-docs],
[`OpenAILanguageModels`][openai-docs] and [`LanguageModels`][core-docs], the core every provider module shares. For
sessions, tools and profiles, see Apple's
[Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels).

New to Foundation Models? [Foundation Models Academy](https://github.com/dioKaratzas/foundation-models-academy)
teaches it in 40 hands-on lessons, and runs its live lessons on OpenRouter with this package.

## Contributing

Ask questions and share ideas in [Discussions](https://github.com/ironsparrows/swift-language-models/discussions),
and report bugs in [Issues](https://github.com/ironsparrows/swift-language-models/issues). Pull requests are
welcome. For a larger change, such as a new provider module, open an issue first.
[CONTRIBUTING.md](CONTRIBUTING.md) says how to build, refresh the model catalog and add a provider module, which
[Writing a provider module][writing-a-provider] describes.
[ARCHITECTURE.md](ARCHITECTURE.md) maps how the modules fit together and how a request travels through them.

### Testing

`swift test` runs offline. The live suites call real models, and a full run costs a few cents:

```sh
# Add LIVE_SWEEP=1 to also sweep each vendor's cheapest model.
OPENROUTER_API_KEY=… swift test --filter 'OpenRouterLanguageModelsTests\.Live'

# OpenAI's live suite, on its cheapest models.
OPENAI_API_KEY=… swift test --filter 'OpenAILanguageModelsTests\.Live'

# Model and provider info, which needs no key.
LIVE_INFO=1 swift test --filter LiveInfoTests
```

Refreshing OpenAI's catalog needs a key too, since OpenAI lists the models it still serves only to a request with one:

```sh
OPENAI_API_KEY=… swift package plugin --allow-network-connections all:443 --allow-writing-to-package-directory generate-model-catalog
```

## Related projects

- [Foundation Models framework utilities](https://github.com/apple/foundation-models-utilities): Apple's extra
  utilities for the framework, such as custom skills, context management helpers and a chat completions client.
- [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel) reimplements the Foundation Models API, so it
  runs on earlier OS versions and Linux, and adds on-device backends such as MLX and llama.cpp.
- [ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels): Anthropic's native package
  for Claude models.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).

[docs]: https://ironsparrows.github.io/swift-language-models/documentation
[core-docs]: https://ironsparrows.github.io/swift-language-models/documentation/languagemodels
[reasoning-levels]: https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/reasoninglevels
[model-details]: https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/readingmodeldetails
[logging]: https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/logging
[model-catalogs]: https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/modelcatalogs
[evaluating]: https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/evaluatingacrossmodels
[scripted-model]: https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/testingwithascriptedmodel
[writing-a-provider]: https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/writingaprovider
[openrouter-docs]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels
[getting-started]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/gettingstarted
[authentication]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/authentication
[tools]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/toolsandguidedgeneration
[openrouter-reasoning]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/reasoning
[attachments]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/attachments
[choosing-a-model]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/choosingamodel
[model-info]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/modelandproviderinfo
[routing]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/routingandfallbacks
[caching]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/caching
[server-tools]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/servertools
[errors-and-metadata]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/errorsandmetadata
[mapping]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/mapping
[judging]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/judgingandgeneratingsamples
[repeatable-runs]: https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/repeatableruns
[openai-docs]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels
[openai-getting-started]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/gettingstarted
[openai-authentication]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/authentication
[openai-choosing-a-model]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/choosingamodel
[openai-reasoning]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/reasoning
[openai-caching]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/caching
[openai-errors-and-metadata]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/errorsandmetadata
[openai-judging]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/judgingandgeneratingsamples
[openai-tools]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/toolsandguidedgeneration
[openai-attachments]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/attachments
[openai-repeatable-runs]: https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/repeatableruns
