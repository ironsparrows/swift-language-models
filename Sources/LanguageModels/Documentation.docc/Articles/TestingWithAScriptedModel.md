# Testing with a scripted model

Test a feature offline, with a model that gives the same answers on every run.

## Overview

A unit test of a model feature needs answers it can predict. A model of the test's own, whose executor replays a
script of text, tool calls and usage, drives a real `LanguageModelSession` with no network, API key or Apple
Intelligence. The session does what it does with any model: it checks the model's capabilities, runs tools, parses
guided generation and keeps the transcript, so the test exercises the app's code around the model. Apple's
[Foundation Models utilities](https://github.com/apple/foundation-models-utilities) test their own code with a model
like this.

The model belongs in the app's test target. It conforms to Foundation Models' `LanguageModel` directly, with an
executor of its own that reads a script. A provider module's model instead conforms to ``DetailedLanguageModel``,
with an executor that makes the protocol's two checks, as <doc:WritingAProvider> describes.

### Write the model

Each turn of the script is text, a tool call or an error. The model also lists its capabilities, the token counts it
reports, and a log of the requests it receives:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "model")

Foundation Models creates the executor from the model's `executorConfiguration`, and passes the model to each call, so
the executor reads the script from the model. It sends text with `appendText`, a tool call with
`toolCall(id:name:action:)`, and the usage after each, and throws a scripted error as it is:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "executor")

The executor picks a turn by counting the tool calls and answers since the transcript's last prompt. After a tool call,
the session runs the tool and asks the model again, which takes the next turn, and each new prompt starts the script
from its first turn. Tool calls take their ids from their turns rather than random ones, so they're the same on
every run.

### Inject the model

The feature takes its model as `some LanguageModel`, so the app passes the model it ships with, such as an
`OpenRouterLanguageModel`, and a test passes a scripted one. Nothing else in the feature changes:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "feature")

### Script the answers

For guided generation, the scripted text is the JSON that the schema asks for, and the session parses it into the
`Generable` type as it parses a provider module's answer:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "text")

For a `Generable` enum, the scripted text is the case's name alone, without quotes.

A tool call comes first, then the answer. The session decodes the scripted arguments, calls the tool, adds its output
to the transcript and asks the model again:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "tools")

The response's `usage` holds the counts of its last turn, and the session's `usage` adds up every turn, both here.

### Test the unhappy path

An error the executor throws reaches the caller as it is, so a script can throw what a provider module throws, such as
`LanguageModelError.rateLimited` or `LanguageModelError.guardrailViolation`, and a test checks what the app shows for
it. An error of another type, such as a provider module's own, passes through the same way:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "errors")

### Leave capabilities out

Foundation Models checks a request against the model's capabilities before the executor runs. A guided-generation
request to a model without `.guidedGeneration`, or a session with tools on a model without `.toolCalling`, throws
`LanguageModelError.unsupportedCapability`, so a test of what the app does on a less capable model needs no code of
its own in the executor:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "capabilities")

A plain-text request works with no capabilities at all.

### Check what the model received

The log keeps every `LanguageModelExecutorGenerationRequest`: the transcript so far, the tools the session enables,
the schema and the generation options. A test reads it to check the instructions, the tools, or what a tool sent back:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "requests")

### Test an evaluation

An evaluation is code too, and a scripted model tests it offline, before a live run costs anything. The evaluation
takes its model and its judge as `any LanguageModel`, as <doc:EvaluatingAcrossModels> describes:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "evaluation")

A scripted subject checks the evaluators' logic, such as a slow dinner failing `Quick`, and a scripted judge gives the
same score every time. The judge sends a guided-generation request. In the 27.2 SDK, its schema asks for the metric's
name followed by `_value`, which is `"1"` or `"0"` on a pass-fail scale, and by `_rationale`. Apple doesn't document
this shape, so it can change with the SDK; the scripted judge's `requests` log shows the schema it received:

@Snippet(path: "swift-language-models/Snippets/ScriptedModel", slice: "judge")

`result.errors == .clean` catches a judge that fails. A reply that doesn't decode counts as an evaluator failure, and
the judge's metric goes missing from the summary, where `aggregateValue(_:)` returns `-1`.

A judge model without `.guidedGeneration` gets no schema. Its prompt asks instead for a JSON object in its text, such
as `{"ratings": [{"name": "Warm", "value": 1, "rationale": "…"}]}`, and the judge scores only when the model writes
exactly that. Guided generation is what makes a judge reliable.

### Apple's guides

- [Running a Core AI model in a Foundation Models session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session),
  which conforms a model of your own to `LanguageModel`
- [LanguageModel](https://developer.apple.com/documentation/foundationmodels/languagemodel)
- [LanguageModelExecutor](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutor)
- [LanguageModelExecutorGenerationChannel](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationchannel)
- [LanguageModelExecutorGenerationRequest](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutorgenerationrequest)
- [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)
- [Scoring with model-judge evaluators](https://developer.apple.com/documentation/evaluations/scoring-with-model-as-judge-evaluators)
