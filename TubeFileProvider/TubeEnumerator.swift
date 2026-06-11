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
        // Signal all content has changed by re-enumerating from scratch
        observer.finishEnumeratingChanges(upTo: currentAnchor(), moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(currentAnchor())
    }

    private func currentAnchor() -> NSFileProviderSyncAnchor {
        // Change anchor each time extension launches — forces re-enumeration
        let ts = String(Int(Date().timeIntervalSince1970 / 60)) // changes every minute
        return NSFileProviderSyncAnchor(Data(ts.utf8))
    }
}
