---
title: The File Provider
date: 2026-06-05
tags: [tech, src]
type: journal
audience: owner
status: journaling
coffee: 2
summary: The tube in Finder. Apple's FileProvider framework turns tubeRequest into a native filesystem. Enumerate, fetch, done. The system handles caching, thumbnails, and the sidebar.
workflow: draft
deploy:
  type: multi
  target: TubeFS/
  code: swift
  files:
    - TubeFileProvider/FileProviderExtension.swift
    - TubeFileProvider/TubeItem.swift
    - TubeFileProvider/TubeEnumerator.swift
    - TubeFileProvider/ProviderRouter.swift
---

## Why FileProvider

The WebDAV server works. But it's a localhost process you start manually, mount manually, and kill manually. It can't go in the App Store. It can't run on iOS. It doesn't get Touch ID for free.

FileProvider is Apple's answer to "I have files somewhere else." You implement an extension, the system mounts it. Finder shows it in the sidebar. Files.app on iOS shows it too. Same code, both platforms. The system manages caching, eviction, and conflict resolution — you just enumerate items and provide content on demand.

Three things to implement:
1. **Extension** — the entry point, creates enumerators
2. **Enumerator** — lists items for a container (folder)
3. **Item** — metadata for one file or folder

```swift # src TubeFileProvider/FileProviderExtension.swift
import FileProvider
import UniformTypeIdentifiers

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }
```

## Item identifiers

Every item has a unique identifier. The root is `.rootContainer`. Children are paths encoded as identifiers. The identifier *is* the tube path.

```
.rootContainer          → /
"logs"                  → /logs/
"logs/2026-05-21"       → /logs/2026-05-21/
"logs/2026-05-21/00.tsv" → /logs/2026-05-21/00.tsv
"aws"                   → /aws/
"aws/cloudfront"        → /aws/cloudfront/
```

The identifier is the path. No mapping table. No database. The namespace *is* the addressing scheme.

```swift # src TubeFileProvider/FileProviderExtension.swift
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
```

## Enumerator

The system calls `enumerator(for:)` when Finder needs to list a folder's contents. Return an enumerator that knows how to fetch items for that container.

```swift # src TubeFileProvider/FileProviderExtension.swift
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {

        return TubeEnumerator(containerIdentifier: containerItemIdentifier)
    }
```

## Fetching content

When the user opens a file, the system calls `fetchContents`. Route to the right provider based on the path prefix, get the data via tubeRequest, write it to the provided URL.

```swift # src TubeFileProvider/FileProviderExtension.swift
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
```

## No writes (for now)

The tube is read-only through the filesystem. Writes go through `send-tube` or the share system. The FileProvider reports items as read-only — Finder won't offer rename, delete, or drag-to-copy-in.

```swift # src TubeFileProvider/FileProviderExtension.swift
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
```

---

## TubeItem

Metadata for one file or folder. Minimal — identifier, parent, name, type. The system uses this for Finder display.

```swift # src TubeFileProvider/TubeItem.swift
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
```

---

## TubeEnumerator

Lists items for a container. Calls the provider router with the container's path, gets back a list of items.

```swift # src TubeFileProvider/TubeEnumerator.swift
import FileProvider

class TubeEnumerator: NSObject, NSFileProviderEnumerator {
    private let containerIdentifier: NSFileProviderItemIdentifier

    init(containerIdentifier: NSFileProviderItemIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {

        Task {
            do {
                let path = containerIdentifier == .rootContainer
                    ? ""
                    : containerIdentifier.rawValue

                let items = try await ProviderRouter.shared.listItems(path: path)
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // No change tracking — always fresh
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        // Static anchor — we don't track changes
        completionHandler(NSFileProviderSyncAnchor(Data("1".utf8)))
    }
}
```

---

## ProviderRouter

Routes paths to providers. Same concept as the WebDAV server's provider chain — first match wins.

```swift # src TubeFileProvider/ProviderRouter.swift
import FileProvider

actor ProviderRouter {
    static let shared = ProviderRouter()

    func listItems(path: String) async throws -> [NSFileProviderItem] {
        // Root listing
        if path.isEmpty {
            return [
                TubeItem(identifier: NSFileProviderItemIdentifier("logs"),
                         parentIdentifier: .rootContainer, filename: "logs", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws"),
                         parentIdentifier: .rootContainer, filename: "aws", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("tube"),
                         parentIdentifier: .rootContainer, filename: "tube", isFolder: true),
            ]
        }

        // Route to provider
        if path == "aws" || path.hasPrefix("aws/") {
            return try await AWSProvider.shared.list(path: path)
        }
        if path == "logs" || path.hasPrefix("logs/") {
            return try await LogsProvider.shared.list(path: path)
        }
        if path == "tube" || path.hasPrefix("tube/") {
            return try await TubeStorageProvider.shared.list(path: path)
        }

        return []
    }

    func fetchContent(path: String) async throws -> Data {
        if path.hasPrefix("aws/") {
            return try await AWSProvider.shared.fetch(path: path)
        }
        if path.hasPrefix("logs/") {
            return try await LogsProvider.shared.fetch(path: path)
        }
        if path.hasPrefix("tube/") {
            return try await TubeStorageProvider.shared.fetch(path: path)
        }

        throw TubeRequest.TubeError.unexpected("No provider for path: \(path)")
    }
}
```

[journey]:
prev: tube-request-swift
next: provider-protocol
The WebDAV server was the prototype — prove the namespace works with PROPFIND and GET. The FileProvider is the same namespace surfaced through Apple's framework. Identifiers are paths. Enumerators call providers. Providers call tubeRequest. The system handles everything else: caching, sidebar, iOS. Read-only for now — writes go through send-tube. The hard part isn't the code, it's the entitlements and signing. The code is just routing.
