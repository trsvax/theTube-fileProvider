import FileProvider
import UniformTypeIdentifiers

class TubeItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let isFolder: Bool
    let contentType: UTType
    let documentSize: NSNumber?

    static let root = TubeItem(
        identifier: .rootContainer,
        parentIdentifier: .rootContainer,
        filename: "TubeFS",
        isFolder: true
    )

    init(identifier: NSFileProviderItemIdentifier,
         parentIdentifier: NSFileProviderItemIdentifier,
         filename: String,
         isFolder: Bool,
         size: Int? = nil) {

        self.itemIdentifier = identifier
        self.parentItemIdentifier = parentIdentifier
        self.filename = filename
        self.isFolder = isFolder
        self.documentSize = size.map { NSNumber(value: $0) }

        if isFolder {
            self.contentType = .folder
        } else if filename.hasSuffix(".json") {
            self.contentType = .json
        } else if filename.hasSuffix(".tsv") {
            self.contentType = UTType(filenameExtension: "tsv") ?? .plainText
        } else if filename.hasSuffix(".md") {
            self.contentType = UTType(filenameExtension: "md") ?? .plainText
        } else {
            self.contentType = .data
        }
    }

    // Read-only
    var capabilities: NSFileProviderItemCapabilities {
        if isFolder {
            return [.allowsReading, .allowsContentEnumerating]
        }
        return [.allowsReading]
    }

    var itemVersion: NSFileProviderItemVersion {
        // No versioning — content is always fresh from the tube
        NSFileProviderItemVersion(contentVersion: Data("1".utf8), metadataVersion: Data("1".utf8))
    }
}
