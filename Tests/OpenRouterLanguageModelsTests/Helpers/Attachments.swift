import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport

@testable import OpenRouterLanguageModels

/// A prompt entry with an attachment and no text.
func attachmentPrompt(_ attachment: Transcript.Attachment, label: String? = nil) -> Transcript.Entry {
    .prompt(Transcript.Prompt(segments: [.attachment(.init(content: attachment, label: label))]))
}

/// The content parts of a message, or none when its content is a string.
func parts(_ message: JSONValue?) -> [JSONValue] {
    elements(message?["content"])
}

/// What a part's data URL holds.
struct SentData: Equatable {
    let mediaType: String
    let data: Data
}

/// What a part's data URL holds, such as an `image_url` part's.
func dataURL(_ part: JSONValue?) -> SentData? {
    let url = part?["image_url"]?["url"] ?? part?["video_url"]?["url"] ?? part?["file"]?["file_data"]
    guard let text = url?.stringValue, text.hasPrefix("data:"), let comma = text.firstIndex(of: ","),
        let data = Data(base64Encoded: String(text[text.index(after: comma)...]))
    else { return nil }
    return SentData(mediaType: String(text.dropFirst(5).prefix { $0 != ";" && $0 != "," }), data: data)
}

/// Bytes as a base64 data URL, as a host sends a generated image.
func dataURLText(mediaType: String, data: Data) -> String {
    "data:\(mediaType);base64,\(data.base64EncodedString())"
}
