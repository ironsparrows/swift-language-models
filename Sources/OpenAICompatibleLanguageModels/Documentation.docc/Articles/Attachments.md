# Attachments

Send images, and from OS 27.2 PDFs, audio and text, with a prompt, and reach a server on your own network.

## Overview

Prompts and tool outputs carry images, and from OS 27.2 data attachments too. A label goes before its attachment as
text, so the model can name it, as an `ImageReference` does:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleAttachments", slice: "image")

An image goes as a JPEG drawn upright from its orientation, on white, and scaled down so that its longer side is at most
2,048 pixels, as a data URL in an `image_url` part in Chat Completions, or an `input_image` in Responses. The model's
``OpenAICompatibleConfiguration/images`` change that side and the JPEG quality. Only its pixels leave the device, never
metadata such as where a photo was taken. Every image sent as data goes as JPEG, so a provider that takes only some
kinds of images, such as Ollama, which takes JPEG, PNG and WebP, takes it.

### Images at a web address

An image at an http or https address goes as that address, for the provider to fetch, when it's upright; one at
another kind of address, or that isn't upright, throws `LanguageModelError.unsupportedTranscriptContent`. Foundation
Models reads the image itself first, before the request is built, so the address must be readable from the device too,
even where the provider fetches it: an image Foundation Models can't load throws
`LanguageModelError.unsupportedTranscriptContent` before anything is sent.

- Gemini fetched an image at a web address.
- Ollama answers one with a 400, so its preset refuses it before it's sent, with
  `LanguageModelError.unsupportedTranscriptContent`: attach the image itself.
- vLLM's server fetches it, and waits up to 5 seconds for one by default.

### Say what a model takes

A model takes images unless its details say otherwise, and no other kind of data. Name the kinds it takes in
`attachments:`, as `UTType` values, and `supportsDataAttachmentType(_:)` says whether it takes one:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleAttachments", slice: "kinds")

When the model doesn't take an attachment, a request throws before sending anything:
`LanguageModelError.unsupportedCapability` with `.vision` for an image attachment to a model without `.vision`, and
`LanguageModelError.unsupportedTranscriptContent` for a data attachment of a kind it doesn't list, an image file
included. Instructions take only text, so an attachment there throws `unsupportedTranscriptContent` too.

### Attach files

Data attachments need Xcode 27.2 at build time, since earlier SDKs lack them. ``FileAttachment``, from the
`LanguageModels` module, reads a file and tells its type from its extension, or wraps bytes of a type you name:

@Snippet(path: "swift-language-models/Snippets/OpenAICompatibleAttachments", slice: "file")

| Kind | Chat Completions | Responses |
|---|---|---|
| An image file, such as a PNG or HEIC file | An `image_url` part, as for an image attachment | An `input_image`, as for an image attachment |
| A PDF | A `file` part with `filename`, the label ending in `.pdf` or `document.pdf`, and `file_data`, a data URL | An `input_file` with `filename` and `file_data`, the same way |
| WAV and MP3 audio | An `input_audio` part with `data` and `format` | `LanguageModelError.unsupportedTranscriptContent`, before anything is sent |
| Plain text | A text part | Text |
| Other audio, and video | `LanguageModelError.unsupportedTranscriptContent`, before anything is sent | The same |

Which presets' providers read a `file` part or `input_audio`, and for which models, wasn't checked: list a kind in a
model's `attachments:` only when its provider documents it. Each request sends the whole transcript, so a prompt's
attachment goes again with every later request of the session. An answer's attachments stay in the transcript but
aren't sent back.

### Reach a server on your own network

A server on the same Mac, such as Ollama at `http://localhost:11434/v1/`, takes requests from an app running there, and
from an app in the iOS Simulator, which reaches the Mac at `localhost`. A device reaches it at the Mac's address on the
network, such as `http://192.168.1.20:11434/v1/`, through ``OpenAICompatibleProvider/at(_:)``, once the server
listens on that network and not only on `localhost`, which its documentation says how to set.

App Transport Security, which allows only HTTPS by default, allows plain HTTP to unqualified names such as `localhost`
and to `.local` names. From iOS 17, iPadOS 17 and macOS 14, it no longer allows it to an IP address unless the app's
`Info.plist` says so, such as with `NSAllowsLocalNetworking`, under `NSAppTransportSecurity`, set to `YES`. Whether iOS
also asks the person for access to the local network wasn't checked.

### Apple's guides

- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Attachment](https://developer.apple.com/documentation/foundationmodels/attachment),
  [ImageReference](https://developer.apple.com/documentation/foundationmodels/imagereference) and
  [DataAttachmentRepresentable](https://developer.apple.com/documentation/foundationmodels/dataattachmentrepresentable)
- [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
