---
title: The Share Extension
date: 2026-06-05
tags: [tech, src]
type: journal
audience: owner
status: journaling
coffee: 2
summary: Share sheet → tube. One extension, both platforms. Replaces the Shortcuts workaround with real code that can be debugged, versioned, and tested.
workflow: draft
deploy:
  type: module
  name: ShareViewController.swift
  target: TubeFS/TubeShare/ShareViewController.swift
  code: swift
---

## Why not Shortcuts

Shortcuts is a flowchart that silently fails and can't be diffed. You can't version it. You can't test it. You can't debug it. You can't grep it. When it breaks, you stare at colored blocks and guess.

The macOS Shortcut that works today:
1. Receive input from share sheet
2. Get name of Shortcut Input
3. Run Shell Script: `tee ~/tube-debug.txt | ~/bin/send-tube`

Three steps, two failure modes (stdin parsing, shell environment), zero error reporting. And it only works on Mac because `send-tube` is a bash script.

The Share Extension replaces all of that with Swift you can read:

```swift # src TubeShare/ShareViewController.swift
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
```

## Extract the shared item

The system passes shared items as `NSItemProvider` attachments. Extract the URL, image, or file — detect the type, same as `send-tube`:

```swift # src TubeShare/ShareViewController.swift
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
```

## Fire the capture

Same `TubeRequest.fire("share/add", ...)` that `send-tube capture` uses. One code path. The extension shares the Keychain via the app group — same JWT, same secret, same time-hash.

```swift # src TubeShare/ShareViewController.swift
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
```

## What this replaces

| Before (Shortcuts) | After (Share Extension) |
|---------------------|------------------------|
| Flowchart UI | Swift source |
| Silent failures | Catchable errors |
| Mac only (`send-tube` is bash) | Mac + iOS, same code |
| stdin/arguments gymnastics | `NSItemProvider` API |
| Shell environment dependency | Self-contained binary |
| Can't be versioned | Git, diffs, PRs |
| Can't be tested | XCTest |

## Both platforms

The same `ShareViewController` runs on macOS and iOS. The share sheet is universal — Safari on Mac, Safari on iPhone, Photos on iPad. One target with both deployment targets set.

On Mac, three capture paths coexist:
- `send-tube` from terminal (stays — it's useful for scripting and pipes)
- Share sheet from Safari/Finder/Photos (GUI, replaces Shortcut)
- Both hit the same tube, same locker structure

On iOS:
- Share sheet from any app (the only capture path needed)
- Files.app for browsing (from the FileProvider extension)

## No UI

The extension has no compose view. Share → it fires → it dismisses. No confirmation dialog, no "post" button, no text field. Instant capture. The data is in the shared item — type detection is automatic.

If you ever want a caption field, add a `SLComposeServiceViewController` instead. But the zero-UI version matches `send-tube capture` — fire and forget.

## The activation rule

Which share sheet items trigger the extension:

```swift # src TubeShare/ShareViewController.swift
// Info.plist NSExtensionActivationRule (set in Xcode target)
// - URLs: 1 (link capture)
// - Images: 10 (batch capture)
// - Files: 10 (batch upload)
// - Text: 1 (note capture)
```

This means the "Tube" option appears in the share sheet only when sharing URLs, images, files, or text. Not for audio, video, or other types (unless you want those too — just add them).

[journey]:
prev: xcode-project
next:
The Shortcuts version was the prototype. It proved the flow works: share sheet → extract content → fire to tube. But it's unmaintainable — a flowchart you can't diff, test, or debug. The native extension is the same three-step flow in Swift: receive attachment, detect type, fire tubeRequest. Same result, real code. Both platforms from one source file. The $99/year Apple Developer fee pays for itself in never writing another Shortcut.
