# Contributing

Ask questions and share ideas in [Discussions](https://github.com/ironsparrows/swift-language-models/discussions),
and report bugs in [Issues](https://github.com/ironsparrows/swift-language-models/issues). Pull requests are
welcome. For a larger change, such as a new provider module, open an issue first.

## Build and test

Before a pull request, run `swift build` and `swift test`, and format the code with swift-format, which reads
`.swift-format`. The README's [Testing](README.md#testing) section says how to run the live suites.

## Refresh the model catalog

The files in `Catalogs/` and the `Generated/` sources are generated, so don't edit them by hand. To refresh them from
the providers' model lists, run:

```sh
OPENAI_API_KEY=… swift package plugin --allow-network-connections all:443 --allow-writing-to-package-directory generate-model-catalog
```

OpenAI lists the models it still serves only to a request with an API key, so fetching its catalog needs one; without
it, `ModelCatalogGenerator fetch --sources openrouter` fetches the other source alone. A source that fails doesn't hold
back the others: the fetch writes the sources that worked, then fails with the `--sources` to fetch again. The workflow
reads the key from the `OPENAI_CATALOG_API_KEY` secret, apart from the live tests' `OPENAI_API_KEY`.

The Model catalog workflow does the same for every provider at once, and runs `ModelCatalogGenerator diff` to classify
the changes. When a source fails, the pull request still carries the sources that worked, with a warning, and the run
fails so someone looks. It keeps one pull request, `catalog/update`, with a changelog and a `release:` label for the
release the changes need:

- `major` when a generated member is deleted, which only a hand edit to a snapshot or the generator's `clear-removed`
  does. The pull request also gets `needs-review` and waits for a maintainer.
- `patch` for any other change to a snapshot: a member added, deprecated or made current again, a model that gains or
  stops accepting effort levels, or a model's limits or parameters.
- No label when only the shape of a provider's API changed.

A model, word or effort level a provider stops listing keeps its member, marked deprecated, so code that names it
still compiles, with a warning. `minor` is for the package's own features.

A fetch that loses more than a fifth of a source's models at once more likely ran into an outage, so it writes nothing.
Models lost on or after their expiration date don't count, since the source said when they'd go.

The workflow builds with warnings as errors, except deprecations. So when a provider retires or stops listing a model
that a snippet or fixture test names, the workflow still opens the pull request, but the pull request's CI, where
deprecations are errors too, fails and it doesn't merge: on `main`, name another model in that snippet or test, and in
the README if it names the model too, then run the workflow again. Live tests keep deprecations as warnings, so a model
they name doesn't hold the pull request back, and the warning says to replace it.

Any pull request but a major one merges once CI passes, and its label releases it.
[Model catalogs](https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/modelcatalogs)
describes the same rules for the package's users.

## Add a provider module

A provider module is named `<Vendor>LanguageModels`, and its `<Vendor>LanguageModel` conforms to
`DetailedLanguageModel`. Whatever its provider takes, its public face is the same as every other provider's: a model,
model details, authentication, a configuration, an error and typed facts. Compare the public surfaces, so an app moves
between providers without learning a new API.

[Writing a provider module](https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/writingaprovider)
is for a module in another package, which has only the public contract. In this repository a module also builds on the
shared models, which are `package`. How much it writes depends on what its provider takes:

| | It takes a format as it is | It takes a format, with additions | It has a wire format of its own |
|---|---|---|---|
| Its executor's `respond` | one line, into the shared model | one line, into the shared model | its own `run`, between the two checks |
| Values on the shared model | where requests go, and what's true of its models | the same | none |
| Exchange | `error(for:)` alone, since the plain exchange throws a `RequestFailure` apps can't read | only the methods it needs | none |
| Request and stream types | none | the exchange's members and chunk extras | its own |
| Sending, the transcript, attachments, the channel | reused | reused | reused |
| Removed-model report, guide check | inside the shared model | inside the shared model | two calls of its own |

The last column needs `ByteLines`, `TranscriptTurn`, `AttachmentReader`, `AnswerChannel` and `RequestLog`, which are
internal to `LanguageModels` today. They become `package` in the pull request that adds such a provider, not before.

In this repository:

- Add `provider("<Vendor>")` to `providers` in `Package.swift`. That declares the module, its library product, and a test
  target that copies `Tests/<Vendor>LanguageModelsTests/Fixtures`, which you create. The module depends on
  `LanguageModels` alone, and re-exports it with `@_exported public import LanguageModels`, so an app imports only the
  provider.
- A provider whose models come from a list gets a case in `ModelCatalogGenerator`'s `CatalogSource`, which names it, says
  where its API lives and lists its vocabularies, and code that reads its list into the catalog's models, as
  `Providers/OpenRouterCatalog.swift` does for OpenRouter and `Providers/OpenAICatalog.swift` does for OpenAI. The
  generator then keeps a snapshot of the list in `Catalogs/<provider>.json`, and turns it into a static member and an
  effort type for each model, such as `Efforts.Of<OpenRouterCatalog.AnthropicClaudeHaiku5_5>`. The Model catalog
  workflow picks the new provider up with the others. A word the module's code names, such as a parameter a request
  sends, goes in the source's `wordsNamedByModule(in:)`, so a list that stops naming it doesn't deprecate its member and
  fail the build.
- The generator also writes `Generated/ModelRemovals+<Name>.swift`, with the models the provider stopped listing as
  `ModelRemovals.<name>`, where `<Name>` is the source's `swiftName`, such as `ModelRemovals.openRouter` in
  `ModelRemovals+OpenRouter.swift`. The details' `removalDate` returns `ModelRemovals.<name>.removalDate(of:)` for the
  model's id, as `OpenRouterModel` does; a provider without a catalog returns `nil`. Test that each removed model in
  the table has its `removalDate`, as `RemovalDateTests` does for OpenRouter.
- Nest a public `Executor` in the model, conforming to Foundation Models' `LanguageModelExecutor`. Keep its `Configuration`
  to where requests go and how they're sent, with no secrets. Its `respond` is one line: it derives the shared model and
  calls that model's `respond`, as `OpenRouterLanguageModel.Executor` does. The function that derives it, such as
  `chatCompletions(_:)`, opens the provider's exchange file and sets the values
  [ARCHITECTURE](ARCHITECTURE.md#what-a-provider-states) lists. Pass `reaching:` every model a request may reach, in the
  order the provider tries them, so the shared model reports the removed ones.
- A value saved transcripts hold never changes: `reasoningOrigin`, such as `openrouter` for OpenRouter's Chat Completions
  reasoning and `openai-responses` for OpenAI's Responses reasoning, `phasesKey`, such as `openAI.phases`, and
  `serverToolsKey`, such as `openAI.serverTools`. Each shared model's initializer requires the ones it has, and
  `images`, so a provider can't forget one. Give each format its own origin, since each sends reasoning back in another
  shape: reasoning a model wrote in one format is then skipped, not sent back in the wrong one.
- Keep what the model, the exchange and any info calls all rely on in the module's `Internal/API.swift`: the provider's
  name, base URL, paths and header names.
- Give the model a public configuration of the module's own, such as `VendorConfiguration`, built only from the core's
  pieces the module uses, `RequestRetries` and `ImageEncoding`, and an `idleTimeout`. Never declare a retry or image
  setting of the module's own. Make `Connection` from it, with the `RetriedStatuses` rule for which statuses to retry,
  such as `.transient`. A rule that isn't there yet is a new case of `RetriedStatuses`.
- Throw Foundation Models' error wherever it has a case, from `error(for:)`, and the module's own for the rest. Say what
  each status stands for in a `switch` over `HTTPStatus` with no `default`, as `OpenRouterFailure` and `OpenAIFailure` do,
  so a status named later stops the module's build until it decides. A status without a name is `.other`. Naming one also
  takes a row in `HTTPStatus.init(code:)` and in `HTTPStatusTests`, which no compiler checks. Read facts through
  `ProviderResponseMetadata`, `ProviderUsageMetadata` and `ProviderErrorMetadata`, and give apps a reader named for the
  provider, such as `openRouter`. Its keys live in the module's metadata file, private to it, apart from the
  `phasesKey` and `serverToolsKey` the shared Responses model takes.
- Log through a `PackageLogger` with a category named after the module, which writes only at the levels the app's
  `LanguageModelsLogging.minimumLevel` lets through. Where the module works around a likely mistake, such as a setting
  the model doesn't take, log it at the info level and call `runtimeWarning(_:)`, which shows a runtime warning in a
  debug build.
- Call `checkProvider` from the module's tests, as `ProviderChecksTests` does. It reads the models the provider gives its
  shared model, and holds an answer to its guides. It can't see the report, which only logs, so a provider with a format
  of its own has to show its call to `reportRemovedModels(for:)` another way: details whose computed `removalDate` confirms
  each read, as `ModelRemovalsTests` has.

## Where shared code goes

Code lives in the narrowest place that every user of it can reach:

- **`LanguageModelsCore`** holds the public API, and what the public API itself needs: `DetailedLanguageModel`, model
  details, efforts, configuration values, vocabularies, attachments, typed facts, guide violations and the logging switch,
  with ordered JSON, the package logger and the removed-model reports they use. It compiles no HTTP code, and never
  imports `LanguageModels`.
- **`LanguageModels`** holds the two shared models, in `Models/ChatCompletions/` and `Models/Responses/`, and in `Shared/`
  what both use. Only `Exports.swift` is `public`, which CI checks. A provider writes `package` names, and the rest stays
  internal. Its tests run on the plain models, so they check a format alone.
- **A provider module** holds what only its provider has: its public types, its exchange, its catalog and info calls and
  its errors. Its public types never name a format's types.

`Shared/` is flat, and each file owns one thing:

| File | Owns |
|---|---|
| `Connection.swift` | How requests reach a provider: session, authentication, timeout, retries; opening a stream, with one more attempt in the portable schema; cached read-only calls about a model. |
| `HTTPClient.swift` | Sending: the retry loop and policy, waits a server asks for, redirects to the same scheme, URL host and port only, the user agent, statuses, header and media-type names. |
| `ServerSentEvent.swift` | Events of a byte stream, and the byte-level line splitter under them. |
| `RequestLog.swift` | The log of one request: what it sends, retries, adjustments, how it ended, and what the log says of an error. |
| `TranscriptTurn.swift` | The transcript as provider APIs take it: turns, a turn's segments as a format's parts, the first prompt's id, and which reasoning goes back. |
| `AttachmentReader.swift` | An attachment as content to send: kinds, text, PDFs, data URLs. |
| `EncodedImage.swift` | An image as JPEG no larger than a size, and the bounded cache of encoded images. |
| `RequestSettings.swift` | What a request sends of the app's settings: sampling, tool choice, metadata within its limits, the body with the provider's members and the app's over them, and what it leaves out or changes. |
| `AnswerChannel.swift` | Writing one answer to Foundation Models' channel: text, reasoning, reasoning tagged inside the text, tool calls assembled from fragments, data, citations, how an answer ends, facts and usage. |
| `RequestFailure.swift` | A failure before a provider maps it, and the helpers that map it. |

A provider hands a shared model values and an exchange, and never touches a transcript reader, a stream or the channel.
[ARCHITECTURE](ARCHITECTURE.md#what-a-provider-states) lists all of it. Add a method to an exchange, or a value to a model
or a request, when a provider needs one, with a default that keeps the plain format's behavior. A value that nothing
would show missing, or that can't be undone, has no default: it's a required argument of the model's initializer.
Implement a method that has a default in the type that declares the conformance: only there does a misspelled one draw a
warning, which CI's `-warnings-as-errors` turns into an error, instead of silently keeping the default.

## Sets of values

Inside the package, a set that a decision reads is an enum, and a `switch` over it has no `default`, so a new case is a
compile error wherever it needs a decision. A value that only names something, and that nothing branches on, stays what
it is. A word a host sends stays open: there `default` is the decision.

A public set takes the shape that lets it grow without breaking an app:

| The set | Its shape |
|---|---|
| Can't grow, such as on, off or automatic | A plain `enum` |
| Hosts send it, or apps add to it | A struct over `rawValue`, a `ProviderVocabulary` |
| Apps build it, with payloads they shouldn't see, such as authentication or server tools | A struct with static members |
| Only the package defines it, apps read or pick it, and it can grow | A `@nonexhaustive` enum, from its first release, since adding the attribute later breaks apps |

## How a module's files are laid out

No number decides a file's size. A file owns a responsibility, reads top to bottom, and keeps private whatever nothing
else needs:

- **A file owns one responsibility a reader looks for by name**, and reads top to bottom under marks: the type, how it
  works, what it needs.
- **What only that file needs is `private` there**: wire types, coding keys, helpers, small extensions of other types. A
  wire type lives in the file that writes or reads it, never in a file of its own.
- **A mechanism lives with what it serves.** It gets a file of its own only when two files use it.
- **A public type gets its own file when it's read on its own**: it has options or behavior worth opening by itself, such
  as options, routing or server tools. A small value that only parameterizes one type lives in that type's file.
  Vocabularies share one file per module.
- **Split at a seam, never at a size.** A seam is where the other side needs one narrow entry: the request needs the
  transcript as one value, and the model needs the stream as one type. One type is one file. A long file is a reason to
  look for a second responsibility, and to leave it whole when there is none.
- **A file is named after its primary type or its responsibility.** No "Utils", "Helpers" or "Wire". No hand-written
  `Type+Topic.swift`: a type that seems to need a second file has a second responsibility, and that gets its own name.
  Generated files keep their names, and tests may keep topic files, such as `LiveTests+Caching.swift`: one suite extended
  by topic.
- **Folders only where they carry meaning**: `Models/<format>/` and `Shared/` in `LanguageModels`, `Generated/`,
  `Documentation.docc/`, and `Internal/` in the core and the provider modules. A file of those modules with no `public`
  declaration goes in `Internal/`, so a reader sees first what they can use. The rest of those modules is flat.
  `LanguageModels` has no `Internal/`: all of it is `package` or internal, and `Shared/` does that job.
- **Access is the narrowest that compiles.** `public` for what apps use, `package` for what another target writes today,
  another target's tests included, nothing written for the rest of a target, and `private` for what one file uses, or
  `fileprivate` when a sibling in that file reads it. `internal` is never written. A module's own tests use `@testable`.
  The defaults of an `Exchange` protocol stay `package`, so a provider can leave those methods out. A helper with unit
  tests of its own stays internal, since `@testable` tests can't reach a `private` type. Wire types have no such tests and
  are `private`.
- **Initializers of a generic public type stay in the struct.** In an unconstrained extension, DocC adds "Available when"
  to each page.

### Marks

- `// MARK: - Title` opens each section of a file, which gives it a separator in Xcode's jump bar. `// MARK: Title`,
  without the dash, groups members inside one type, so a reader sees sections first and groups under them.
- A title says what the section holds, in sentence case, with no period: "Before it is sent", "Wire". Never "Private",
  "Helpers", "Extensions" or a protocol list.
- Files of one kind use the same titles in the same order, word for word. A section that doesn't apply is left out, and
  the order of the rest doesn't change.
- "Wire" is always the last section: the `Encodable` and `Decodable` types and their coding keys, `private` unless
  another file of the module reads them.
- A file with one section has no mark. Tests have none: suites structure them.

| Kind | Files | Sections, in order |
|---|---|---|
| A provider's model | `OpenRouterLanguageModel.swift`, `OpenAILanguageModel.swift` | Model · Creating a model · Details and capabilities · Settings · Executor |
| A shared model | `ChatCompletionsModel.swift`, `ResponsesModel.swift` | Model · Answering · Executor · Exchange · Plain exchange · Defaults |
| A provider's exchange | `OpenRouterExchange.swift`, `OpenAIExchange.swift` | As a Chat Completions model (or: As a Responses model) · Exchange · Wire; inside the exchange: While the request is read · Before it is sent · While the answer streams · When it ends, or fails |
| A request | `ChatCompletionsRequest.swift`, `ResponsesRequest.swift` | Request · Reading · Body · Wire |
| A transcript reader | `ChatCompletionsTranscript.swift`, `ResponsesInput.swift` | Turns · Attachments · Wire |
| A stream | `ChatCompletionsStream.swift`, `ResponsesStream.swift` | Stream · Receiving · Finishing · Wire |
| A provider's error | `OpenRouterError.swift`, `OpenAIError.swift` | Error · Codes · Response body · What a failure becomes · Logging |
| A module's metadata | `ProviderMetadata.swift`, `OpenRouterMetadata.swift`, `OpenAIMetadata.swift` | Response · Usage · Generated data · Error · Reading · Keys |

The groups inside an exchange are the marks of the protocol, so the protocol and each provider's conformance read alike
in the jump bar.

## Tests

Each behavior is tested at one level, and a test earns its place by catching a bug nothing else would:

| Level | Target | A behavior belongs here when |
|---|---|---|
| 1 Contract | `LanguageModelsCoreTests` | it needs no HTTP: it's a function of the core's own types. |
| 2 Shared models | `LanguageModelsTests` | the plain model shows it, so every provider of the format gets it. Transport, every split point of a stream, the parts with an algorithm of their own, and one suite over real loopback HTTP are here too. |
| 3 Providers | `OpenRouterLanguageModelsTests`, `OpenAILanguageModelsTests` | it differs from the plain model: a member, a header, a chunk member, an error mapping, an option. Exact exchanges pin whole requests and answers, and one test goes through public API alone over loopback HTTP. |
| 4 Live | each provider's `Live/` folder | only the real provider can show it. Tagged, and skipped without a key. |

A test may not assert what a lower level owns. An OpenRouter server-tool test asserts the member OpenRouter adds, and
doesn't check again how tool-call fragments are joined. Each test target links what it tests and
`LanguageModelsTestSupport`, nothing more, and a provider's tests don't import `LanguageModels` with `@testable`.

- **Layout.** One root suite per area, with a file per behavior that extends it, such as
  `ChatCompletionsModelTests+ToolCalls.swift`. `LanguageModelsTests` mirrors `Sources/LanguageModels/`. Use Swift Testing
  only, with names as sentences in backticks and one suite per file.
- **Traits.** Put `.timeLimit` on the root suite, once, where nested suites inherit it. Live roots add `.tags(.live)` and
  their key condition. The only tags are `live`, `liveSweep` and `loopback`, since `swift test` selects by name.
- **Arguments.** Use `arguments:` in place of a loop over cases, so a failure names its input.
- **`confirmation`.** Use it where a count is the behavior and nothing records it. Where a stub records requests, a count
  of requests stays an `#expect`.
- **`.bug`.** Put it on a test that pins a fixed defect, with its pull request or issue.
- **Sockets.** Only the suites tagged `loopback` open one. The rest answer through `HTTPStub`.

Test a provider's requests and answers through Foundation Models, as `ExactExchangeTests` does with
`LanguageModelsTestSupport`'s `ExactExchange`: the bytes each request sends and what the session's transcript holds
afterwards. Never reflect on Apple's types: pin them through a session, the bytes, the transcript, usage and the last
snapshot.

### Snapshots

Snapshots hold whole request bodies, exchanges and errors. A single value, a typed reader or a count reads better as an
`#expect`, and the generator's golden files stay as they are.

- Nobody types or edits snapshot text. It's recorded.
- CI never records: `ci.yml` and `model-catalog.yml` set `SNAPSHOT_TESTING_RECORD=never`.
- Locally, a new snapshot is written and fails that run once, and a wrong one fails and isn't rewritten. To re-record on
  purpose, run `SNAPSHOT_TESTING_RECORD=failed swift test --filter <suite>`.
- A snapshot says what changed, not what's right. A commit that changes one says why, and changes nothing else.
- `.memberLines` shows a body with whitespace added outside its strings, so a diff reads well and the bytes stay exact.

### Fixtures

Back a test with a real recording, in the test target's `Fixtures`, with ids and other account values swapped for fake
ones. Build a fixture by hand only for what a host won't send on demand, such as a cut-off stream or a dropped
connection.

[ARCHITECTURE](ARCHITECTURE.md) maps how the modules fit together: which depends on which, how one request travels
through them, and what a provider states at each step.
