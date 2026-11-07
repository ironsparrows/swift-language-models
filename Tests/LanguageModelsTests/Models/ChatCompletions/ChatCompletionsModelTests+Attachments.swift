import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels

extension ChatCompletionsModelTests {
    @Suite("Attachments")
    struct Attachments {
        #if canImport(FoundationModels, _version: 2.1.14)
        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `a PDF goes as a named file part and WAV audio as input_audio, after their labels`() throws {
            let pdf = Transcript.DataAttachment(contentType: .pdf, content: Data("%PDF-1.4".utf8))
            let audio = Transcript.DataAttachment(contentType: .wav, content: Data("RIFF".utf8))
            let entry = prompt(.attachment(.init(content: .data(pdf), label: "Menu")), .attachment(.init(content: .data(audio))))

            let parts = messages(try ChatCompletionsSentRequest(generationRequest([entry])).body).first?["content"]

            #expect(
                parts == [
                    ["type": "text", "text": "Menu"],
                    ["type": "file", "file": ["filename": "Menu.pdf", "file_data": "data:application/pdf;base64,JVBERi0xLjQ="]],
                    ["type": "input_audio", "input_audio": ["data": "UklGRg==", "format": "wav"]],
                ])
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `data of a kind neither the format nor the provider has a part for throws`() {
            let movie = Transcript.DataAttachment(contentType: .mpeg4Movie, content: Data([1, 2]))

            #expect(throws: LanguageModelError.self) {
                try ChatCompletionsSentRequest(generationRequest([prompt(.attachment(.init(content: .data(movie))))]))
            }
        }
        #endif
    }
}
