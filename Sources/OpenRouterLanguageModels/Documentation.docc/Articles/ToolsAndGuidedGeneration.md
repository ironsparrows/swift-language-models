# Tools and guided generation

Call the session's tools and generate `Generable` values with OpenRouter models.

## Overview

Tools and guided generation are plain Foundation Models: a session takes `Tool` values, and `respond(to:generating:)`
returns a `Generable` type. This article covers what OpenRouter models add: which models take them, what a request
sends, and what comes back.

### Check what a model takes

A model calls tools when it lists `tools`, and generates `Generable` values when it lists `structured_outputs`, so its
host holds the answer to the schema. With fallbacks, every model must list them, since any of them may answer:

@Snippet(path: "swift-language-models/Snippets/ToolsAndGuidedGeneration", slice: "capabilities")

Foundation Models checks a request against ``OpenRouterLanguageModel/capabilities`` before anything is sent: a session
with tools on a model without `.toolCalling`, or a guided request to a model without `.guidedGeneration`, throws
`LanguageModelError.unsupportedCapability`.

### Call tools and generate a value

A session can use tools and guided generation in the same request. The model calls tools first, the session runs them
and sends their outputs back, and the last answer is the `Generable` value:

@Snippet(path: "swift-language-models/Snippets/ToolsAndGuidedGeneration", slice: "feature")

- The session's tools go out as `function` tools, with each tool's name, description and argument schema.
- The calls of one answer form one tool-calls entry, so calls the model makes in parallel run as one round.
  ``OpenRouterOptions/parallelToolCalls`` allows or stops parallel calls; by default the host decides.
- The facts OpenRouter reports about a request that ends in tool calls, such as the model that answered, are on the
  tool-calls entry's `openRouter`, as <doc:ErrorsAndMetadata> describes.
- An answer cut off at its token limit inside a tool call throws ``OpenRouterError`` with
  ``OpenRouterError/Code/invalidResponse``, so no tool runs with partial arguments.
- With tools, server tools or a response schema, a request asks OpenRouter for hosts that honor every parameter it
  sends, so a host that would ignore the tools or the schema isn't used, unless
  ``OpenRouterRouting/parameterSupport`` says otherwise.

### Require a tool call

`toolCallingMode` becomes `tool_choice`: `auto` when tools are allowed, and `required` when the model must call one.
Only `tool_choice` makes a model call a tool, so a required mode throws `LanguageModelError.unsupportedCapability`
before sending anything when the model or a fallback doesn't list it:

@Snippet(path: "swift-language-models/Snippets/ToolsAndGuidedGeneration", slice: "required")

Server tools, such as a web search, run next to the session's tools, and a required mode doesn't force a call to one,
as <doc:ServerTools> describes.

### How the schema is sent

- The request sends the schema as a strict `json_schema` response format, and the host holds the answer to it.
- A model with only JSON mode, `response_format`, has no `.guidedGeneration`, since its host doesn't hold the answer
  to the schema, so Foundation Models refuses the request before it's sent.
- An answer that still doesn't match the schema, such as one cut off at its token limit, throws Foundation Models'
  `GeneratedContent.ParsingError`.
- A request that may reach an Anthropic model, whose structured outputs reject constraints, as the model or a
  fallback, sends the portable schema: constraints that some hosts reject, such as `minimum`, `maxItems` and
  `pattern`, move into the description, which every host takes. In the example, `.range(5...120)` becomes part of the
  `minutes` description.
- Any other request sends the full schema. When the host rejects one of its constraints, with a 400 that names it, the
  request goes once more with the portable schema.
- Whichever schema the request sent, the answer is checked against the full one, since a host may drop or ignore a
  constraint. A value that breaks a guide, such as a `minutes` of 2 in the example, throws
  `GeneratedContent.ParsingError`, which names the value and the guide. Its `underlyingError` is a ``GuideViolations``
  that lists each value with its path, keyword and limit, so an app can clamp a number or cut a list short instead of
  asking again. A streamed response is checked once it ends, so its snapshots may show such a value before the stream
  throws.

<doc:Mapping#Requests> lists each of these in full.

### Apple's guides

- [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)

### OpenRouter's guides

- [Client Tools](https://openrouter.ai/docs/guides/features/tool-calling)
- [Structured Outputs](https://openrouter.ai/docs/guides/features/structured-outputs)
