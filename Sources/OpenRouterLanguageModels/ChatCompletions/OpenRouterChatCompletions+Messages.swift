import Foundation
import FoundationModels
import LanguageModels
import UniformTypeIdentifiers

extension OpenRouterChatCompletions {
    /// Checks that every model takes an attachment: images, and data of the input kinds they all take.
    func checkAttachment(_ attachment: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {
        switch attachment {
        case .image:
            guard model.attachmentInputs.contains(.image) else {
                throw LanguageModelError.unsupported(.vision, "The model or one of its fallbacks doesn't take images.")
            }
        case .data(let type):
            guard let input = OpenRouterInputModality(carrying: type) else {
                throw LanguageModelError.unsupported(entry, "\(Self.name) takes no attachments of type \(type.identifier).")
            }
            guard model.attachmentInputs.contains(input) else {
                throw LanguageModelError.unsupported(
                    entry, "The model or one of its fallbacks doesn't take \(input) attachments, such as \(type.identifier).")
            }
        }
    }

    /// The kinds of audio and movies OpenRouter takes beyond the format's, each with its part.
    static var openRouterMedia: [MediaPart] {
        let audio = OpenRouterInputModality.audioTypes.compactMap { type in audioNames[type].map { MediaPart.audio(type, format: $0) } }
        let video = OpenRouterInputModality.videoTypes.compactMap { type in videoNames[type].map { MediaPart.video(type, mediaType: $0) } }
        return audio + video
    }

    /// OpenRouter's `input_audio` format for each kind of audio it takes beyond WAV and MP3, which the format names.
    private static var audioNames: [UTType?: String] {
        [
            .aiff: "aiff", .mpeg4Audio: "m4a", OpenRouterInputModality.UnnamedType.aacAudio: "aac",
            OpenRouterInputModality.UnnamedType.flacAudio: "flac", OpenRouterInputModality.UnnamedType.oggAudio: "ogg",
        ]
    }

    /// The media type OpenRouter names each kind of movie by in a `video_url` data URL.
    private static var videoNames: [UTType?: String] {
        [
            .mpeg4Movie: "video/mp4", .mpeg: "video/mpeg", .quickTimeMovie: "video/mov",
            OpenRouterInputModality.UnnamedType.webMMovie: "video/webm",
        ]
    }

    /// The assistant message's `reasoning` and `reasoning_details` for the reasoning it sends back.
    ///
    /// The details go back as OpenRouter sent them, and the text of the reasoning that came with them, since text
    /// without them would reach the host unsigned. Reasoning that came as text alone goes back as text, as OpenRouter
    /// takes it from models that return only raw reasoning. A block the model wrote in its answer's text already goes
    /// back there, so its text isn't sent again. Some models send an empty list of details when they didn't reason,
    /// and expect it back.
    func replayMembers(_ reasoning: [ReplayedReasoning]) -> OpenRouterReplayMembers {
        var signedText = ""
        var plainText = ""
        var details: [JSONValue]?
        for replayed in reasoning {
            if let sent = ReasoningDetails.replayed(from: replayed.entry) {
                details = (details ?? []) + sent
                if !sent.isEmpty { signedText += replayed.text }
            }
            if ReasoningDetails.isTextAlone(replayed.entry) { plainText += replayed.text }
        }
        let text = ((details ?? []).isEmpty ? "" : signedText) + plainText
        return OpenRouterReplayMembers(reasoning: text.isEmpty ? nil : text, reasoningDetails: details)
    }
}

/// The members an assistant message carries for the reasoning OpenRouter sends back.
struct OpenRouterReplayMembers: Encodable {
    /// The reasoning's text, or `nil` when there's none to send.
    let reasoning: String?

    /// The `reasoning_details` as OpenRouter sent them, which go back unchanged, so each stays the JSON it was.
    let reasoningDetails: [JSONValue]?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        try container.encodeIfPresent(reasoning, forKey: "reasoning")
        try container.encodeIfPresent(reasoningDetails, forKey: "reasoning_details")
    }
}
