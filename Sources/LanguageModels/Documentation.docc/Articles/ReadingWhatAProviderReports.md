# Reading what a provider reports

Read the model, the host, the cost and the other facts a provider reports about an answer, with any provider's model.

## Overview

An answer reports more than its content: the model that answered, the host that ran it, why it ended and what it cost.
`providerMetadata` reads those facts the same way for every provider module, so code that reads them works with any
language model in this package. It's on a transcript's response and tool-calls entries, on a usage and on a
`LanguageModelError`.

A fact the provider didn't report is `nil`, and a list it didn't report is empty. Providers report different facts:
OpenRouter names the host and the cost but no request id, and OpenAI names the request id but no host and no cost.

### Read what an answer reports

The response entry that ends an answer carries its facts, and
``FoundationModels/Transcript/Response/providerMetadata`` reads them as ``ProviderResponseMetadata``:

@Snippet(path: "swift-language-models/Snippets/ProviderMetadata", slice: "response")

``ProviderResponseMetadata/model`` is the model that answered, in the provider's spelling of its id, which can differ
from the one asked for when the provider routes the request or a fallback answers. A text answer cut off at its token
limit doesn't throw, so a ``ProviderResponseMetadata/finishReason`` of ``FinishReason/length`` is the way to tell. A
guided answer, or tool calls, cut off there throw instead.

### Read a request that ended in tool calls

Each round of tool calls is a request of its own, and a tool-calls entry ends it instead of a response entry. Foundation
Models keeps no readable metadata on a tool-calls entry, so the request's facts sit on its first call, and
``FoundationModels/Transcript/ToolCalls/providerMetadata`` reads them from there, as ``ProviderResponseMetadata``. A
request that asks for several calls at once has one set of facts:

@Snippet(path: "swift-language-models/Snippets/ProviderMetadata", slice: "toolCalls")

A response entry that tool calls follow carries only the ``ProviderResponseMetadata/citations``, which point into the
answer's text.

### Read what an answer cost and counted

A response's `usage` holds Foundation Models' token counts.
``FoundationModels/LanguageModelSession/Usage/providerMetadata`` reads what the provider reported beyond them as
``ProviderUsageMetadata``: the cost in US dollars, the prompt tokens written to the host's cache and the web searches
the provider ran:

@Snippet(path: "swift-language-models/Snippets/ProviderMetadata", slice: "usage")

A session's own `usage` adds up the token counts of its requests but keeps no metadata, so its facts are all `nil`. A
response whose tool calls ran has only the last request's usage. Each request's facts are also on the entry that ends
it, which ``ProviderResponseMetadata/usage`` reads, so adding up their costs gives what the whole response cost:

@Snippet(path: "swift-language-models/Snippets/ProviderMetadata", slice: "cost")

### Read what a failure reports

A failure that throws Foundation Models' `LanguageModelError` carries what the provider reported, which
``FoundationModels/LanguageModelError/providerMetadata`` reads as ``ProviderErrorMetadata``:

@Snippet(path: "swift-language-models/Snippets/ProviderMetadata", slice: "errors")

``ProviderErrorMetadata/status`` is `nil` for a failure in the stream, which arrives after the response's HTTP 200.
``ProviderErrorMetadata/host`` names the host that failed, such as the one OpenRouter sent the request to. An error
that Foundation Models threw itself, such as for a capability the model lacks, has none of these facts.

### Read what only one provider reports

Each provider module also has a reader of its own, in the same four places, through a property named for the provider.
It reads the shared facts in the provider's own types, and what only that provider reports. Use `providerMetadata` in
code that works with any model, and a provider's reader in code that works with that provider's models:

- [`openRouter`](https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/errorsandmetadata):
  how OpenRouter routed the request, the hosts it tried, the response cache, the host's charge and the server tools'
  calls.
- [`openAI`](https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/errorsandmetadata):
  the phase of each of an answer's messages.

### Apple's guides

- [Transcripts](https://developer.apple.com/documentation/foundationmodels/transcripts)
- [LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror)
