# Logging

See what each request sends, leaves out and returns, and choose how much the package logs.

## Overview

The package logs each request to the unified logging system, under the subsystem
`com.ironsparrows.swift-language-models`, with a category for each provider module, such as `OpenRouter`, and
`LanguageModels` for what the core logs. Each message names its request by the first eight characters of the
request's id, so the messages of requests sent at once can be told apart.

| Level | Messages |
|---|---|
| Debug | What a request sends: the model, its fallbacks and the names of the options. Which model and host answered, the finish reason, whether the response cache served the answer, the time to the first token and the whole time. A cancelled request. A model-info call's path, status and time, and whether the info cache answered it |
| Info | What a request leaves out or changes from what the app asked for: options the models don't list, metadata that isn't a string or is past the provider's limits, settings the request doesn't send, either because the format has no member for them, such as a seed or top-k, or because the provider doesn't take them with the request's other settings, such as a temperature while a model reasons, a token limit raised to the fewest the provider takes, a reasoning level sent as another effort, and a response cache's time to live outside its range. A retry after a failed connection or a brief failure, such as a server error or an unavailable gateway, or with a portable schema after a host rejected a constraint |
| Error | A request that may reach a model its provider stopped listing, as its model or a fallback, and an answer that breaks its schema's guides, with where each value is and the guide it breaks, never the value, both in the `LanguageModels` category. A failed request or model-info call: the error it became, such as `LanguageModelError.rateLimited`, with the HTTP status, error code and host it came from |

The levels are Apple's `OSLogType` levels. The package logs at these three only, so `.default` logs what `.error`
does, and `.fault` logs nothing.

The system decides what it keeps, as it does for Apple's frameworks: debug messages only while a tool such as Xcode
or Console shows them, info messages in memory, and errors on disk, up to a limit. Messages are formatted only when
someone reads them, so logging costs little.

### What stays out of the log

The package never logs API keys, prompts, answers, tool arguments or outputs, or attachments, nor a host's error
message, which may quote the request. Model ids, host names, parameter names, HTTP statuses, error codes and timings
are public. The keys of metadata left out are private, so the system redacts them.

This covers the package's own logging. A recording with Instruments' Foundation Models template can include prompts
and responses, which Foundation Models records.

### Watch the messages

Filter Xcode's console by `subsystem:com.ironsparrows.swift-language-models`, or stream the messages in Terminal; for a
simulator, run the same command after `xcrun simctl spawn booted`:

```sh
log stream --level debug --predicate 'subsystem == "com.ironsparrows.swift-language-models"'
```

### Log less

Logging is on at every level. To log less, set ``LanguageModelsLogging/minimumLevel`` once, early, from any thread:

```swift
LanguageModelsLogging.minimumLevel = .error  // Only failed requests and removed models.
LanguageModelsLogging.minimumLevel = .fault  // Nothing.
```

### Runtime warnings

In a debug build, Xcode also shows a purple runtime warning for a likely mistake: a request that may reach a model its
provider stopped listing, a request that leaves out or changes something the app asked for, and a response cache's
time to live outside its range. Setting the level to `.fault` silences the warnings too; any other level leaves them on.
A release build never shows them.
