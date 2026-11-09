# Caching

Help a provider's prompt cache serve the start of a prompt, group requests with a cache key, and see what the cache
read.

## Overview

Many providers keep the start of a prompt they've read, so a later request that starts the same way reads that part
from their cache, faster and often for less. Each request sends the whole transcript, so every turn of a session starts
the way the turn before it did. Every part of a request is written the same way each time, in the same order, from the
model and the instructions to the transcript's earlier turns and the settings, so each Chat Completions request of a
session repeats the one before it byte for byte up to its new turn. The module sends no cache marks: a provider caches
on its own, and some, such as Gemini, Groq and Mistral, document a minimum length for the start of a prompt they cache,
so a short prompt reads nothing from the cache there.

Apple's
[Optimizing key-value caching in language model sessions](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions)
still applies: a transcript that keeps its start unchanged keeps the cache valid.

### See what the cache did

The cache needs no code, and the answer's usage says what it did: the input tokens, and the ones read from the cache
in `input.cachedTokenCount`:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleCaching", slice: "usage")

The usage reads cached tokens from `prompt_tokens_details.cached_tokens` in Chat Completions, and from
`input_tokens_details.cached_tokens` in Responses. A provider that reports them in another member, such as a
`cached_tokens` beside the other counts, or not at all, reads as 0, so a 0 means the provider reported no cache hit
where the module reads it, not that its cache was missed.

A session's first request has read little or nothing from the cache, since no request before it started the same
way.

### Group requests with a cache key

``OpenAICompatibleOptions/cacheKey`` groups requests whose prompts start the same, so a provider that routes on it
serves their shared start from the same cache more often. It goes out as `prompt_cache_key`, and it's `nil` unless the
model is created with one:

- ``OpenAICompatibleOptions/CacheKey/session`` gives each session its own key: the id of its first prompt, which stays
  the same for the whole session.
- ``OpenAICompatibleOptions/CacheKey/named(_:)`` gives a key of the app's own, such as one for every session that
  shares the same long instructions.

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleCaching", slice: "cacheKey")

The key goes to xAI and Mistral, whose documentation ties their caches to it, and to a provider you describe, which
may refuse it as a member it doesn't know. The other presets leave it out and log it, since their providers refuse it,
ignore it or don't document it: Gemini and Groq answer `prompt_cache_key` with a 400. A key of your own can still go to
any provider as `prompt_cache_key` in ``OpenAICompatibleOptions/additionalMembers``.

### What each provider caches

| Provider | Caches on its own | Cache key | Cached tokens read |
|---|---|---|---|
| Gemini | Yes, seen | Left out | Seen, on the answer's last chunk |
| Groq | Documented for some models, not seen | Left out | None seen |
| DeepSeek | Documented | Left out | Documented, not seen |
| Mistral | Not documented without a key | Sent | Documented in `prompt_tokens_details`, not seen |
| xAI | Documented | Sent | Documented, not seen |
| Ollama | Yes, seen, while the model stays loaded | Left out | Seen on Ollama 0.40.15 |
| LM Studio | Reported | Left out | None: reported to send no cached tokens in this format |
| vLLM | By default, from its source | Left out | Only from a server started with `--enable-prompt-tokens-details` |

- **Gemini.** After the same instructions of about 6,000 tokens, a second request to `gemini-3.1-flash-lite` read 2,033
  of its 6,030 input tokens from the cache, and the first reported none. Gemini reports cached tokens only on a hit.
- **Groq.** Groq's documentation says `openai/gpt-oss-20b` and `openai/gpt-oss-120b` cache a repeated prefix, but on the
  free plan neither reported any cached tokens for a prompt of about 3,000 tokens sent again seconds later, streamed or
  not.
- **DeepSeek** documents its cache hits as `prompt_cache_hit_tokens` and as `prompt_tokens_details.cached_tokens`,
  which the usage reads.
- **Mistral** documents cached tokens in `prompt_tokens_details.cached_tokens`, which the usage reads. Ones it sends only
  as `num_cached_tokens` or in `prompt_token_details`, as it's reported to, read as 0.
- **xAI** documents that it routes requests that share a `prompt_cache_key` to the same cache, and reports cached
  tokens in `input_tokens_details.cached_tokens`. Its documentation names earlier reasoning left out of a request as
  the top cause of misses; its preset sends each answer's reasoning back as it came.
- **Ollama.** The loaded model reuses what it read of a repeated prefix until it's unloaded: after the same instructions
  of about 2,000 tokens, a second request read 2,020 of its 2,060 input tokens from the cache, on Ollama 0.40.15.
  Ollama's source added cached tokens to this format in September 2026, so an older server's read as 0.
- **vLLM** reports the tokens it writes to its cache as `created_cache_tokens`, which aren't read.

Gemini's, Groq's and Ollama's caching was checked on 9 November 2026; the others follow their documentation, what their
users report and, for vLLM, its server's source. ``OpenAICompatibleUsageMetadata/cacheWriteTokenCount`` reads the tokens
written to the cache where a provider reports them in `prompt_tokens_details.cache_write_tokens`, or in Responses
`input_tokens_details.cache_write_tokens`; Gemini, Groq and Ollama reported none.
