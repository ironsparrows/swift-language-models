# Reading model details

Read what a provider module reports about a model: its name, capabilities, context size, reasoning levels and data
kinds.

## Overview

A provider module's model conforms to ``DetailedLanguageModel``, so it carries ``ModelDetails`` in
``DetailedLanguageModel/details``. Foundation Models reads the model's capabilities from them, and an app reads the
rest, such as to show a model's context size or to offer only models that call tools:

@Snippet(path: "swift-language-models/Snippets/Catalog", slice: "details")

A value the provider module doesn't report is `nil`. <doc:ReasoningLevels> shows how to use the levels a model
accepts.

### Identify models

A model's id is the service's id, in a type of the provider module's own that conforms to ``ProviderVocabulary``, so
one module's id can't be passed where another's belongs. Other words from a service's API, such as parameter names,
have types of their own too. A string literal creates any of them, and each encodes as its raw string.

### Check data kinds

``ModelDetails/dataAttachmentTypes`` lists the kinds of data a model accepts as prompt attachments, such as images or
PDF documents, and ``ModelDetails/dataEntryTypes`` the kinds it generates besides text, such as images. A kind that
conforms to a listed one, such as PNG to image, counts too.

From OS 27.2, Foundation Models asks the model itself, with `supportsDataAttachmentType(_:)` and
`supportsDataEntryType(_:)`, which need Xcode 27.2 at build time:

@Snippet(path: "swift-language-models/Snippets/Catalog", slice: "dataKinds")

``DetailedLanguageModel`` answers from the details. A provider module's model can answer for more than its details
describe, such as for every model a request may reach.

### Apple's guides

- [LanguageModel](https://developer.apple.com/documentation/foundationmodels/languagemodel)
- [LanguageModelCapabilities](https://developer.apple.com/documentation/foundationmodels/languagemodelcapabilities)
