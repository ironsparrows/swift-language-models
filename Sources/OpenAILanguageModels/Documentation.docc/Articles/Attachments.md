# Attachments

Send images, PDFs and text with a prompt.

## Overview

Prompts and tool outputs carry images, and from OS 27.2 data attachments too: PDFs and text. A label goes before its
attachment as text, so the model can name it, as an `ImageReference` does:

@Snippet(path: "swift-language-models/Snippets/OpenAIAttachments", slice: "image")

An image goes as an `input_image`, as a JPEG drawn upright from its orientation, on white, and scaled down so that its
longer side is at most 2,048 pixels, with its `detail` set to `auto`. The model's ``OpenAIConfiguration/images`` change
that side and the JPEG quality, such as to 1,024 pixels for fewer input tokens. Only its pixels leave the device, never
metadata such as where a photo was taken. An image at a web address goes as that address, when it's upright and its
address is http or https; otherwise the request throws `LanguageModelError.unsupportedTranscriptContent`.

### Attach files

Data attachments need Xcode 27.2 at build time, since earlier SDKs lack them. ``FileAttachment``, from the
`LanguageModels` module, reads a file and tells its type from its extension, or wraps bytes of a type you name:

@Snippet(path: "swift-language-models/Snippets/OpenAIAttachments", slice: "file")

``FileAttachment/init(contentsOf:)`` throws ``FileAttachment/UnknownTypeError`` for a file whose extension names no type
the system knows, such as one without an extension; pass the type yourself with ``FileAttachment/init(_:type:)``.

- An image file, such as a PNG or HEIC file, goes as an image attachment does.
- A PDF goes as an `input_file`, named by its label, with `.pdf` added when the label lacks it, or `document.pdf`
  without a label.
- Plain text goes as text.
- Audio and video aren't taken: a request with either throws `LanguageModelError.unsupportedTranscriptContent`
  before sending anything.

### Check what a model takes

``OpenAIModel/inputModalities`` lists the kinds a model takes: `text`, `image` and `pdf`. GPT-6 Luna takes all three,
and GPT-5.2 takes text and images, but not PDFs. `supportsDataAttachmentType(_:)` says whether the model takes a kind
of data:

@Snippet(path: "swift-language-models/Snippets/OpenAIAttachments", slice: "kinds")

When the model doesn't take an attachment, a request throws before sending anything:
`LanguageModelError.unsupportedCapability` with `.vision` for an image attachment, and
`LanguageModelError.unsupportedTranscriptContent` for a data attachment, an image file included. Instructions take
only text, so an attachment there throws `unsupportedTranscriptContent` too. An image OpenAI rejects, such as one too
large or in a format it can't read, throws `unsupportedTranscriptContent`, naming the entries with images.
<doc:Mapping#Requests> lists the part each kind of attachment becomes.

Generated data and an answer's attachments stay in the transcript but aren't sent back. Each request sends the whole
transcript, so a prompt's attachment goes again with every later request of the session.

### Get images back

A model draws images with the image generation server tool, from OS 27.2. Each image is a data entry of its own, of its
format's kind, which `supportsDataEntryType(_:)` says the model generates. The image's call goes back on later turns,
so the model can change the image, while OpenAI keeps responses. <doc:ServerTools> shows how.

### Apple's guides

- [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Attachment](https://developer.apple.com/documentation/foundationmodels/attachment),
  [ImageReference](https://developer.apple.com/documentation/foundationmodels/imagereference) and
  [DataAttachmentRepresentable](https://developer.apple.com/documentation/foundationmodels/dataattachmentrepresentable)

### OpenAI's guides

- [Images and vision](https://developers.openai.com/api/docs/guides/images-vision)
- [File inputs](https://developers.openai.com/api/docs/guides/file-inputs), on PDFs
