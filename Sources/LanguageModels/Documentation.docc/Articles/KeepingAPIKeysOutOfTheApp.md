# Keeping API keys out of the app

Call a provider's models from an app you ship, without shipping the provider's key.

## Overview

A provider's API key pays for every request made with it. Anything an app holds, the person who has the app can read:

- strings in the binary, which `strings` lists;
- `Info.plist`, and the `xcconfig` values a build copies into it;
- obfuscated strings, which the app decodes before it sends them;
- a key the app fetches at launch, such as from CloudKit or a remote config service, which then sits in the app's
  memory and in its network traffic.

Obfuscation only slows extraction. A key that leaks spends your money on anyone's requests until you revoke it, and a
key built into an app can't be changed without shipping a new version.

So the key stays on your Mac during development, and in a shipping app it belongs to the person who uses it, or stays
on a server of yours.

### Choose an approach

| Approach | Where the key lives | Who pays | Server |
|---|---|---|---|
| A development key | Your Mac, in an Xcode scheme | You | None |
| A key each person brings | The person's Keychain | The person | None |
| Your own proxy | Your server's secrets | You | Yours |

With a proxy, the app also proves to your server that the request comes from it, and who sends it, as
<doc:KeepingAPIKeysOutOfTheApp#Prove-the-request-comes-from-your-app> describes.

### During development

Put the key in the scheme's environment: in Xcode, choose Product > Scheme > Edit Scheme, then Run > Arguments, and
add it under Environment Variables. The app reads it with `ProcessInfo.processInfo.environment`.

Xcode shares schemes by default, and a shared scheme goes into the repository with its key. In Product > Scheme >
Manage Schemes, clear the scheme's Shared checkbox: Xcode then keeps it in the project's `xcuserdata` folder, which the
usual Xcode `.gitignore` leaves out. Xcode sets the variables when it runs the app, so the app launched any other way,
and every build you ship, has no key.

Keep the key out of `xcconfig` files and `Info.plist`, which go into the app's bundle.

### Keep a secret on the device

The Keychain stores a secret encrypted, for your app alone. This helper saves, reads and deletes one:

@Snippet(path: "swift-language-models/Snippets/KeepingKeysOut", slice: "keychain")

A Keychain call blocks its thread, so the methods are `@concurrent` and run off the caller's actor. On a Mac,
`kSecUseDataProtectionKeychain` makes the item behave as it does on iOS; other platforms ignore it.

`kSecAttrAccessible` sets when the item can be read, and whether it leaves the device:

