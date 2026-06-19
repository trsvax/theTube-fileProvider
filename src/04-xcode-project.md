---
title: The Xcode Project
date: 2026-06-05
tags: [tech, src]
type: journal
audience: owner
status: journaling
coffee: 2
summary: Everything Xcode needs to build TubeFS. Three targets, one app group, shared Keychain. The project file is the build system — documented here so it can be recreated without wizards.
workflow: draft
deploy:
  type: reference
  name: TubeFS.xcodeproj
  target: theTube-fileProvider/
  code: plist
---

## Three targets

One Xcode project, three targets:

| Target | Type | What |
|--------|------|------|
| `TubeFS` | macOS/iOS App | Container app — shows status, holds preferences |
| `TubeFileProvider` | File Provider Extension | The filesystem — appears in Finder/Files |
| `TubeShare` | Share Extension | Share sheet → `send-tube capture` from any app |

The container app does almost nothing — it exists because extensions require a host app. Maybe later it shows recent captures, tube status, or token management. For now it's a single view that says "TubeFS is active."

The Share Extension is the easier capture path. Share sheet is everywhere on iOS/macOS — any app that can share a URL or image can feed the tube. No Shortcuts setup, no automation config. Just "Share → Tube" and it fires a capture.

## App Group

All three targets share an app group:

```
group.com.thetube.fs
```

This gives them:
- Shared Keychain access (signing key readable by all three)
- Shared container (if you ever need local state between app and extensions)
- Shared UserDefaults (device ID, preferences visible to extensions)

Without the app group, the extension can't read the Keychain items the app writes.

## Bundle identifiers

```
com.thetube.fs                          ← container app
com.thetube.fs.file-provider            ← FileProvider extension
com.thetube.fs.share                    ← Share extension
```

The extension bundle IDs must be prefixed by the app's bundle ID. Xcode enforces this.

## Entitlements

### TubeFS.entitlements (container app)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.thetube.fs</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.thetube.fs</string>
    </array>
</dict>
</plist>
```

### TubeFileProvider.entitlements (File Provider extension)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.thetube.fs</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.thetube.fs</string>
    </array>
</dict>
</plist>
```

### TubeShare.entitlements (Share extension)

Same as above — needs Keychain access to read the signing key and fire a capture.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.thetube.fs</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.thetube.fs</string>
    </array>
</dict>
</plist>
```

## Info.plist — File Provider Extension

The critical entries. This tells the system it's a File Provider and which domain it manages.

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionFileProviderDocumentGroup</key>
    <string>group.com.thetube.fs</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.fileprovider-nonui</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).FileProviderExtension</string>
</dict>
```

Key points:
- `fileprovider-nonui` — this is a replicated (modern) file provider, not the deprecated UI-based one
- `NSExtensionFileProviderDocumentGroup` — must match the app group
- `NSExtensionPrincipalClass` — the class Xcode instantiates. Must match your Swift class name.

## Info.plist — Share Extension

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>NSExtensionActivationRule</key>
        <dict>
            <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
            <integer>1</integer>
            <key>NSExtensionActivationSupportsImageWithMaxCount</key>
            <integer>10</integer>
            <key>NSExtensionActivationSupportsFileWithMaxCount</key>
            <integer>10</integer>
        </dict>
    </dict>
</dict>
```

This says: the share extension accepts URLs, images, and files. One URL at a time (link capture), up to 10 images or files (batch upload).

## Build settings

| Setting | Value | Why |
|---------|-------|-----|
| Deployment Target | macOS 13.0 / iOS 16.0 | Minimum for replicated FileProvider |
| Swift Version | 5.9 | Async/await, actors |
| Code Signing | Automatic | Let Xcode manage profiles |
| Frameworks | FileProvider, CryptoKit, Security | System only — no SPM deps |

No Swift Package Manager dependencies. No CocoaPods. No Carthage. Three system frameworks, zero third-party code. CryptoKit provides P-256 signing. Security provides Keychain access with biometric protection.

## The Share Extension

Simpler than Shortcuts because:
- No intent definition file to maintain
- No parameter discovery
- No "donate" interactions
- No Shortcuts app configuration by the user
- Just appears in the share sheet automatically for matching content types

The code is minimal:

```swift
// ShareViewController.swift — Share Extension
import UIKit
import Social

class ShareViewController: SLComposeServiceViewController {
    override func didSelectPost() {
        // Read shared items, call TubeRequest.shared.fire("share/add", params: ...)
        // Signs with P-256 key from shared Keychain, dismisses
    }

    override func configurationItems() -> [Any]! {
        // Optional: let user pick capture type
        return []
    }
}
```

On iOS: share a photo from Camera Roll → Share → Tube → signs and fires a capture. On macOS: share a URL from Safari → Share → Tube → fires a link capture.

Same `TubeRequest.fire("share/add", ...)` as the CLI. One code path, three surfaces (CLI, share sheet, FileProvider writes if we ever add them).

## Creating the project

1. Xcode → File → New → Project
2. macOS → App → "TubeFS"
3. Team: your developer account
4. Organization: com.thetube
5. Interface: SwiftUI, Language: Swift
6. File → New → Target → macOS → File Provider Extension → "TubeFileProvider"
7. File → New → Target → (macOS or iOS) → Share Extension → "TubeShare"
8. For each target: Signing & Capabilities → + App Groups → add `group.com.thetube.fs`
9. For each target: Signing & Capabilities → + Keychain Sharing → add `com.thetube.fs`
10. Delete template code, drop in Swift from journal posts

## .gitignore

```
# Xcode
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.pbxuser
*.perspectivev3
xcuserdata/

# macOS
.DS_Store
```

The `.xcodeproj/project.pbxproj` is committed — it's the build config. User-specific data (breakpoints, window positions) is ignored.

## Multiplatform

Same project supports iOS by adding:
- iOS deployment target on each extension target
- Conditional compilation for platform-specific UI (share extension view differs slightly)
- `TubeRequest.swift` and all providers work unchanged — Foundation + CryptoKit are universal

One repo, one project, both platforms.

[journey]:
prev: file-provider
next:
The Xcode project is the part that can't be a `# src` block — it's generated by GUI. But the decisions (app groups, entitlements, bundle IDs, what targets exist) are worth documenting. This post is the recipe for recreating the project from scratch. The Share Extension is the second capture surface — easier than Shortcuts because it's just "show up in the share sheet for URLs and images, sign with P-256, fire a tubeRequest." Same protocol, different input surface. The container app now generates the signing key pair and shows the public key for server registration — no more importing JWT/secret from the login keychain.
