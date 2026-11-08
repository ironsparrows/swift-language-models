# Server tools

Let OpenRouter search the web, fetch pages, tell the time and consult other models while the model answers.

## Overview

Server tools are tools that OpenRouter runs for the model while it answers: a web search, a web page fetch, the
current date and time, an advisor model to consult and a subagent model to hand tasks to. The app implements nothing;
the model calls them as it needs, and only its answer reaches the session. A web search's answer lists the pages it
cites on its response entry, as ``Citation`` values that ``OpenRouterResponseMetadata/citations`` reads:

@Snippet(path: "swift-language-models/Snippets/ServerTools", slice: "search")

A citation has the page's ``Citation/url`` and, when the search reported them, its
``Citation/title``, an ``Citation/excerpt`` of the page, and the ``Citation/startOffset``
and ``Citation/endOffset`` of the text that cites it. OpenRouter doesn't say what unit those offsets count, so
check that they fall within the answer's text before using them.

### Consult other models

An advisor is a model that the model asks for advice while it answers, and a subagent is a model that it hands
self-contained tasks to, with server tools of its own:

@Snippet(path: "swift-language-models/Snippets/ServerTools", slice: "models")

Each call is a request to the other model. Chat Completions returns neither the model's request nor the other model's
answer, so an advisor can't recall earlier consultations.

### Choose the engine and the sites

The engine decides who sees what the model searches for and fetches. By default the host's own search or fetch runs
when the model's host has one, and Exa otherwise; `engine` picks another, such as
``OpenRouterWebSearchEngine/perplexity`` or OpenRouter's own fetcher, ``OpenRouterWebFetchEngine/openRouter``. A search
also takes an ``OpenRouterWebSearchMode``, how deep Exa or Parallel searches; an ``OpenRouterSearchContextSize``, how
much of each page the model gets; a limit on results across all of an answer's searches; and the domains to search or
fetch from or never to use:

@Snippet(path: "swift-language-models/Snippets/ServerTools", slice: "options")

A web search sends its domains to leave out as OpenRouter's `excluded_domains`, and a web fetch as `blocked_domains`.
Most engines take either allowed or excluded domains, not both, and Google's own search takes neither.

Data retention depends on the engine. With zero data retention enforced on the account, OpenRouter rejects Firecrawl,
while Exa, Parallel, Perplexity and the hosts' own search keep what they're sent under their own policies.
``OpenRouterRouting/zeroDataRetention`` picks the hosts of the model, not the engines.

### Use them with the session's tools

Server tools are sent after the session's own tools, and only when the model and every fallback take tools;
otherwise a request throws `LanguageModelError.unsupportedCapability` before sending anything. They count as tools,
so a request with them asks for hosts that honor every parameter, unless ``OpenRouterRouting/parameterSupport``
says otherwise. <doc:ToolsAndGuidedGeneration> covers the session's own tools, and <doc:Mapping> lists what each
server tool sends.

A tool-calling mode concerns only the session's tools: `tool_choice` goes out only with them. Only `.disallowed`
reaches the server tools, which it leaves out too.

OpenRouter's record of a server-tool call, when it sends one, is part of the answer's reasoning details, and goes back
on later turns with them unless a fallback wrote the answer. Server-tool calls never become tool calls in the
transcript, so Apple's `ToolCallEvaluator` can't check them, as
<doc:JudgingAndGeneratingSamples#Check-tool-calls> describes.

Searches, fetches and calls to other models cost extra, as <doc:ChoosingAModel#What-a-request-costs> describes.

### OpenRouter's guides

- [Server Tools](https://openrouter.ai/docs/guides/features/server-tools)
- [Web Search](https://openrouter.ai/docs/guides/features/server-tools/web-search)
- [Web Fetch](https://openrouter.ai/docs/guides/features/server-tools/web-fetch)
- [Advisor](https://openrouter.ai/docs/guides/features/server-tools/advisor)
- [Subagent](https://openrouter.ai/docs/guides/features/server-tools/subagent)
