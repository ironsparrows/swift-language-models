# Reasoning levels

Choose how much a model reasons, with the model's own levels or Apple's.

## Overview

Each model accepts its own reasoning levels: Claude Haiku 5.5 takes `max`, `xhigh`, `high`, `medium`, `low` and
`off`, and GPT-5 Mini takes `high`, `medium`, `low` and `minimal`. ``DetailedLanguageModel/reasoningLevel(_:)``
takes only the levels the model accepts, so code completion offers exactly those:

@Snippet(path: "swift-language-models/Snippets/Effort", slice: "modelLevel")

### See a model's levels

- In Xcode, type `model.reasoningLevel(.` and code completion lists exactly the model's levels.
- At runtime, ``ModelDetails/reasoningEfforts`` lists them, highest first:

  @Snippet(path: "swift-language-models/Snippets/Effort", slice: "levels")

- The model's effort type, ``ModelDetails/Effort``, is its own: ``Efforts/Of`` a type named after the model, such as
  `Efforts.Of<OpenRouterCatalog.AnthropicClaudeHaiku5_5>` for Haiku 5.5. The model carries the type, so an
  `OpenRouterLanguageModel` of Haiku 5.5 is an
  `OpenRouterLanguageModel<Efforts.Of<OpenRouterCatalog.AnthropicClaudeHaiku5_5>>`.

A catalog model that doesn't reason, or reasons at a level it picks itself, has an effort type with no levels. A
model described by hand can use ``Efforts/Unsupported`` for that.

### Set a level for a whole session

``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)`` sets a model on a Dynamic Profile at one of
its own levels, checked the same way. A profile that's generic over its model works with any model, and the effort's
type follows from the model you pass:

@Snippet(path: "swift-language-models/Snippets/Effort", slice: "profile")

Declare a profile as a type, as above. With Swift's default isolation set to the main actor, as in a new Xcode app
project, a profile built in a function and passed to `LanguageModelSession(profile:)` fails to compile with "sending
'profile' risks causing data races".

A request's `ContextOptions` replaces the profile's level for that request. A `reasoningLevel(_:)` applied around a
profile that sets ``FoundationModels/LanguageModelSession/DynamicProfile/model(_:effort:)`` doesn't replace the
effort.

### Apple's levels work too

Apple's `.light`, `.moderate` and `.deep` work with every model too, in a request's `ContextOptions` or with
`reasoningLevel(_:)` on a profile:

@Snippet(path: "swift-language-models/Snippets/Effort", slice: "request")

@Snippet(path: "swift-language-models/Snippets/Effort", slice: "sessionLevel")

A provider module sends the nearest level the model accepts: `.light`, `.moderate` and `.deep` ask for `low`, `medium`
and `high`, and a level the model doesn't accept moves to the nearest one it does, the lower one on a tie. A model
asked to reason keeps reasoning, so only a model's own `off` turns reasoning off.

### Pick levels at runtime

A model whose levels are known only at runtime, such as one a person picks from a list, has
`ContextOptions.ReasoningLevel` as its effort type, so ``DetailedLanguageModel/reasoningLevel(_:)`` and the same
generic profile take any level for it. Pick one from its details to send a level it accepts, as
<doc:ReadingModelDetails> shows:

@Snippet(path: "swift-language-models/Snippets/Effort", slice: "runtime")

To show or store a level in this form, ``FoundationModels/ContextOptions/ReasoningLevel/effortWord`` reads its word:
`low`, `medium` and `high` for `.light`, `.moderate` and `.deep`, and a custom level's own word, such as `xhigh`.

### Effort types

Each catalog model has an effort type of its own: ``Efforts/Of`` a type the catalog generates for the model. Its
static members are the model's levels, and `allCases` lists the levels it accepts, highest first. It's `Codable`, so
an app can store the level a person picked.

The type stays the same when the provider changes the model's levels: a level the model gains adds a member, and a
level it stops accepting stays, marked `deprecated`. A request that names such a level moves it to the nearest one
the model accepts.

A type of your own can be an effort type too: conform an enum that lists a set of levels to ``ModelEffort``.

### What a request sends

Each provider module says what a level becomes in its requests, which models always reason, and what reasoning goes
back on later turns:

- [Reasoning with OpenRouter models](https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/reasoning)
- [Reasoning with OpenAI models](https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/reasoning)
- [Reasoning with OpenAI-compatible providers](https://ironsparrows.github.io/swift-language-models/documentation/openaicompatiblelanguagemodels/reasoning)

### Apple's guides

- [Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)
- [ContextOptions](https://developer.apple.com/documentation/foundationmodels/contextoptions)
