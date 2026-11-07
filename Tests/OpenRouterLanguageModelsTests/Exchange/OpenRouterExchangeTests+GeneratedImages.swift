import Foundation
import FoundationModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import LanguageModels
@testable import OpenRouterLanguageModels

#if canImport(FoundationModels, _version: 2.1.14)
/// A chunk with generated images, each at the given URL.
private func images(_ urls: String...) -> JSONValue {
    chunk(["images": .array(urls.map { ["type": "image_url", "image_url": ["url": .string($0)]] })])
}

/// The data entries of a transcript.
@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
private func dataEntries(_ entries: some Sequence<Transcript.Entry>) -> [Transcript.DataEntry] {
    entries.compactMap { entry in
        if case .data(let data) = entry { data } else { nil }
    }
}

/// The output kinds of a model and of its fallback, if any, whether the request has a schema, and the `modalities` it
/// asks for.
private let modalityCases: [(Set<OpenRouterOutputModality>, Set<OpenRouterOutputModality>?, Bool, JSONValue?)] = [
    ([.text, .image], nil, false, ["image", "text"]),
    ([.image], nil, false, ["image"]),
    ([.text, .image], [.text, .image], false, ["image", "text"]),
    ([.text, .image], [.text], false, nil),
    ([.text, .image], nil, true, nil),
    ([.text], nil, false, nil),
    ([.text, .audio], nil, false, nil),
]

extension OpenRouterExchangeTests {
    @Suite("Generated images")
    struct GeneratedImages {
        /// The bytes of a tiny PNG.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `a generated image becomes a data entry of the kind its data URL names, next to the answer's text`() async throws {
            let url = DataURL(mediaType: "image/png", data: png).text
            let stub = HTTPStub(events(text("Here's a cat."), images(url), done()))
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image], outputs: [.text, .image]))

            let response = try await session.respond(to: "Draw a cat.")

            #expect(response.content == "Here's a cat.")
            let entries = dataEntries(response.transcriptEntries)
            #expect(entries.map(\.contentType) == [.png])
            #expect(entries.map(\.content) == [png])
            #expect(dataEntries(session.transcript).count == 1)
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `each image becomes a data entry of its own, in order, and an answer of only images still has a response`()
            async throws
        {
            let webp = Data([0x52, 0x49, 0x46, 0x46])
            let stub = HTTPStub(
                events(
                    images(DataURL(mediaType: "image/png", data: png).text, DataURL(mediaType: "image/webp", data: webp).text),
                    images(DataURL(mediaType: "image/jpeg", data: png).text), done())
            )
            let session = LanguageModelSession(model: model(stub, outputs: [.text, .image]))

            let response = try await session.respond(to: "Draw three cats.")

            #expect(response.content.isEmpty)
            #expect(dataEntries(response.transcriptEntries).map(\.contentType) == [.png, .webP, .jpeg])
            #expect(dataEntries(response.transcriptEntries).map(\.content) == [png, webp, png])
            #expect(Set(dataEntries(response.transcriptEntries).map(\.id)).count == 3)
            #expect(plainText(try lastResponse(of: response).segments).isEmpty)
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `an image at a web address, or data that isn't base64, is left out`() async throws {
            let stub = HTTPStub(
                events(text("Done."), images("https://images.example.com/cat.png", "data:image/png,raw", "data:;base64,%%%"), done()))
            let session = LanguageModelSession(model: model(stub, outputs: [.text, .image]))

            let response = try await session.respond(to: "Draw a cat.")

            #expect(response.content == "Done.")
            #expect(dataEntries(response.transcriptEntries).isEmpty)
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `an image of an unknown kind is still an image`() async throws {
            let stub = HTTPStub(events(images(DataURL(mediaType: "image/x-sketch", data: png).text), done()))
            let session = LanguageModelSession(model: model(stub, outputs: [.text, .image]))

            let response = try await session.respond(to: "Sketch a cat.")

            let entry = try #require(dataEntries(response.transcriptEntries).first)
            #expect(entry.contentType.conforms(to: .image))
            #expect(entry.content == png)
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `generated images aren't sent back on later turns, while the answer's text is`() async throws {
            let stub = HTTPStub(
                events(text("Here's a cat."), images(DataURL(mediaType: "image/png", data: png).text), done()),
                events(text("It's orange."), done())
            )
            let session = LanguageModelSession(model: model(stub, inputs: [.text, .image], outputs: [.text, .image]))

            _ = try await session.respond(to: "Draw a cat.")
            _ = try await session.respond(to: "Which color is it?")

            let messages = messages(try body(stub, 1))
            #expect(messages.map { $0["role"] } == ["user", "assistant", "user"])
            #expect(messages[1] == ["role": "assistant", "content": "Here's a cat."])
            #expect(!String(decoding: try #require(stub.requests.last).body, as: UTF8.self).contains(png.base64EncodedString()))
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test(arguments: modalityCases)
        func `images and text are asked for when every model generates images and no schema is set`(
            outputs: Set<OpenRouterOutputModality>,
            fallbackOutputs: Set<OpenRouterOutputModality>?,
            hasSchema: Bool,
            modalities: JSONValue?
        ) async throws {
            let stub = HTTPStub(events(text(hasSchema ? #"{"name":"Tom"}"# : "Hi"), done()))
            let fallbacks = fallbackOutputs.map { [fallback(outputs: $0)] } ?? []
            let session = LanguageModelSession(model: model(stub, outputs: outputs, fallbacks: fallbacks))

            if hasSchema {
                _ = try await session.respond(to: "Name a cat.", schema: Cat.generationSchema)
            } else {
                _ = try await session.respond(to: "Draw a cat.")
            }

            #expect(try body(stub)["modalities"] == modalities)
        }

        @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
        @Test func `the data kinds supported are the images that every model generates`() async throws {
            let stub = HTTPStub()
            let painter = model(stub, outputs: [.text, .image])
            let speaker = model(stub, outputs: [.text, .audio])
            let chain = model(stub, outputs: [.text, .image], fallbacks: [fallback(outputs: [.text])])

            #expect(try await painter.supportsDataEntryType(.png))
            #expect(try await !painter.supportsDataEntryType(.wav))
            #expect(try await !speaker.supportsDataEntryType(.wav))
            #expect(speaker.details.dataEntryTypes.isEmpty)
            #expect(try await !chain.supportsDataEntryType(.png))
        }
    }
}

/// A cat with a name, for a request with a schema.
@Generable
private struct Cat {
    var name: String
}
#endif
