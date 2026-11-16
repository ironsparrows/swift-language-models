# Showcase

A tour of swift-language-models in the terminal, one command for each feature. Each command is a short file in
[`Showcase/Commands`](Showcase/Commands) that uses the package the way an app would, so the files read as examples;
[`Showcase/Terminal`](Showcase/Terminal) holds the printing.

| Command | What it shows |
|---|---|
| `chat [model-id]` | A chat with any catalog model, streamed, with `/model`, `/effort` and a footer of tokens, cache, cost and host |
| `tools [question]` | Two Foundation Models tools that the model calls, several in a round, with each call and round printed |
| `guided [destination]` | A `@Generable` trip plan that fills in as it streams |
| `reasoning [level] [question]` | DeepSeek's reasoning at the level you pick, dimmed, then its answer |
| `search [question]` | OpenRouter's web search as a server tool, with numbered citations |
| `fallbacks [prompt]` | Fallback models and routing, and which model and host answered |
| `caching` | Two turns on Claude: the prompt cache write, then a cheaper read |
| `attachments <path> [question]` | A question about an image, or a PDF through `FileAttachment` |
| `profiles` | A Dynamic Profile that switches models and reasoning levels mid-session |
| `compare` | The same booking requests on several models, and Apple's on-device model when it's available, with right answers, failures, time and cost |
| `catalog [capability] [words]` | The typed model catalog by capability, with context sizes and output limits, offline |
| `providers [model-id]` | The hosts that serve a model, live from OpenRouter, with their tier, prices, latency and uptime |

## Before you run it

Every command but `catalog` and `providers` calls a model, so it needs an API key: create one at
[openrouter.ai/keys](https://openrouter.ai/keys). The showcase reads it from the `OPENROUTER_API_KEY` environment
variable; in a terminal without it, the showcase asks for the key when it starts, with the typing hidden, and keeps it
in memory for that run. It never prints or stores the key. The commands use inexpensive models, such as Claude Haiku
5.5, GPT-5.4 Mini and Gemini 2.5 Flash Lite, and each answer's footer shows what it cost.

The project builds with Xcode 27.2 and runs on macOS 27. A PDF or another file that isn't an image needs macOS 27.2.

## Run it from Xcode

1. Open `Example/Example.xcodeproj`, and choose the **Showcase** scheme and **My Mac**.
2. Choose **Product > Scheme > Edit Scheme**, select **Run**, and on the **Arguments** tab add `OPENROUTER_API_KEY`
   under **Environment Variables**, with your key as its value. Leave the scheme unshared, so the key stays in
   `xcuserdata`, which git ignores.
3. Run. The console shows a menu: type a number or a name, and any arguments, such as `catalog vision`. Each command
   comes back to the menu, and Return quits. To run one command straight away, add it under
   **Arguments Passed On Launch**, such as `chat`.

The styles and the live trip plan need a terminal. Elsewhere, such as in Xcode's console or a pipe, the showcase
prints plain text, and the trip plan once it's complete.

## Run it from the terminal

From the repository's root, build the showcase and run the binary. It asks for the key, then shows the menu, which
each command comes back to until you press Return:

```sh
xcodebuild -project Example/Example.xcodeproj -scheme Showcase -destination 'platform=macOS' -derivedDataPath .build/showcase -quiet build
.build/showcase/Build/Products/Debug/Showcase
```

To skip the question, set `OPENROUTER_API_KEY` in the environment first.

Without a command, it shows the menu. Pass one to run it directly, or `help` to list them all:

```sh
.build/showcase/Build/Products/Debug/Showcase chat
.build/showcase/Build/Products/Debug/Showcase reasoning high "Is 1,001 prime?"
.build/showcase/Build/Products/Debug/Showcase catalog vision claude
```

Set `NO_COLOR` to turn the styles off.
