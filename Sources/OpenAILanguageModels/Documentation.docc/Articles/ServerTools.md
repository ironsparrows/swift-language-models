# Server tools

Let OpenAI search the web, generate images and search your files while the model answers.

## Overview

Server tools are tools that OpenAI runs for the model while it answers: a web search, an image generator and a file
search. The app implements nothing; the model calls them as it needs, and OpenAI hands each result back to the model
before it answers. A web search's answer lists the pages it cites on its response entry, as ``Citation`` values that
``OpenAIResponseMetadata/citations`` reads, and with `listsSources` every page it consulted, which
``OpenAIResponseMetadata/sources`` reads:

@Snippet(path: "swift-language-models/Snippets/OpenAIServerTools", slice: "search")

A citation has the page's ``Citation/url`` and ``Citation/title``, and the ``Citation/startOffset`` and
``Citation/endOffset`` of the text that cites it, counted in the answer's text. Show cited pages to the person as links
beside the answer. Without a ``OpenAIServerTool/Location``, OpenAI searches as if from the United States; a location
with no fields avoids that. GPT-5 doesn't search at its least reasoning, `minimal`.

### Generate images

An image generator draws images the model asks for. Each image is a data entry of its own in the transcript, a
`Transcript.DataEntry` of its format's kind, such as PNG, beside the answer's text, and
`Transcript.DataEntry.openAI` reads the prompt it was drawn from, as the model revised it:

@Snippet(path: "swift-language-models/Snippets/OpenAIServerTools", slice: "images")

The model sees an image on later turns, so it can change it: the image's call goes back by its id, and OpenAI looks the
image up. That needs OpenAI to keep the response that made the image and the request that sends it back, its default.
When OpenAI doesn't keep one of them, as with ``OpenAIOptions/Storage/notStored``, the call stays out of later turns
with the reasoning before it, so attach the image to a prompt to work on it. OpenAI keeps a response for a limited time, so a
saved transcript sends an old image's call that OpenAI may no longer have. Data entries need iOS,
macOS, visionOS or watchOS 27.2 and Xcode 27.2's SDK: anywhere else, a request with an image generator throws
`LanguageModelError.unsupportedCapability` before sending anything, since the image would be billed and couldn't arrive.

An image generator plans each image with the request's reasoning effort, unless its `complexity` says otherwise. GPT
Image 2 refuses a complexity of `low` or `medium`, and GPT Image 1 mini of `low`, which a light reasoning level passes
on: with them, a request at a light reasoning level fails with an ``OpenAIError`` whose code is `invalid_value`. Leave
the reasoning level at the model's default.

### Search your files

A file search looks through files the app added to OpenAI's vector stores beforehand, with OpenAI's API: upload the
files, add them to a vector store, and wait until it has indexed them. The answer lists the files it cites, which
``OpenAIResponseMetadata/fileCitations`` reads, each with the place in the answer's text where its citation goes:

@Snippet(path: "swift-language-models/Snippets/OpenAIServerTools", slice: "files")

### Use them with the session's tools

Server tools are sent after the session's own tools, and only when the model takes tools; otherwise a request throws
`LanguageModelError.unsupportedCapability` before sending anything. A tool-calling mode concerns only the session's
tools: `tool_choice` goes out only with them, so `.required` doesn't force a search. Only `.disallowed` reaches the
server tools, which it leaves out too. ``OpenAIOptions/maximumServerToolCalls`` caps the calls of every server tool in
one request; each round of the session's tool calls is a request of its own. <doc:ToolsAndGuidedGeneration> covers the
session's own tools, and <doc:Mapping> lists what each server tool sends.

Server tool calls never become tool calls in the transcript, so Apple's `ToolCallEvaluator` can't check them.
``OpenAIResponseMetadata/serverToolCalls`` lists what each one did: a web search's queries and the pages it opened, a
file search's queries, and an image's revised prompt. Each call that completed goes back on later turns right after
the reasoning before it, while the model still has its tool.

Each tool costs extra, on top of the model's tokens: a web search by the call, which
``OpenAIUsageMetadata/webSearchCount`` counts, an image by its model, size and quality, and a file search by the call
and the storage it searches.

### OpenAI's guides

- [Web search](https://developers.openai.com/api/docs/guides/tools-web-search)
- [Image generation](https://developers.openai.com/api/docs/guides/tools-image-generation)
- [File search](https://developers.openai.com/api/docs/guides/tools-file-search)
