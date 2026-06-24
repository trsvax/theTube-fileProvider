#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DebugLog.log("Share: extension launched")
        Task {
            await handleShare()
            DebugLog.log("Share: completing request")
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func handleShare() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            DebugLog.log("Share: no input items")
            return
        }

        DebugLog.log("Share: \(items.count) input items")

        // Check key availability early
        if !KeyManager.hasKey() {
            DebugLog.log("Share: ERROR — no signing key in Keychain (extension cannot access key)")
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        await capture(file: url.absoluteString, type: "link")
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL {
                        await capture(file: url.lastPathComponent, type: "image")
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        await capture(file: text, type: "note")
                    }
                }
            }
        }
    }

    private func capture(file: String, type: String) async {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let params: [String: Any] = [
            "type": type,
            "file": file,
            "date": String(today),
        ]

        DebugLog.log("Share: capture \(type) → \(file)")
        do {
            let result = try await TubeRequest.shared.fire("share/add", params: params)
            DebugLog.log("Share: success → \(result)")
        } catch {
            DebugLog.log("Share: error → \(error)")
        }
    }
}

#else
import AppKit
import UniformTypeIdentifiers

class ShareViewController: NSViewController {

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task {
            await handleShare()
            extensionContext?.completeRequest(returningItems: nil) { _ in }
        }
    }

    private func handleShare() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let item = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) {
                        let urlString: String?
                        if let url = item as? URL {
                            urlString = url.absoluteString
                        } else if let data = item as? Data {
                            urlString = String(data: data, encoding: .utf8)
                        } else {
                            urlString = nil
                        }
                        if let urlString, !urlString.isEmpty {
                            await capture(file: urlString, type: "link")
                        }
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL {
                        await capture(file: url.lastPathComponent, type: "image")
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        await capture(file: text, type: "note")
                    }
                }
            }
        }
    }

    private func capture(file: String, type: String) async {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let params: [String: Any] = [
            "type": type,
            "file": file,
            "date": String(today),
        ]

        DebugLog.log("Share: capture \(type) → \(file)")
        do {
            let result = try await TubeRequest.shared.fire("share/add", params: params)
            DebugLog.log("Share: success → \(result)")
        } catch {
            DebugLog.log("Share: error → \(error)")
        }
    }
}
#endif
