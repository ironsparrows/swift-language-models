# Authentication

Send requests with an API key, a key each person brings, or through a server of your own.

## Overview

``OpenRouterAuthentication`` says how a model's requests authenticate, and where they go:
``OpenRouterAuthentication/apiKey(_:)`` sends them to OpenRouter with a key,
``OpenRouterAuthentication/apiKey(baseURL:_:)`` sends them with a key to another server that speaks OpenRouter's API,
such as a gateway, and ``OpenRouterAuthentication/proxied(baseURL:headers:)`` sends them to your own server, which adds
the key.
<doc:/LanguageModels/KeepingAPIKeysOutOfTheApp>
compares the ways to ship without a key; this article covers what's particular to OpenRouter.

### Use an API key

``OpenRouterAuthentication/apiKey(_:)`` reads an API key for every request and never stores it. It suits
development, or a key each person brings and keeps in the Keychain. A Keychain read blocks, so do it away from the
main actor. A bundled key is extractable from a shipping app, so use one only during development:

@Snippet(path: "swift-language-models/Snippets/QuickStart", slice: "apiKey")

An empty key sends no `Authorization` header, and an error that the closure throws ends the request and passes through
as it is. A `URLError` passes through too, except that a timeout becomes `LanguageModelError.timeout` and a
cancellation `CancellationError`, as for a failed connection.

``OpenRouterAuthentication/apiKey(baseURL:_:)`` sends the key the same way to another server that speaks OpenRouter's
API, such as your company's gateway or a test server. Requests go to the same paths under its URL, such as
`chat/completions`, and follow redirects only to the same URL host. Model info calls go there too. The key is still in the
app, so to ship without one, send requests through your server instead.

### Let each person sign in

With OAuth PKCE, a person signs in to OpenRouter, and the app gets a key from their own account, which they control
and pay for:

1. Open `https://openrouter.ai/auth?callback_url=…&code_challenge=…&code_challenge_method=S256` with
   `ASWebAuthenticationSession`.
2. OpenRouter returns to the callback with a `code`, which works once, within 10 minutes.
3. `POST` it to `https://openrouter.ai/api/v1/auth/keys` as JSON, with `code`, `code_verifier` and
   `code_challenge_method`.
4. Keep the `key` it returns in the Keychain, for ``OpenRouterAuthentication/apiKey(_:)``.

OpenRouter's guide shows `https` and `localhost` callbacks, and doesn't mention custom URL schemes.

### Send requests through your server

``OpenRouterAuthentication/proxied(baseURL:headers:)`` sends each request to your server, which adds the key and
forwards it to OpenRouter. The headers let the server authorize the caller:

@Snippet(path: "swift-language-models/Snippets/QuickStart", slice: "proxy")

Requests go to the same paths under the server's URL, such as `chat/completions`, and follow redirects only to the
same URL host, so the headers never reach another one. The headers are read for every request, so a token can refresh,
and the package's own headers, such as `Content-Type`, take precedence over one of the same name. Model info calls,
such as ``OpenRouterLanguageModel/endpoints()``, go to the server too.

With the `AppToken` from
<doc:/LanguageModels/KeepingAPIKeysOutOfTheApp>,
the headers closure returns the current token, and a new one when it's about to expire:

@Snippet(path: "swift-language-models/Snippets/KeepingKeysOut", slice: "proxied")

That article's proxy, in Swift, Node.js or Python, takes these settings for OpenRouter:

| Setting | Value |
|---|---|
| `upstream` | `https://openrouter.ai/api/v1/` |
| `keyVariable` | `OPENROUTER_API_KEY` |
| `authHeader`, `authValue` | `Authorization`, `Bearer {key}` |
| `paths` | `chat/completions`, `models/*/*/endpoints`, `model/*/*` |
| `passHeaders` | The headers below |
| `fixedHeaders` | None |

The headers it passes:

- **To OpenRouter:** `HTTP-Referer`, `X-OpenRouter-Title`, `X-OpenRouter-Categories`, `X-OpenRouter-App-Visibility`,
  `X-OpenRouter-Metadata`, `X-OpenRouter-Cache`, `X-OpenRouter-Cache-TTL`, `X-OpenRouter-Cache-Clear` and
  `X-Session-Id`, which carries the session id while the response cache is on.
- **Back to the app:** `X-OpenRouter-Cache-Status`, `X-OpenRouter-Cache-Age`, `X-OpenRouter-Cache-Source-Id`,
  `Retry-After` and `X-RateLimit-Reset`.

The module sends `chat/completions` as a `POST`, whose answer streams as server-sent events, and the other two paths as
`GET`s.

### Give each person a key with a limit

With a management key, your server creates a key for each person with `POST https://openrouter.ai/api/v1/keys`, which
takes a `name` and a credit `limit` and returns the key. `PATCH https://openrouter.ai/api/v1/keys/{hash}` with
`limit_reset: "daily"` restores the limit each day at midnight UTC, and with `disabled: true` turns the key off. Your
proxy uses the person's key, or their app keeps it, so a leaked key spends at most its limit.

### OpenRouter's guides

- [Authentication](https://openrouter.ai/docs/api_reference/authentication)
- [OAuth PKCE](https://openrouter.ai/docs/guides/overview/auth/oauth)
- [Management API keys](https://openrouter.ai/docs/guides/overview/auth/management-api-keys)
