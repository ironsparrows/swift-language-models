package import CoreGraphics
package import Foundation
package import FoundationModels
package import ImageIO
package import UniformTypeIdentifiers

// MARK: - Fixture files

extension Bundle {
    /// The contents of a file in the bundle's `Fixtures` folder.
    ///
    /// The test target copies the folder as a resource with `resources: [.copy("Fixtures")]`, so the folder keeps its
    /// name in the bundle.
    ///
    /// - Parameter name: The file name with its extension, such as `plain-text.sse`.
    /// - Returns: The file's contents.
    /// - Throws: `CocoaError.fileNoSuchFile` when the bundle has no such fixture.
    package func fixture(_ name: String) throws -> Data {
        guard let url = url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Fixtures/\(name)"])
        }
        return try Data(contentsOf: url)
    }
}

// MARK: - Requests

/// What Foundation Models asks an executor for.
package func generationRequest(
    _ entries: [Transcript.Entry],
    tools: [Transcript.ToolDefinition] = [],
    schema: GenerationSchema? = nil,
    options: GenerationOptions = GenerationOptions(),
    metadata: [String: any ConvertibleToGeneratedContent] = [:]
) -> LanguageModelExecutorGenerationRequest {
    LanguageModelExecutorGenerationRequest(
        id: UUID(), transcript: Transcript(entries: entries), enabledTools: tools, schema: schema, generationOptions: options,
        contextOptions: ContextOptions(), metadata: metadata)
}

/// A prompt entry with the given segments.
package func prompt(_ segments: Transcript.Segment...) -> Transcript.Entry {
    .prompt(Transcript.Prompt(segments: segments))
}

/// A rating whose stars have a range, which the portable schema moves into the description.
@Generable
package struct Rating {
    @Guide(.range(1...5))
    package var stars: Int
}

/// A tool that looks up a word, and answers with the word.
package struct LookUpTool: Tool {
    package let name = "lookUp"
    package let description = "Looks up a word."

    @Generable
    package struct Arguments {
        package var word: String
    }

    package init() {}

    package func call(arguments: Arguments) async throws -> String {
        arguments.word
    }
}

// MARK: - Capabilities

extension LanguageModelCapabilities {
    /// The capabilities in the set, in a fixed order, so a test can compare them with one expectation.
    package var listed: [Capability] {
        [.toolCalling, .guidedGeneration, .reasoning, .vision].filter(contains)
    }
}

// MARK: - Images

/// Images drawn in code, so tests need no image files.
package enum TestImage {
    /// An image whose left half is red and right half blue, so a test can tell how it was turned.
    ///
    /// - Parameters:
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    /// - Returns: The image, or `nil` when Core Graphics can't draw it.
    package static func halves(width: Int, height: Int) -> CGImage? {
        draw(width: width, height: height) { context in
            context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
    }

    /// A thick black digit 7 on white, for a model to read.
    ///
    /// - Parameter size: The width and height in pixels.
    /// - Returns: The image, or `nil` when Core Graphics can't draw it.
    package static func seven(size: Int) -> CGImage? {
        let side = Double(size)
        return draw(width: size, height: size) { context in
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.setLineWidth(side / 9)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            // Core Graphics' y grows upward: the bar runs along the top, and the stroke falls to the bottom left.
            context.move(to: CGPoint(x: side * 0.25, y: side * 0.8))
            context.addLine(to: CGPoint(x: side * 0.75, y: side * 0.8))
            context.addLine(to: CGPoint(x: side * 0.4, y: side * 0.15))
            context.strokePath()
        }
    }

    /// An image as a file of a kind ImageIO writes, such as PNG or HEIC.
    ///
    /// - Parameters:
    ///   - image: The pixels.
    ///   - type: The kind of file.
    ///   - orientation: The orientation the file records, which a reader applies to turn the pixels upright.
    /// - Returns: The file's bytes, or `nil` when ImageIO can't write the kind.
    package static func file(of image: CGImage, as type: UTType, orientation: CGImagePropertyOrientation = .up) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Draws into an opaque sRGB canvas, with Core Graphics' y growing upward.
    private static func draw(width: Int, height: Int, _ drawing: (CGContext) -> Void) -> CGImage? {
        // Without a buffer of its own, the context allocates and owns its memory, so no pointer is ever used.
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = unsafe CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        drawing(context)
        return context.makeImage()
    }
}

/// An image file's pixels, decoded, so a test can check its size and where its colors are.
package struct DecodedImage {
    /// The width in pixels.
    package let width: Int

    /// The height in pixels.
    package let height: Int

    private let pixels: Data
    private let bytesPerRow: Int

    /// Decodes an image file, without applying the orientation it records, or fails when ImageIO can't read the data.
    ///
    /// - Parameter data: The file's bytes, such as a JPEG.
    package init?(_ data: Data) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = unsafe CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let pixels = context.makeImage()?.dataProvider?.data else { return nil }
        self.width = image.width
        self.height = image.height
        self.pixels = pixels as Data
        self.bytesPerRow = image.width * 4
    }

    /// The color of a pixel, counted from the top left, each component from 0 to 255.
    package func color(x: Int, y: Int) -> (red: Int, green: Int, blue: Int) {
        let offset = y * bytesPerRow + x * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
    }

    /// Whether a pixel is mostly red, allowing for JPEG's loss.
    package func isRed(x: Int, y: Int) -> Bool {
        let color = color(x: x, y: y)
        return color.red > 200 && color.green < 60 && color.blue < 60
    }

    /// Whether a pixel is mostly blue, allowing for JPEG's loss.
    package func isBlue(x: Int, y: Int) -> Bool {
        let color = color(x: x, y: y)
        return color.blue > 200 && color.red < 60 && color.green < 60
    }
}

// MARK: - PDF documents

/// A one-page PDF that shows a line of text in Helvetica, written out byte by byte, so tests need no PDF files.
///
/// - Parameter text: The line, in ASCII.
/// - Returns: The PDF's bytes.
package func pdfDocument(showing text: String) -> Data {
    let escaped = text.replacing("\\", with: "\\\\").replacing("(", with: "\\(").replacing(")", with: "\\)")
    let content = "BT /F1 24 Tf 72 720 Td (\(escaped)) Tj ET"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    var pdf = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(pdf.utf8.count)
        pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
    }
    let table = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
        pdf += String(repeating: "0", count: 10 - String(offset).count) + "\(offset) 00000 n \n"
    }
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(table)\n%%EOF\n"
    return Data(pdf.utf8)
}
