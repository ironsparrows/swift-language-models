// FoundationModels 2.1.14 comes with Xcode 27.2, the first SDK with data attachments and data entries.
#if canImport(FoundationModels, _version: 2.1.14)
public import UniformTypeIdentifiers

@available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
extension DetailedLanguageModel {
    /// Whether the details of the model and of each of its fallbacks list the kind of data as a prompt attachment
    /// they accept.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the kind conforms to one of the `dataAttachmentTypes` of every model a request may reach.
    /// - Throws: Nothing; the method throws only because Foundation Models declares it so.
    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        details.supportsDataAttachmentType(type) && fallbacks.allSatisfy { $0.supportsDataAttachmentType(type) }
    }

    /// Whether the details of the model and of each of its fallbacks list the kind of data as one they generate.
    ///
    /// - Parameter type: The kind of data, such as `UTType.png`.
    /// - Returns: Whether the kind conforms to one of the `dataEntryTypes` of every model a request may reach.
    /// - Throws: Nothing; the method throws only because Foundation Models declares it so.
    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        details.supportsDataEntryType(type) && fallbacks.allSatisfy { $0.supportsDataEntryType(type) }
    }
}
#endif
