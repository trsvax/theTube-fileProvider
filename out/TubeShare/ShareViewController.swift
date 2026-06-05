import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            await handleShare()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
    private func handleShare() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

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

        do {
            _ = try await TubeRequest.shared.fire("share/add", params: params)
        } catch {
            // Silent failure — share extensions shouldn't block the user
            // Log to shared container for debugging if needed
        }
    }
}
// Info.plist NSExtensionActivationRule (set in Xcode target)
// - URLs: 1 (link capture)
// - Images: 10 (batch capture)
// - Files: 10 (batch upload)
// - Text: 1 (note capture)
