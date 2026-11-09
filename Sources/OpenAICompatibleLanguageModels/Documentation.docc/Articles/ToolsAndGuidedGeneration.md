# Tools and guided generation

Call the session's tools and generate `Generable` values with models on any provider that speaks OpenAI's formats.

## Overview

Tools and guided generation are plain Foundation Models: a session takes `Tool` values, and `respond(to:generating:)`
returns a `Generable` type. This article covers what the module adds: what a model is taken to support, what a request
sends, what each provider refuses, and what happens to a call the session can't run.

### Say what a model takes

A model takes tools, guided generation and images unless its details say otherwise, which
``OpenAICompatibleModel/capabilities`` reports as `.toolCalling`, `.guidedGeneration` and `.vision`. DeepSeek's preset
leaves out guided generation, since DeepSeek takes no JSON Schema for an answer. For a model that takes less, name what
it takes in `capabilities:`, such as `[.toolCalling]`. Foundation Models checks a request against them before anything
is sent: a session with tools on a model without `.toolCalling`, or a guided request to a model without
`.guidedGeneration`, throws `LanguageModelError.unsupportedCapability`.

### Call tools and generate a value

A session can use tools and guided generation in the same request. The model calls tools first, the session runs them
and sends their outputs back, and the last answer is the `Generable` value:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleTools", slice: "feature")

- The session's tools go out as `function` tools, with each tool's name, description and argument schema.
- The calls of one answer form one tool-calls entry, so calls the model makes in parallel run as one round. Asked for
  two calls at once, Gemini made both in one answer, and Groq's `openai/gpt-oss-20b` made one in each of two rounds.
- A call whose arguments arrive as a JSON object, rather than as its text, is read as its text, and arguments of only
  whitespace as an empty object.
- Each tool's output goes back as a `tool` message in Chat Completions, or a `function_call_output` in Responses,
  matched to its call by its id.
- When the model reasoned before its calls, its reasoning goes back with them where its provider reads it, as
  <doc:Reasoning> describes. Gemini signs only the first of parallel calls, so the others go back without a signature,
  which Gemini takes.
- The facts a provider reports about a request that ends in tool calls, such as the model that answered, are on the
  tool-calls entry's first call, as <doc:ErrorsAndMetadata> describes.
- An answer cut off at its token limit inside a tool call throws ``OpenAICompatibleError`` with
  ``OpenAICompatibleError/Code/invalidResponse``, so no tool runs with partial arguments.

### Require a tool call

`toolCallingMode` becomes `tool_choice`: `auto` when tools are allowed, and `required` when the model must call one. It
goes out only with the session's tools, and when tool calls are disallowed, the request sends no tools at all. Some
providers can't be made to call a tool, so their presets refuse a request that requires one before it's sent, with
`LanguageModelError.unsupportedCapability`:

- Ollama ignores `tool_choice`, so its preset leaves it out and refuses every required call.
- DeepSeek takes a required call only with reasoning off, so its preset refuses one while the model reasons: set the
  reasoning level to ``FoundationModels/ContextOptions/ReasoningLevel/off``.

Others take the request, and may still answer without a call: on Groq, such an answer throws ``OpenAICompatibleError``
with the code `tool_use_failed`, and LM Studio is reported to make a required call only with its llama.cpp engine, and
to answer one empty there too.

### How the schema is sent

- A Chat Completions request sends the schema as `response_format`, of type `json_schema`, with `strict` set to `true`,
  and a Responses request as `text.format`. With `includeSchemaInPrompt`, which is Foundation Models' default, the
  schema also goes as text in the prompt that asked for it.
- The request sends the full schema first. When the provider rejects one of its constraints, with a 400 whose message
  names a constraint keyword, such as `minimum`, `maxItems` or `pattern`, and says it isn't supported, permitted or
  allowed, the request goes once more with the portable schema, whose constraints move into the descriptions.
- Whichever schema the request sent, the answer is checked against the full one, since a provider may ignore a guide.
  A value that breaks a guide throws `GeneratedContent.ParsingError`, which names the value and the guide, with a
  ``GuideViolations`` as its `underlyingError`.
- A guided answer cut off at its token limit throws `GeneratedContent.ParsingError`, since it would decode as a wrong
  value, and so does one Groq finds breaks its schema, with what the model generated as its raw content.
- A provider that ignores `response_format` answers as it likes: an object or array answer that isn't complete JSON
  throws `GeneratedContent.ParsingError` too.

### What each provider does with tools and a schema

- **Groq** refuses a schema in a request that also sends tools, so its preset refuses such a request before it's sent:

  @Snippet(path: "swift-language-models/Snippets/OpenAICompatibleTools", slice: "refused")

  Groq also fails some calls it can't read with ``OpenAICompatibleError`` and the code `tool_use_failed`:
  `qwen/qwen3.8-27b`'s calls failed that way in 2 of 9 runs of two tool rounds.
- **Gemini** takes both, and once answered with a call to the session's tool whose arguments held the schema's
  answer, so in a session with tools and a schema, a tool may be called with arguments it can't use.
- **Mistral** is reported to take only tool call ids of nine letters and digits, so a transcript whose calls another
  provider made may fail there.
- **vLLM** takes tools only from a server started with `--enable-auto-tool-choice` and a `--tool-call-parser`, and
  answers a request with tools from any other with a 400 naming the flags.
- **LM Studio** is reported to send some models' calls as `[TOOL_REQUEST]` text, which reaches the app as text.

<doc:Providers> says what each preset does in full.

### Calls the session can't run

A provider sends what its model wrote, and Foundation Models checks each call against the session's tools after the
answer ends. This was checked with a Chat Completions answer; Responses answers reach Foundation Models the same way,
but weren't checked. In each failing case below, the tool doesn't run, nothing goes back to the model, and `respond`
throws:

- A call to a tool the session doesn't have throws `GeneratedContent.ParsingError`, whose description names the
  generated tool and the session's tools. Its `rawContent` holds only the tool's name.
- Arguments that miss a required property, have `null` for one, or a value of another type, such as `"2"` for an `Int`,
  throw `LanguageModelSession.ToolCallError`, whose `underlyingError` is a `GeneratedContent.ParsingError`. It names a
  missing property, but for a value of another type only the type it wanted.
- An extra property doesn't stop the call: the tool runs, and the property goes back to the model with the call.
- Parallel calls start together, and one that fails cancels the rest, so a sibling's side effects happen only if it
  finishes first, and its output is lost. `respond` throws the failing call's error.

After such a failure, the transcript is what it was before the prompt, unless the session's
`transcriptErrorHandlingPolicy` is `.preserveTranscript`, which keeps the prompt and the tool-calls entry with the calls
as the model wrote them, and no tool output. `ToolCallError`'s description prints the tool value with every property it
stores, so a tool that stores a key or a person's data shows it there.

### Apple's guides

- [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
