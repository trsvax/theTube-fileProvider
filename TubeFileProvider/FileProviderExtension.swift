import FileProvider
import UniformTypeIdentifiers

@objc(FileProviderExtension)
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        NSLog("TubeFileProvider: init with domain %@", domain.identifier.rawValue)
    }
    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {

        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                let item = try await resolveItem(identifier: identifier)
                completionHandler(item, nil)
            } catch {
                completionHandler(nil, error)
            }
            progress.completedUnitCount = 1
        }

        return progress
    }

    private func resolveItem(identifier: NSFileProviderItemIdentifier) async throws -> NSFileProviderItem {
        if identifier == .rootContainer {
            return TubeItem.root
        }

        let path = identifier.rawValue
        let components = path.split(separator: "/")
        let name = String(components.last ?? "")
        let parentPath = components.dropLast().joined(separator: "/")
        let parentId = parentPath.isEmpty
            ? NSFileProviderItemIdentifier.rootContainer
            : NSFileProviderItemIdentifier(parentPath)

        // Determine if this is a file or folder by checking the last component
        let isFile = name.contains(".")

        return TubeItem(
            identifier: identifier,
            parentIdentifier: parentId,
            filename: name,
            isFolder: !isFile
        )
    }
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {

        return TubeEnumerator(containerIdentifier: containerItemIdentifier)
    }
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {

        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                let path = itemIdentifier.rawValue
                let content = try await ProviderRouter.shared.fetchContent(path: path)

                // Write to a temporary file
                let tempDir = FileManager.default.temporaryDirectory
                let filename = path.split(separator: "/").last.map(String.init) ?? "file"
                let tempFile = tempDir.appendingPathComponent(filename)
                try content.write(to: tempFile)

                let item = try await resolveItem(identifier: itemIdentifier)
                completionHandler(tempFile, item, nil)
            } catch {
                completionHandler(nil, nil, error)
            }
            progress.completedUnitCount = 1
        }

        return progress
    }
    // MARK: - Not implemented (read-only filesystem)

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError))
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError))
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        completionHandler(NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError))
        return Progress()
    }

    func invalidate() {
        // Clean up
    }
}
