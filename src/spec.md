---
title: TubeFS
date: 2026-06-05
---

# TubeFS

A macOS/iOS app that mounts the tube as a native filesystem via Apple's FileProvider framework, with a Share Extension for capturing content from any app.

## What it does

1. **FileProvider** — the tube appears in Finder (macOS) and Files.app (iOS)
2. **Share Extension** — share sheet → capture to tube from any app, both platforms
3. **Tour Browser** — CarPlay audio app for narrated landmark/mural tours
4. **Photo Extension** — platinum print curve + invert inside Photos.app

One install, four extensions, one shared auth layer.

## Architecture

```
Shared/
  TubeRequest.swift              ← auth + network (Keychain, CryptoKit, URLSession)

TubeFileProvider/
  FileProviderExtension.swift    ← entry point, enumerator factory, fetch
  TubeItem.swift                 ← file/folder metadata
  TubeEnumerator.swift           ← lists items for a container
  ProviderRouter.swift           ← routes paths to providers
  Providers/
    AWSProvider.swift            ← aws/ subtree
    LogsProvider.swift           ← logs/ subtree
    TubeStorageProvider.swift    ← tube/ subtree

TubeShare/
  ShareViewController.swift      ← share sheet → fire capture → dismiss

TubeTour/
  TourScene.swift                ← CarPlay scene delegate
  TourData.swift                 ← loads tour JSON from tube or bundle
  TourNarrator.swift             ← AVSpeechSynthesizer for TTS

TubePhoto/
  PhotoEditingExtension.swift    ← curve + invert for platinum negatives

TubeFS/
  TubeFSApp.swift                ← container app (minimal)
```

## Auth — Secure Enclave (iOS 27+)

Each device generates a P256 key pair in the Secure Enclave. The private key never leaves hardware. Public key registered once via an existing authenticated device.

```
POST https://thetube.today/tube/{path}
X-Device: {device-id}
X-Timestamp: {unix seconds}
X-Signature: {P256.sign(privateKey, timestamp + path + sha256(body))}
Content-Type: application/json
```

Server: look up public key in `s3://trsvax-blog/tube/devices/index.json`, verify signature, check timestamp ±30s.

Pairing flow:
1. App generates key pair in Secure Enclave on first launch
2. Shows public key fingerprint / QR code
3. Existing device runs `send-tube device add <name> <pubkey>`
4. Server adds public key to devices/index.json
5. New device retries, gets 200, done

Fallback: iCloud Keychain sync of a software P256 key (non-Secure-Enclave) for single-identity-across-devices mode.

## CarPlay Tour Browser

Category: **Audio** (no navigation entitlement needed)

Data source: `tours/index.json` → individual tour JSON files with waypoints.

```json
{
  "name": "Mother Road",
  "lat": 35.171404,
  "lon": -103.717850,
  "desc": "Motel Safari, 722 E. Route 66",
  "story": "The Mother Road mural faces Route 66 from the Motel Safari's east wall..."
}
```

UI:
- `CPListTemplate` — tour list with thumbnails
- `CPListTemplate` with details header — single waypoint, photo, description, buttons
- Action: "Navigate" → opens Apple Maps via `maps://` URL
- Action: "Listen" → `AVSpeechSynthesizer` reads the `story` field
- `CPNowPlayingTemplate` — shows current narration

Voice Control (iOS 27):
- "What's the nearest mural?" → sort by distance, speak the closest
- Available as overlay on any template

## Photo Editing Extension

Purpose: replace Photoshop for platinum/palladium digital negative workflow.

Pipeline:
1. Receive full-resolution 16-bit image from Photos
2. Convert to grayscale (Rec709 luminance)
3. Apply calibrated tone curve (CIToneCurve or custom CIKernel)
4. Invert (CIColorInvert)
5. Return to Photos

Curve stored as JSON control points in the app bundle or fetched from tube:
```json
{"points": [[0,0], [0.25,0.15], [0.50,0.45], [0.75,0.80], [1.0,1.0]]}
```

Print: exported from Photos → QTR or Preview (no color management). Photos' own print path applies ICC profiles — not suitable for alt-process negatives.

## iOS Design — Branding Principles

Two layers:
- **UI layer** — native navigation (tab bar, toolbars, context menus). Use standard components. Liquid Glass. Don't customize what people already know.
- **Content layer** — brand canvas. Imagery, color, typography, motion. Express identity here.

Rules:
- Color in the scroll view, not on toolbars
- Support Dark Mode
- Support Dynamic Type (custom fonts must scale)
- Logos understated — don't remind people which app they're in
- SF Symbols for utilitarian icons; custom icons for brand moments
- Transitions via SwiftUI Zoom Transitions for fluid navigation
- Motion reinforces hierarchy — spring animations, scroll-triggered

## The contract

Every provider implements:
- `list(path:) → [NSFileProviderItem]`
- `fetch(path:) → Data`

Providers call `TubeRequest.shared` which signs requests with Secure Enclave key and POSTs to `https://thetube.today/tube/{route}`.

## Tour Data Format

Markdown with embedded JSON:

```markdown
---
title: Tucumcari Murals
type: tour
region: Tucumcari, NM
---

55 murals on Route 66. Start at Motel Safari.

\```json # data waypoints
[{"name":"Mother Road","lat":35.171404,"lon":-103.717850,"desc":"Motel Safari"}]
\```
```

Prose for humans/AI. JSON block for machines. Same pattern as `# src` for Swift code extraction.

Published as:
- `/tours/index.json` — feed of all tours
- `/tours/{slug}.json` — waypoints for one tour
- `/tours/{slug}.html` — MapKit JS interactive map
- Bundled in app for offline use

## Namespace

```
/
  logs/
    {date}/
      {hour}.tsv
  aws/
    cloudfront/
    lambda/
    s3/
  tube/
    locker/
    routes/
    devices/
      index.json
  tours/
    index.json
    tucumcari-murals.json
    tucumcari-murals.html
```

## Constraints

- Read-only filesystem (writes through share extension or send-tube)
- No third-party dependencies (Foundation, CryptoKit, FileProvider, Security, AVFoundation, CarPlay)
- Swift 5.9+, async/await, actors
- macOS 13+ / iOS 16+ (minimum for replicated FileProvider)
- CarPlay features: iOS 27+ for Voice Control overlay, thumbnails, details header
- No Spotlight indexing

## Build

```bash
./extract.sh        # pulls # src blocks from *.md into out/
open TubeFS.xcodeproj
```

## Related

- `trsvax/theTube-mcp` — Node WebDAV server (same namespace, same protocol)
- `trsvax/thetube-private` — Lambda source (ticket machine, processor)
- `trsvax/theTube` — Platform spec, tour pages at /tours/
- Apple Landmarks sample app — CarPlay audio reference implementation
- Apple Wishlist sample app — SwiftUI travel planner reference

