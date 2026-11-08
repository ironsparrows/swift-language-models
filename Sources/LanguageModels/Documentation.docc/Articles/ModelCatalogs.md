# Model catalogs

See where a provider module's models come from, and how they change from one release to the next.

## Overview

When a provider publishes a list of its models, its module ships that list as a catalog. Each model is a static
member of the module's details type, such as `OpenRouterModel.anthropicClaudeHaiku5_5`, with its context size,
parameters, data kinds and reasoning levels. Its levels form the model's effort type, so
``DetailedLanguageModel/reasoningLevel(_:)`` offers only those, as <doc:ReasoningLevels> describes.

A catalog holds what changes rarely about a model. What changes often, such as prices and the health of each host,
stays out of it: OpenRouter's module reads that from OpenRouter when you ask. A model that's newer than the catalog can
still be described by hand, with the initializer of the module's details type.

### How a catalog is made

The package's generator reads each provider's model list and writes three things:

- A snapshot of the list, in `Catalogs/` in the package's repository.
- Each provider module's static members, an effort type for each model, the words of its provider's API, such as
  parameter names, and for each model the provider stopped listing the day it left, which ``ModelDetails/removalDate``
  reads, in the module's `Generated/` folder.
- The named reasoning levels, such as `.xhigh`, which every provider module shares.

A bot in the repository runs the generator for every provider at once, and opens one pull request with the changes and
the release they need.

### How a model's member changes

| When the provider | The catalog | Code that names the model |
|---|---|---|
| Lists a new model | Adds its static member | Can use it |
| Announces the day it retires a model | Marks the member `deprecated`, with that day | Compiles, with a warning that names the day |
| Stops listing a model | Keeps the member, marked `deprecated` with the day, sets its ``ModelDetails/removalDate``, and leaves it out of the module's list of models and its lookup by id | Compiles, with a warning that names the day. A request that may reach the model logs an error and, in a debug build, shows a runtime warning |
| Lists a dropped model again | Makes the member current again | Compiles without the warning |
| Adds a reasoning level to a model | Adds a member to the model's effort type | Can use the level |
| Stops accepting a reasoning level of a model | Keeps the level's member on the model's effort type, marked `deprecated` with the day | Compiles, with a warning that names the day. A request moves the level to the nearest one the model accepts, logs it and, in a debug build, shows a runtime warning |
| Changes a model's limits, name, dates or parameters | Updates its data | Compiles unchanged |

Each model has an effort type of its own, ``Efforts/Of``, named after the model, such as
`Efforts.Of<OpenRouterCatalog.AnthropicClaudeHaiku5_5>`. So the type stays the same when the model's levels change,
and code that spells it keeps compiling.

The words of a provider's API follow the same rules: a new word is added, and a word the provider stops listing stays,
marked `deprecated`. A named reasoning level that no model uses any more stays too, marked `deprecated` without a
day, since every provider shares it. So a catalog never deletes a member on its own: code that names one still
compiles, with a warning, unless the build treats warnings as errors.

### Which release a change needs

A catalog follows its provider, which adds and stops listing models often, so a catalog change is a patch release
unless code that compiled may stop compiling:

- **Major:** a generated member is deleted, which only a maintainer does, for a major release.
- **Patch:** any other change to a catalog: members added, deprecated or made current again, a model that gains or
  stops accepting reasoning levels, or a model's limits, name, dates or parameters.
- **None:** only the shape of the provider's API changed, which changes no generated code.

Minor releases are for the package's own features, never for a catalog change.

Every provider module ships in one package, so one version covers every catalog: the release that one provider's
changes need is a release of the whole package. A major release waits for a maintainer to review it; any other
release ships once the bot's pull request passes the package's tests.

A major release raises the major version, such as from 1.4.2 to 2.0.0, which a dependency declared with `from:` doesn't
take until you choose to update. To take only patch releases, declare the dependency with `.upToNextMinor(from:)`.
