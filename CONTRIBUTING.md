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

- `major` when a generated member is deleted, which only a hand edit to a snapshot does. The pull request also gets
  `needs-review` and waits for a maintainer.
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
`DetailedLanguageModel`. The article
[Writing a provider module](https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/writingaprovider)
describes the model, its request executor and what it reports. In this repository:

- Add `provider("<Vendor>", uses: [...])` to `providers` in `Package.swift`, naming the API format targets the module
  builds on, such as `provider("OpenRouter", uses: ["ChatCompletionsAPI"])` or `provider("OpenAI", uses:
  ["ResponsesAPI"])`. That declares the module, its library product, and a test target that copies
  `Tests/<Vendor>LanguageModelsTests/Fixtures`, which you create. The module depends on `LanguageModels` and on those
  formats, and re-exports only `LanguageModels`, with `@_exported public import LanguageModels`, so apps never import a
  format.
- A service whose models come from a list gets a case in `ModelCatalogGenerator`'s `CatalogSource`, which names it, says
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
- The module writes a `RequestExecutor` that conforms to `DetailedLanguageModelRequestExecutor`. The core's
  `DetailedLanguageModelExecutor` is always the model's executor: it logs an error and, in a debug build, shows a
  runtime warning for each removed model a request may reach, then calls the request executor's `execute`, which
  returns the answer's response text in a `DetailedLanguageModelAnswer`, or empty text when the answer ends in tool
  calls. For a request with a schema, the executor checks that text against the schema's guides and throws
  `GeneratedContent.ParsingError` when a value breaks one.
- Send requests through the module's API format, as [Where shared code goes](#where-shared-code-goes) describes. The
  format already reads the transcript, attachments and the stream, assembles streamed tool calls, reads reasoning tags
  and sends the answer to Foundation Models' channel, with `APIFormat`'s `TranscriptTurn`, `AttachmentReader`,
  `ServerSentEvent.Events`, `ToolCallAssembler`, `TaggedReasoning` and `AnswerChannel`, which provider modules never
  import. For the rest, build on the core's shared pieces rather than writing them again: `ProviderConnection` and
  `RequestAuthentication` for how requests reach the provider and the auth closure, `ProviderHTTP` to send requests with
  the package's `User-Agent` and the `RetryPolicy` that `RequestRetries.policy(statuses:)` makes from the app's
  settings, `ResponseHeaders` to read a response's headers,
  `HTTPHeaderName`, `HTTPMethod` and `MediaType` for their names, `JSONKey` for JSON members named at run time,
  `InfoTransport` for cached info calls, `Sampling` for the sampling settings and seed, `ReasoningOrigin` for reasoning
  entries, `HTTPRejection`, `MappedError` and `LanguageModelError.ProviderFailure` for errors, and `OperationLog` for
  the log.