| Value | Readable | Leaves the device |
|---|---|---|
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | While the device is unlocked | No |
| `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | From the first unlock after a restart, while locked too | No |
| `kSecAttrAccessibleWhenUnlocked`, the default | While the device is unlocked | In a backup restored to another device |

An item whose value ends in `ThisDeviceOnly` restores only to the device it came from. The helper uses
`AfterFirstUnlockThisDeviceOnly`, so a request that runs while the device is locked, such as one from a background
task, still reads the key. Use `WhenUnlockedThisDeviceOnly` when every request starts in the foreground.

Other attributes widen who reads the item:

- **iCloud Keychain.** `kSecAttrSynchronizable` set to `true` syncs the item to the person's other devices, so a key
  they paste once works on each of them. It can't be combined with a `ThisDeviceOnly` value, and the query must set it
  too, or it finds no synced item. Updating or deleting the item changes every copy.
- **Access groups.** Apps and extensions from your team share an item through a keychain access group: turn on
  Keychain Sharing and set `kSecAttrAccessGroup`. A widget or an extension that sends requests needs one.

The Secure Enclave holds keys it creates, such as P-256 keys, and never lets them out. It can't hold a key you already
have, so it can't store an API key. It can wrap one: encrypt the key with a Secure Enclave P-256 key, using the
`eciesEncryptionCofactorX963SHA256AESGCM` algorithm, and keep the result in the Keychain. Only that device can decrypt
it, and an access control flag such as `userPresence` asks the person to authenticate first. The app still
decrypts the key into memory to send it.

Never keep a secret in source code, in a file or property list in the bundle, or in `UserDefaults`, which stores it
on disk unencrypted.

### Let each person bring a key

When each person brings a key, they pay for their own requests, and no key of yours ships.

- **A pasted key.** Ask for the key in a `SecureField`, save it with the helper, and let the person remove it. The
  provider module's key closure returns `read()`, so each request uses the current key.
- **The provider's sign-in.** Some providers let a person sign in on the provider's site and hand the app a key of
  their own. `ASWebAuthenticationSession` opens the sign-in page and returns the callback URL, which carries a one-time
  code. The app exchanges the code for the key, with the PKCE verifier it made for this sign-in, and keeps the key in
  the Keychain. The callback is a custom URL scheme, or an `https` URL on a domain associated with the app, through
  `ASWebAuthenticationSession.Callback.https(host:path:)`.

A provider module's article describes its provider's sign-in, when there is one.

### Run your own proxy

The app sends each request to your server, which checks the caller and forwards the request to the provider with the
key. The key never leaves the server, and you change it without an app update.

A proxy does the same for every provider:

- Check the caller, with a token your server issued, and drop the token.
- Forward only the paths the provider module calls, and answer 404 for the rest, so the key can't reach the provider's
  other endpoints, such as the ones that manage keys.
- Attach the provider's key in its auth header, and the provider's fixed headers.
- Pass the provider's other headers, both ways, and nothing else, so the app's cookies and tokens stay out of the
  provider's request.
- Stream the response through as it arrives. An answer comes as server-sent events, and a buffered response shows
  nothing until the model finishes.
- Stop the provider's request when the app disconnects, so a cancelled answer stops costing.
- Return the provider's redirects instead of following them, so the key goes nowhere else.
- Limit each person's requests.
- Optionally, read the request's JSON and refuse a model or an output limit you don't allow. The provider's API names
  these members.
- Never log request or response bodies, which hold prompts and answers. Log the person, the path, the status and the
  time.

Only the settings differ. Each provider module's article gives its provider's values:

| Setting | Holds |
|---|---|
| `upstream` | The provider's API base URL |
| `keyVariable` | The name of the environment variable that holds the key |
| `authHeader`, `authValue` | The header that carries the key, and its value, with `{key}` for the key |
| `paths` | The paths the proxy forwards, where `*` stands for one segment |
| `passHeaders` | The headers passed through, both ways, besides `Content-Type` and `Accept` |
| `fixedHeaders` | Headers added to every request |

Providers differ in their auth header: OpenAI-compatible APIs and OpenRouter take `Authorization: Bearer <key>`, and
Gemini's API takes `x-goog-api-key: <key>`. Anthropic's API needs an `anthropic-version` header with each request,
which is a fixed header.

Each top-level name in the settings file is a route prefix, so one server serves several providers, each under its own
prefix, such as `/openrouter/`. The app points each provider module at its prefix:

```json
{
    "example": {
        "upstream": "https://api.example.com/v1/",
        "keyVariable": "EXAMPLE_API_KEY",
        "authHeader": "Authorization",
        "authValue": "Bearer {key}",
        "paths": ["chat/completions", "models/*"],
        "passHeaders": ["Retry-After"],
        "fixedHeaders": {}
    }
}
```

These servers read the file named by `PROXY_CONFIG`, check an `X-App-Token` header, limit each person to
`REQUESTS_PER_MINUTE` requests, and listen on `PORT`:

@TabNavigator {
    @Tab("Swift") {
        Vapor 4. The target also depends on AsyncHTTPClient, whose `HTTPClientRequest` streams the answer:

        ```swift
        import AsyncHTTPClient
        import Vapor

        struct Provider: Decodable {
            let upstream: String
            let keyVariable: String
            let authHeader: String
            let authValue: String
            let paths: [String]
            let passHeaders: [String]
            let fixedHeaders: [String: String]
        }

        actor RateLimiter {
            let perMinute: Int
            private var recent: [String: [ContinuousClock.Instant]] = [:]  // In memory, so for one instance only.

            init(perMinute: Int) { self.perMinute = perMinute }

            func allow(_ user: String) -> Bool {
                let now = ContinuousClock.now
                let times = recent[user, default: []].filter { now - $0 < .seconds(60) }
                guard times.count < perMinute else { return false }
                recent[user] = times + [now]
                return true
            }
        }

        /// Checks a token your server issued: `user.expiry.signature`, signed with TOKEN_SECRET.
        func user(for token: String?, key: SymmetricKey) -> String? {
            let parts = (token ?? "").split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, let signature = Data(base64Encoded: String(parts[2])),
                let expiry = Double(parts[1]), expiry > Date().timeIntervalSince1970
            else { return nil }
            let signed = Data("\(parts[0]).\(parts[1])".utf8)
            let valid = HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: signed, using: key)
            return valid ? String(parts[0]) : nil
        }

        /// `*` stands for one path segment.
        func allowed(_ globs: [String], _ parts: [String]) -> Bool {
            guard !parts.contains(where: { $0.allSatisfy { $0 == "." } }) else { return false }
            return globs.contains { glob in
                let want = glob.split(separator: "/").map(String.init)
                return want.count == parts.count && zip(want, parts).allSatisfy { w, p in
                    w == "*" ? p.wholeMatch(of: /[A-Za-z0-9_.:~-]+/) != nil : w == p
                }
            }
        }

        let providers = try JSONDecoder().decode(
            [String: Provider].self,
            from: Data(contentsOf: URL(filePath: Environment.get("PROXY_CONFIG") ?? "providers.json"))
        )
        guard let tokenSecret = Environment.get("TOKEN_SECRET"), tokenSecret.utf8.count >= 32 else {
            fatalError("Set TOKEN_SECRET to at least 32 random bytes.")
        }
        let tokenKey = SymmetricKey(data: Data(tokenSecret.utf8))
        let limiter = RateLimiter(perMinute: Environment.get("REQUESTS_PER_MINUTE").flatMap(Int.init) ?? 20)

        func proxy(_ request: Request) async throws -> Response {
            let path = request.parameters.getCatchall()
            guard let provider = providers[request.parameters.get("provider") ?? ""], allowed(provider.paths, path)
            else { throw Abort(.notFound) }
            guard let user = user(for: request.headers.first(name: "X-App-Token"), key: tokenKey)
            else { throw Abort(.unauthorized) }
            guard await limiter.allow(user) else { throw Abort(.tooManyRequests) }

            let passed = Set(["content-type", "accept"] + provider.passHeaders.map { $0.lowercased() })
            let query = request.url.query.map { "?\($0)" } ?? ""
            var upstream = HTTPClientRequest(url: provider.upstream + path.joined(separator: "/") + query)
            upstream.method = request.method
            upstream.headers = HTTPHeaders(request.headers.filter { passed.contains($0.name.lowercased()) })
            upstream.headers.add(contentsOf: provider.fixedHeaders.map { ($0.key, $0.value) })
            let key = Environment.get(provider.keyVariable) ?? ""
            upstream.headers.replaceOrAdd(name: provider.authHeader, value: provider.authValue.replacing("{key}", with: key))
            if let body = request.body.data { upstream.body = .bytes(body) }

            let client = request.application.http.client.shared
            guard let response = try? await client.execute(upstream, timeout: .minutes(10))
            else { throw Abort(.badGateway) }
            return Response(
                status: response.status,
                headers: HTTPHeaders(response.headers.filter { passed.contains($0.name.lowercased()) }),
                body: .init(managedAsyncStream: { writer in
                    for try await chunk in response.body { try await writer.writeBuffer(chunk) }
                })
            )
        }

        let app = try await Application.make(.detect())
        app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080
        app.http.client.configuration.redirectConfiguration = .disallow
        for method in [HTTPMethod.GET, .POST] {
            app.on(method, ":provider", "**", body: .collect(maxSize: "20mb"), use: proxy)
        }
        try await app.execute()
        try await app.asyncShutdown()
        ```
    }

    @Tab("Node.js") {
        Express 5, with Node.js's `fetch`. Run it with `node server.js`:

        ```javascript
        import express from "express";
        import { createHmac, timingSafeEqual } from "node:crypto";
        import { readFileSync } from "node:fs";
        import { Readable, pipeline } from "node:stream";

        const providers = JSON.parse(readFileSync(process.env.PROXY_CONFIG ?? "providers.json", "utf8"));
        const perMinute = Number(process.env.REQUESTS_PER_MINUTE ?? 20);
        const recent = new Map(); // In memory, so for one instance only.
        const tokenSecret = process.env.TOKEN_SECRET ?? "";
        if (Buffer.byteLength(tokenSecret) < 32) throw new Error("Set TOKEN_SECRET to at least 32 random bytes.");

        // A token your server issued: `user.expiry.signature`, signed with TOKEN_SECRET.
        function userFor(token = "") {
            const parts = token.split(".");
            if (parts.length !== 3) return null;
            const [user, expiry, signature] = parts;
            const expected = createHmac("sha256", tokenSecret).update(`${user}.${expiry}`).digest();
            const given = Buffer.from(signature, "base64");
            const valid = given.length === expected.length && timingSafeEqual(given, expected);
            return valid && Number(expiry) > Date.now() / 1000 ? user : null;
        }

        function allow(user) {
            const now = Date.now();
            const times = (recent.get(user) ?? []).filter((time) => now - time < 60_000);
            if (times.length >= perMinute) return false;
            recent.set(user, [...times, now]);
            return true;
        }

        // `*` stands for one path segment.
        function allowed(globs, path) {
            const parts = path.split("/");
            if (parts.some((part) => /^\.*$/.test(part))) return false;
            return globs.some((glob) => {
                const want = glob.split("/");
                return want.length === parts.length
                    && want.every((w, i) => (w === "*" ? /^[\w.:~-]+$/.test(parts[i]) : w === parts[i]));
            });
        }

        const app = express();
        app.use(express.raw({ type: () => true, limit: "20mb" }));

        app.all("/:provider/*path", async (req, res) => {
            const provider = providers[req.params.provider];
            const path = req.params.path.join("/");
            if (!provider || !allowed(provider.paths, path)) return res.sendStatus(404);
            const user = userFor(req.get("x-app-token"));
            if (!user) return res.sendStatus(401);
            if (!allow(user)) return res.sendStatus(429);

            const passed = new Set(["content-type", "accept", ...provider.passHeaders.map((h) => h.toLowerCase())]);
            const headers = Object.fromEntries(Object.entries(req.headers).filter(([name]) => passed.has(name)));
            Object.assign(headers, provider.fixedHeaders);
            const key = process.env[provider.keyVariable];
            headers[provider.authHeader] = provider.authValue.replace("{key}", key);

            const url = req.originalUrl;
            const query = url.includes("?") ? url.slice(url.indexOf("?")) : "";
            const abort = new AbortController();
            res.on("close", () => abort.abort());
            try {
                const upstream = await fetch(new URL(path + query, provider.upstream), {
                    method: req.method, headers, body: req.body, redirect: "manual", signal: abort.signal,
                });
                res.status(upstream.status);
                for (const [name, value] of upstream.headers) if (passed.has(name)) res.setHeader(name, value);
                if (upstream.body) pipeline(Readable.fromWeb(upstream.body), res, () => {});
                else res.end();
            } catch {
                if (!res.headersSent) res.sendStatus(502);
            }
        });

        app.listen(Number(process.env.PORT ?? 8080));
        ```
    }

    @Tab("Python") {
        FastAPI with HTTPX. Run it with `uvicorn main:app`:

        ```python
        import base64, hmac, json, os, re, time
        from collections import defaultdict

        import httpx
        from fastapi import FastAPI, Request, Response
        from fastapi.responses import StreamingResponse

        providers = json.load(open(os.environ.get("PROXY_CONFIG", "providers.json")))
        per_minute = int(os.environ.get("REQUESTS_PER_MINUTE", "20"))
        recent = defaultdict(list)  # In memory, so for one instance only.
        token_secret = os.environ.get("TOKEN_SECRET", "").encode()
        if len(token_secret) < 32:
            raise RuntimeError("Set TOKEN_SECRET to at least 32 random bytes.")
        client = httpx.AsyncClient(timeout=httpx.Timeout(30, read=600))
        app = FastAPI()


        def user_for(token):
            """Checks a token your server issued: `user.expiry.signature`, signed with TOKEN_SECRET."""
            parts = (token or "").split(".")
            if len(parts) != 3:
                return None
            user, expiry, signature = parts
            expected = base64.b64encode(hmac.digest(token_secret, f"{user}.{expiry}".encode(), "sha256"))
            valid = hmac.compare_digest(signature.encode(), expected) and int(expiry) > time.time()
            return user if valid else None


        def allow(user):
            now = time.monotonic()
            recent[user] = [t for t in recent[user] if now - t < 60]
            if len(recent[user]) >= per_minute:
                return False
            recent[user].append(now)
            return True


        def allowed(globs, path):
            """`*` stands for one path segment."""
            parts = path.split("/")
            if any(part.strip(".") == "" for part in parts):
                return False

            def matches(glob):
                want = glob.split("/")
                return len(want) == len(parts) and all(
                    re.fullmatch(r"[\w.:~-]+", p, re.ASCII) if w == "*" else w == p for w, p in zip(want, parts)
                )

            return any(matches(glob) for glob in globs)


        @app.api_route("/{name}/{path:path}", methods=["GET", "POST"])
        async def proxy(name: str, path: str, request: Request):
            provider = providers.get(name)
            if not provider or not allowed(provider["paths"], path):
                return Response(status_code=404)
            user = user_for(request.headers.get("x-app-token"))
            if not user:
                return Response(status_code=401)
            if not allow(user):
                return Response(status_code=429)

            passed = {"content-type", "accept", *(h.lower() for h in provider["passHeaders"])}
            headers = {name: value for name, value in request.headers.items() if name in passed}
            headers.update(provider["fixedHeaders"])
            key = os.environ[provider["keyVariable"]]
            headers[provider["authHeader"]] = provider["authValue"].replace("{key}", key)

            upstream = client.build_request(
                request.method, provider["upstream"] + path,
                params=request.query_params, headers=headers, content=await request.body(),
            )
            try:
                response = await client.send(upstream, stream=True)
            except httpx.HTTPError:
                return Response(status_code=502)

            async def body():
                try:
                    async for chunk in response.aiter_bytes():
                        yield chunk
                finally:
                    await response.aclose()

            return StreamingResponse(
                body(),
                status_code=response.status_code,
                headers={name: value for name, value in response.headers.items() if name in passed},
            )
        ```
    }

}

The same steps fit other frameworks:

- **Swift:** Hummingbird.
- **Node.js:** Hono, which also runs on Cloudflare Workers, Bun and Deno; Fastify; and Firebase Cloud Functions, which
  serves an Express app with `onRequest(app)`.
- **Python:** Flask and Django.

Whichever runs the proxy, check that it streams responses instead of buffering them, and that its timeouts allow a
long answer. A reverse proxy in front may buffer too: nginx passes a response straight through when its location sets
`proxy_buffering off`, or when the response carries `X-Accel-Buffering: no`.

The rate limit lives in memory, so it holds for one instance. With several, keep the counts in a shared store, such as
Redis.

The server reads the provider's key, and `TOKEN_SECRET`, from its environment, set from your hosting platform's secrets
manager. Neither goes in the repository: the settings file names the key's variable, not the key. The server refuses to
start unless `TOKEN_SECRET` holds at least 32 random bytes, since a short or empty one lets anyone sign a token.

### Prove the request comes from your app

A proxy that forwards any request is the provider's API with your key, open to anyone. So the proxy checks two things
before it forwards: that the request comes from your app, on a real device, and who sends it.

- **App Attest.** The app creates a key in the Secure Enclave, and Apple attests that it belongs to your app on a
  genuine device. Your server checks the attestation once, keeps the key's public half, and then checks the assertions
  the app signs with it. Follow Apple's steps in
  [Validating apps that connect to your server](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server),
  or use a library that implements them. Check `DCAppAttestService.isSupported` first: it's `false` in most app
  extensions, and App Attest needs a device with a Secure Enclave, so test it on a device, not in the Simulator. During
  development, attestations come from Apple's sandbox, which keeps their keys apart from production's.
- **DeviceCheck.** `DCDevice` gives a token that your server sends to Apple, which authenticates the device and keeps
  two bits for it, such as whether it already had a free allowance.
- **Firebase App Check.** A managed service that runs App Attest, or DeviceCheck, for the app. The app sends its token
  in an `X-Firebase-AppCheck` header, and your proxy checks it with the Firebase Admin SDK, for Node.js, Python or Go,
  or as a JSON Web Token against Firebase's public keys, as
  [Verify App Check tokens from a custom backend](https://firebase.google.com/docs/app-check/custom-resource-backend)
  describes.
- **Sign in with Apple.** Attestation proves the app; sign-in tells you the person. Your server checks the identity
  token's signature, issuer, audience, expiry and nonce, as
  [Verifying a user](https://developer.apple.com/documentation/signinwithapple/verifying-a-user) describes. Any
  sign-in of your own works the same way.

After these checks, your server issues a short-lived token: the person, an expiry minutes or an hour away, and a
signature. The proxy checks the token on each request without calling Apple, and the app asks for a new one before it
expires. The servers above take `user.expiry.signature`, where the expiry is in Unix seconds and the signature is the
Base64 HMAC-SHA256 of `user.expiry` with `TOKEN_SECRET`; a JSON Web Token works too.

On the app's side, this actor attests a key once, keeps the key's id in the Keychain, and signs a challenge with it for
each new token. It posts to three routes of your server: `app-attest/challenge` returns a one-time `challenge`, and
`app-attest/attest` and `app-attest/assert` check the hash of that challenge and return a `token` and its `expiresIn`
seconds:

@Snippet(path: "swift-language-models/Snippets/KeepingKeysOut", slice: "appAttest")

Apple asks for a key for each account on a device, so an app with several accounts keeps a key id for each.

Some providers run attestation themselves and issue short-lived tokens, so the app needs no server of yours. A provider
module's article says when its provider does.

### Limit what a leaked key can do

- **A key for each person.** Some providers create keys through an API, each with its own spending limit. Your server
  creates one for each person, and disables it alone.
- **A spending cap.** Set a spending limit on the account or project, where the provider offers one.
- **Rotation.** Use separate keys for development and production. To rotate, add the new key to the server's secrets,
  restart it, and then revoke the old key. Rotate after any suspected leak.
- **Revocation.** Revoke a leaked key in the provider's console at once. Changing `TOKEN_SECRET` ends every token
  your server issued.

### How the package fits

Each provider module reads its key, or the headers for your proxy, from a closure that it calls for every request and
never stores what it returns. So the closure can read the Keychain, or return a token that `AppToken` refreshes before
it expires. Each provider module's article shows its authentication and its proxy's settings:

- [OpenRouter](https://ironsparrows.github.io/swift-language-models/documentation/openrouterlanguagemodels/authentication)
- [OpenAI](https://ironsparrows.github.io/swift-language-models/documentation/openailanguagemodels/authentication)
- [OpenAI-compatible providers](https://ironsparrows.github.io/swift-language-models/documentation/openaicompatiblelanguagemodels/gettingstarted#Keep-the-key-out-of-the-app)

### Apple's guides

- [Storing keys in the keychain](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain)
- [Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
- [Sharing access to keychain items among a collection of apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
- [Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)
- [Authenticating a user through a web service](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service)
- [Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)
- [Validating apps that connect to your server](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server)
- [Preparing to use the App Attest service](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service)
- [Assessing fraud risk](https://developer.apple.com/documentation/devicecheck/assessing-fraud-risk)
- [Accessing and modifying per-device data](https://developer.apple.com/documentation/devicecheck/accessing-and-modifying-per-device-data)
- [Verifying a user](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)
- [Customizing the build schemes for a project](https://developer.apple.com/documentation/xcode/customizing-the-build-schemes-for-a-project)
- [Mitigate fraud with App Attest and DeviceCheck](https://developer.apple.com/videos/play/wwdc2021/10244/), WWDC21
