package import Foundation
package import UniformTypeIdentifiers

/// Data a model generated, of a kind, such as an image, which an answer sends as a data entry of its own.
package struct GeneratedData {
    package let contentType: UTType
    package let content: Data

    package init(contentType: UTType, content: Data) {
        self.contentType = contentType
        self.content = content
    }
}
