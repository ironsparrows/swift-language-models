# Authentication

Send requests with an API key, a key each person brings, or through a server of your own.

## Overview

``OpenAIAuthentication`` says how a model's requests authenticate, and where they go:
``OpenAIAuthentication/apiKey(organization:project:_:)`` sends them to OpenAI with a key,
``OpenAIAuthentication/apiKey(baseURL:organization:project:_:)`` sends them with a key to another server that speaks
OpenAI's API, such as a gateway, and ``OpenAIAuthentication/proxied(baseURL:headers:)`` sends them to your own server,
which adds the key. <doc:/LanguageModels/KeepingAPIKeysOutOfTheApp> compares the ways to ship without a key; this
article covers what's particular to OpenAI.

### Use an API key

``OpenAIAuthentication/apiKey(organization:project:_:)`` reads an API key for every request and never stores it, and
sends it as a bearer token in `Authorization`. It suits development, or a key each person brings and keeps in the
Keychain. A Keychain read blocks, so do it away from the main actor. A bundled key is extractable from a shipping app,
so use one only during development:

@Snippet(path: "swift-language-models/Snippets/OpenAIAuthentication", slice: "key")

An empty key sends no headers at all: no `Authorization`, and no organization or project either. An error that the
closure throws ends the request and passes through as it is. A `URLError` passes through too, except that a timeout
becomes `LanguageModelError.timeout` and a cancellation `CancellationError`, as for a failed connection.

### Name the organization and project

`organization` goes out as `OpenAI-Organization` and `project` as `OpenAI-Project`, so the requests count toward them.
Leave either `nil` for the key's default:

@Snippet(path: "swift-language-models/Snippets/OpenAIAuthentication", slice: "organization")

### Send the key to another server

``OpenAIAuthentication/apiKey(baseURL:organization:project:_:)`` sends the key the same way to another server that
speaks OpenAI's API, such as your company's gateway or a test server. Its URL stands in for
`https://api.openai.com/v1/`: requests go to the same path under it, `responses`, and follow redirects only to the
same scheme, URL host and port. The key is still in the app, so to ship without one, send requests through your server
instead.

### Send requests through your server

``OpenAIAuthentication/proxied(baseURL:headers:)`` sends each request to your server, which adds the key and forwards
it to OpenAI. The headers let the server authorize the caller:

@Snippet(path: "swift-language-models/Snippets/OpenAIAuthentication", slice: "proxy")

Requests go to the same path under the server's URL, `responses`, and follow redirects only to the same scheme, URL
host and port, so the headers never reach another server. The headers are read for every request, so a token can
refresh, and the package's own headers, `Content-Type`, `Accept` and `User-Agent`, take precedence over one of the same
name. Return `[:]` when the server needs none.

The proxy in <doc:/LanguageModels/KeepingAPIKeysOutOfTheApp>, in Swift, Node.js or Python, takes these settings for
OpenAI:

| Setting | Value |
|---|---|
| `upstream` | `https://api.openai.com/v1/` |
| `keyVariable` | `OPENAI_API_KEY` |
| `authHeader`, `authValue` | `Authorization`, `Bearer {key}` |
| `paths` | `responses` |
| `passHeaders` | The headers below |
| `fixedHeaders` | `OpenAI-Organization` and `OpenAI-Project`, to count the requests toward an organization and project other than the key's defaults; otherwise none |

The headers it passes back to the app, which the module reads: `x-request-id`, `retry-after-ms`, `Retry-After`,
`x-should-retry`, `x-ratelimit-reset-requests` and `x-ratelimit-reset-tokens`. The app sends no headers of OpenAI's
through a proxy.

The module sends `responses` as a `POST`, whose answer streams as server-sent events. It makes no other calls.

### OpenAI's guides

- [Authentication](https://developers.openai.com/api/reference/overview#authentication), on API keys, organizations
  and projects
- [Production best practices](https://developers.openai.com/api/docs/guides/production-best-practices)
