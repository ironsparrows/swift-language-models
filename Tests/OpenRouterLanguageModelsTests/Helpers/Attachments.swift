import Foundation
import FoundationModels
import LanguageModelsTestSupport

@testable import LanguageModels
@testable import OpenRouterLanguageModels

/// A prompt entry with an attachment and no text.
func attachmentPrompt(_ attachment: Transcript.Attachment, label: String? = nil) -> Transcript.Entry {
    .prompt(Transcript.Prompt(segments: [.attachment(.init(content: attachment, label: label))]))
}

/// The content parts of a message, or none when its content is a string.
func parts(_ message: JSONValue?) -> [JSONValue] {
    elements(message?["content"])
}

/// The bytes of a part's data URL, such as an `image_url` part's.
func dataURL(_ part: JSONValue?) -> DataURL? {
    (part?["image_url"]?["url"] ?? part?["video_url"]?["url"] ?? part?["file"]?["file_data"])?.stringValue.flatMap(DataURL.init)
}
