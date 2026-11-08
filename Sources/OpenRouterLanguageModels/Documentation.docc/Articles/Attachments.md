# Attachments and generated images

Send images, PDFs, audio, video and text with a prompt, and get images back.

## Overview

Prompts and tool outputs carry images, and from OS 27.2 data attachments too: PDFs, audio, video and text. A label
goes before its attachment as text, so the model can name it, as an `ImageReference` does:

@Snippet(path: "swift-language-models/Snippets/Attachments", slice: "image")

An image goes as a JPEG, drawn upright from its orientation, on white, and scaled down so that its longer side is at
most 2,048 pixels. The model's ``OpenRouterConfiguration/images`` change that side and the JPEG quality, such as to
1,024 pixels for fewer input tokens. Only its pixels leave the device, never metadata such as where a photo was taken.
An image at a web address goes as that address, when it's upright and its address is http or https; otherwise the
request throws `LanguageModelError.unsupportedTranscriptContent`.

### Attach files

Data attachments need Xcode 27.2 at build time, since earlier SDKs lack them. ``FileAttachment``, from the
`LanguageModels` module, reads a file and tells its type from its extension, or wraps bytes of a type you name:

@Snippet(path: "swift-language-models/Snippets/Attachments", slice: "file")

``FileAttachment/init(contentsOf:)`` throws ``FileAttachment/UnknownTypeError`` for a file whose extension names no type
the system knows, such as one without an extension; pass the type yourself with ``FileAttachment/init(_:type:)``.

- An image file, such as a PNG or HEIC file, goes as an image attachment does.
- A PDF goes as a file. A model that reads PDFs gets it as it is; for any other model OpenRouter reads it first, unless
  ``OpenRouterOptions/pdfEngine`` is ``OpenRouterOptions/PDFEngine/native``.
- Audio in WAV, MP3, AIFF, AAC, FLAC, Ogg or MPEG-4 goes with its format, video in MPEG-4, MPEG, QuickTime or WebM goes
  as data, and plain text goes as text.

`supportsDataAttachmentType(_:)` says whether the model and each of its fallbacks take a kind of data. When one of
them doesn't take an attachment, a request throws before sending anything, as Foundation Models does:
`LanguageModelError.unsupportedCapability` with `.vision` for an image attachment, and
`LanguageModelError.unsupportedTranscriptContent` for a data attachment, an image file included. Instructions become a
`system` message, which takes only text, so an attachment there throws `unsupportedTranscriptContent` too.
<doc:Mapping#Requests> lists the part each kind of attachment becomes.

### Get images back

A model that generates images, such as `.googleGemini2_5FlashImage`, is asked for images when every model of the
request generates them and the request has no response schema, and for text too when they all generate text. Each image
it generates becomes a data entry of its own, of the kind its data names, such as PNG:

@Snippet(path: "swift-language-models/Snippets/Attachments", slice: "images")

Generated images stay in the transcript but aren't sent back; to build on one, attach it to a later prompt. Data
entries need OS 27.2, and Xcode 27.2 at build time; without them, images aren't asked for.

Each request sends the whole transcript, so an attachment goes again with every later request of the session;
<doc:ChoosingAModel#What-a-request-costs> says what that costs.

### Apple's guides

- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Attachment](https://developer.apple.com/documentation/foundationmodels/attachment),
  [ImageReference](https://developer.apple.com/documentation/foundationmodels/imagereference) and
  [DataAttachmentRepresentable](https://developer.apple.com/documentation/foundationmodels/dataattachmentrepresentable)

### OpenRouter's guides

- [PDF Inputs](https://openrouter.ai/docs/guides/overview/multimodal/pdfs)
- [Audio](https://openrouter.ai/docs/guides/overview/multimodal/audio)
- [Video Inputs](https://openrouter.ai/docs/guides/overview/multimodal/videos)
- [Image Generation](https://openrouter.ai/docs/guides/overview/multimodal/image-generation)