- Give the model a public configuration of the module's own, such as `VendorConfiguration`, built only from the core's
  pieces the module uses: `RequestRetries`, `ImageEncoding` and an idle timeout. Conform it to `RetryingConfiguration`
  and `ImageEncodingConfiguration` for the pieces it holds, and the model to `ConfigurableLanguageModel`, as
  [Writing a provider](https://ironsparrows.github.io/swift-language-models/documentation/languagemodels/writingaprovider)
  shows. Never declare a retry, timeout or image setting of the module's own.
- Log through a `PackageLogger` with a category named after the module, which writes only at the levels the app's
  `LanguageModelsLogging.minimumLevel` lets through. Where the module works around a likely mistake, such as a setting
  the model doesn't take, log it at the info level and call `runtimeWarning(_:)`, which shows a runtime warning in a
  debug build.

## Where shared code goes

Code lives in the narrowest place that every user of it can reach:

- **The core, `LanguageModels`**, holds the public API and what any provider would use, whatever its API looks like:
  sending requests (`ProviderHTTP`, `ProviderConnection`, `ResponseHeaders`), the requirements every format's dialect
  shares (`ProviderDialect`) and the types its hooks share (`AnswerFacts`, `AttachmentKind`, `BodyContext`,
  `GeneratedData`, `HeaderContext`, `ReplayedReasoning`, `StreamProblem`), failures as a provider's mapping reads them
  (`HTTPRejection`, `MappedError`), JSON and schemas (`JSONValue`, `JSONKey`, `JSONValueEncoder`, `portableSchema`),
  sampling, effort words, reasoning origins, errors and logging.
- **`APIFormat`** holds what the format targets share and provider modules never name: reading the transcript
  (`TranscriptTurn`, `AttachmentReader`) and streams (`ServerSentEvent`), assembling tool calls (`ToolCallAssembler`),
  reasoning a model writes in its answer's text (`TaggedReasoning`), sending the answer to Foundation Models' channel
  with the facts and usage a format reports (`AnswerChannel`, `AnswerReport`, `AnswerUsage`, `AnswerEnding`), opening a
  stream with one retry in the portable schema when a host rejects a schema's constraints
  (`ProviderConnection.openEventStream`, `SchemaConstraint`), the stream loop and the request's log, the changes a
  request makes to what the app asked for (`RequestAdjustment`), and request metadata within its limits. Provider
  modules never import it.
- **An API format target**, such as `ChatCompletionsAPI` or `ResponsesAPI`, holds one format and nothing a provider adds
  to it. It isn't a product, it depends only on the core and `APIFormat`, and it offers providers, as `package`, only
  its dialect protocol, such as `ChatCompletionsDialect` or `ResponsesDialect`, its one way in,
  `respond(to:model:streamingInto:as:)`, and the types its hooks take and return. Everything else in it, its executor
  included, is internal. Its tests use a dialect of their own, so they check the format alone.
- **A provider module** holds what only its service has: its public types, its catalog and info calls and its errors.
  Its dialect, in one folder named after the format, such as `ChatCompletions/` or `Responses/`, conforms to the dialect
  protocol, and its request executor's `execute` there is one call into the format. No file outside that folder imports
  the format target.

A dialect names the provider, the model a request is for, its base URL and how requests reach it, and turns failures
into the provider's own public error. Every other hook has a default that keeps the format's behavior, so a service that
takes the format as OpenAI defines it writes only those. A dialect with more implements only what its service changes,
each with a typed value: its headers; its own members of the body as an `Encodable` type, their order, so the bytes a
host caches stay the same, and the members its models may not list; the attachments only it takes; the reasoning it
sends back; and what its chunks carry beyond the format's, as a `Decodable` type it reads into a state of its own.
Chat Completions has all of these. Responses, whose only provider so far is OpenAI, has only the body, the listed
members, the attachments, the reasoning that goes back and a state read from the response's headers, and adds two of
its own: the role of the message the instructions go in, and the metadata key that keeps the phase of each message of
an answer; add a hook there when a provider needs one. Each hook receives a value only the format creates, holding just
what that hook needs, and a dialect that sets a type without the hook that uses it doesn't compile. Implement the hooks
that have a default in the extension that declares the conformance: only there does a misspelled hook draw a warning,
which CI's `-warnings-as-errors` turns into an error, instead of silently keeping its default.

The provider's own types, such as its model, errors, options and vocabularies, never name a format type; only its
dialect folder does, and so do only its tests in a test folder of the same name. Moving a provider to another format, or
picking one per model, then means writing a dialect for that format, and its public API stays the same. Give each format
its own `ReasoningOrigin`, since each sends reasoning back in another shape: reasoning a model wrote in one format is
then skipped, not sent back in the wrong one. Keep the values saved transcripts already hold, such as `openrouter` for
OpenRouter's Chat Completions reasoning and `openai-responses` for OpenAI's Responses reasoning, and the Responses
metadata key that keeps each message's phase, such as `openAI.phases`.

Test a provider's requests and answers through Foundation Models, as `ExecutorExactExchangeTests` does with
`LanguageModelsTestSupport`'s `ExactExchange`: the bytes each request sends and what the session's transcript holds
afterwards. A stream recorded from the real service, kept in the test target's `Fixtures`, pins the events it sends.
Test the dialect in the provider's test folder named after the format, and the format's own behavior in the format's
test target, so moving a provider to another format doesn't rewrite its other tests.

## How a module's files are laid out

Each module keeps the same shape, so a file's place says what it is:

- **The root** holds the module's core types, one file each, such as `OpenRouterLanguageModel.swift`,
  `OpenRouterOptions.swift` and `OpenRouterError.swift` in the provider, `DetailedLanguageModel.swift` in the core and
  `ChatCompletionsDialect.swift` in a format. Reading the root is reading the module's main API.
- **A folder per family** holds the types and extensions that belong together, such as `Efforts/`, `Metadata/`,
  `Options/`, `Vocabulary/`, `Info/` or a format's `Hooks/`. A type's extensions go in its family's folder, named
  `Type+Topic.swift`.
- **`Internal/`** holds the files apps can't see at all: types and extensions that are only `internal` or `package`,
  grouped in subfolders when there's a lot of them, as the core's `Internal/Provider/` and `Internal/JSON/` are. A
  public type keeps its own `package` members in its own file.
- **`Generated/`** holds the generator's output, and a provider's **format folder**, such as `ChatCompletions/`, holds
  its dialect.

Keep folders one or two levels deep, and group by what code is, not by who calls it.

[ARCHITECTURE](ARCHITECTURE.md) maps how the modules fit together: which depends on which, how one request travels
through them, and which dialect hook runs at which step.
